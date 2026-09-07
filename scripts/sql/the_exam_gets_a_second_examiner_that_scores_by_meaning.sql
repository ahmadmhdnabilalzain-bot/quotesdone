-- The exam gets a SECOND examiner that scores by meaning, and the estate gets the vectors it needs.
--
-- The founder's objection, verbatim: "but are they doing key word searches to answer?" He is right.
-- fn_certification_exam_sit scores each option with ts_rank_cd plus a trigram tiebreak against the
-- evidence the employee can reach. That is lexical overlap, not meaning: a distractor that happens to
-- share vocabulary with a stored document beats the key, and a key phrased differently from the source
-- loses. bookkeeper sat ACCA at 6/40 = 15% with 25 abstentions under that instrument, and nobody could
-- say how much of that was the instrument and how much was the library.
--
-- This file lays the ground for the second examiner. It creates nothing that scores anything; it only
-- gives the estate the three things a cosine examiner needs and does not have:
--
--   1. certification_exam_question_vector — one gte-small vector per question stem and per option
--      (2,080 x 5 = 10,400 rows), precomputed ONCE by scripts/kb/embed_certification_questions.mjs.
--      vector(384) because that is the estate's dimension: ops_knowledge.embedding_gte, kb_chunks
--      .embedding_gte and company_faq.embedding_gte are all vector(384) (measured on production
--      7 Sep 2026 via pg_attribute.atttypmod), and a vector of any other width — or from any other
--      model — is not comparable with them. Nothing paid ever touches this table: the vectors come
--      from the same free in-region gte-small the whole estate is embedded with.
--
--      This table is EVIDENCE ABOUT THE EMPLOYEES, NEVER MATERIAL FOR THEM. It is deliberately not
--      joined into ops_knowledge, kb_chunks, agent_knowledge or company_faq, and nothing an agent
--      retrieves reads it. scripts/checks/an_exam_answer_never_becomes_knowledge.test.mjs is the guard.
--
--   2. agent_knowledge.embedding_gte — the employee's OWN notes are one of the four evidence sources
--      the lexical sitter reaches for, and they had no vector at all, so a semantic examiner could not
--      see them. 606 rows belong to active employees (measured 7 Sep 2026); the backfill script fills
--      them with the same model.
--
--   3. certification_exam_result.method — 'lexical' or 'semantic'. Every existing row was produced by
--      the ts_rank_cd sitter, so the column defaults to 'lexical' and the backfill stamps the eleven
--      rows already on production. Without it the two examiners' results would mix in
--      fn_certification_exam_summary and neither number would mean anything.
--
-- Apply:
--   node scripts/apply_sql.mjs scripts/sql/the_exam_gets_a_second_examiner_that_scores_by_meaning.sql --apply --ddl

create table if not exists public.certification_exam_question_vector (
  question_id bigint not null references public.certification_exam_question(id) on delete cascade,
  kind        text   not null check (kind in ('stem','A','B','C','D')),
  embedding   vector(384) not null,
  embedded_at timestamptz not null default now(),
  primary key (question_id, kind)
);

comment on table public.certification_exam_question_vector is
  'gte-small vectors for exam stems and options. Evidence ABOUT employees, never material FOR them: never join this into any knowledge store.';

alter table public.certification_exam_question_vector enable row level security;
revoke all on public.certification_exam_question_vector from public, anon, authenticated;

alter table public.agent_knowledge add column if not exists embedding_gte vector(384);

alter table public.certification_exam_result
  add column if not exists method text not null default 'lexical';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'certification_exam_result_method_ck') then
    alter table public.certification_exam_result
      add constraint certification_exam_result_method_ck check (method in ('lexical','semantic'));
  end if;
end $$;

-- The eleven rows on production at the time of writing were all produced by the ts_rank_cd sitter.
update public.certification_exam_result set method = 'lexical' where method is distinct from 'semantic';

-- An index only where it earns its keep. certification_exam_question_vector is read by primary key
-- (question_id, kind) — never by nearest neighbour — so it gets no HNSW index; agent_knowledge is read
-- per employee (at most a few dozen rows) so its vectors are scanned, not indexed.
create index if not exists certification_exam_result_method_idx
  on public.certification_exam_result (agent_key, certification, method, sat_at desc);

do $$
declare v_cols int; v_dim int;
begin
  select count(*) into v_cols from information_schema.columns
   where table_schema='public' and table_name='certification_exam_question_vector';
  select a.atttypmod into v_dim from pg_attribute a join pg_class c on c.oid=a.attrelid
   where c.relname='certification_exam_question_vector' and a.attname='embedding';
  if v_cols < 4 or v_dim <> 384 then
    raise exception 'question vector table is wrong: % columns, dimension %', v_cols, v_dim;
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='agent_knowledge' and column_name='embedding_gte') then
    raise exception 'agent_knowledge.embedding_gte was not created';
  end if;
  if exists (select 1 from public.certification_exam_result where method is null) then
    raise exception 'certification_exam_result.method left null rows';
  end if;
end $$;
