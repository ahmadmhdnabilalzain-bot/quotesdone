-- AN ARABIC QUESTION FINDS THE SAME KNOWLEDGE AS AN ENGLISH ONE. Seat: it_engineer (shared platform). 23 Sep 2026.
--
-- MEASURED 23 Sep 2026 (scripts/eval/multilingual_recall_eval.mjs: every verified pack's eval question, asked in
-- English AND Arabic, recall@5 through the ranking below, 2,188 questions over 6 seats; numbers in the PR).
--   * Every vector the seats reason from is gte-small (Supabase.ai.Session), an English-only model — Supabase's
--     own docs: "exclusively caters to English texts". Arabic recall@5 was 0.000-0.067 on every seat, and an
--     Arabic case situation scored 0.722-0.849 against its English twin, under fn_case_recall's 0.84 floor.
--   * support_knowledge (408) and ceo_knowledge (508) carry NO vector: 916 rows two seats cannot reach by meaning.
--   * English recall@5 was weakest for ceo (0.411) and accountant (0.465) in PR #897's run; this eval, with the
--     kb_chunks that compete for those questions in the pool, reproduces it: ceo 0.396, accountant 0.465. The
--     SAME questions without kb_chunks score accountant 0.771 and ceo 0.521: the 150,103 general reference rows
--     out-rank the seat's own knowledge in fn_reason_retrieve's single union ranking. That is the cause, and it
--     is fixed in the ranking (the seat's own knowledge first), not by lowering a bar.
--   * Xenova/multilingual-e5-small alone lifts Arabic to 0.63-0.82 but costs English (it_engineer 0.794 ->
--     0.675 against gte-small with the same own-first ranking). Fusing both spaces by reciprocal rank, each
--     weighted by how decisive it is for THIS question (its best similarity minus its 21st: an Arabic question is
--     flat under gte-small, so gte-small steps aside by itself — no language test, no word list), gives, with
--     kb_chunks in the pool: EN sales 0.617->0.717, support 0.626->0.730, accountant 0.465->0.715, ceo
--     0.396->0.583, it 0.728->0.811, marketing 0.600->0.750; AR 0.000-0.067 -> 0.517-0.609. That is this file.
--
-- WHAT THIS CHANGES.
--   1. public.knowledge_vector_ml — one multilingual-e5-small vector (MIT, 384-d, ~100 languages incl. Arabic)
--      per row of every source the seats reason from. Run in the edge runtime by transformers.js on the runtime's
--      own ONNX session: free, in-region, not OpenRouter. Same 384 dimensions as gte-small, a DIFFERENT space:
--      never compared with an embedding_gte column, which is why it is a side table and not those columns.
--      support_knowledge and ceo_knowledge gain embedding_gte (the same column PR #892 adds; "if not exists"),
--      filled by the same queue, so every source is in both spaces.
--   2. public.v_knowledge_ml_source — the text each source becomes and its backfill priority, in one place.
--   3. fn_ml_embed_claim / fn_ml_embed_write — the queue: gated by app_secrets 'ml_embed_golive', capped at
--      'ml_embed_daily_cap' rows a day, both SET ON APPLY below (the founder approved finishing this). At most
--      64 rows a claim with a 5-minute lease; a row is written back only if its text is still the text that was
--      embedded. No bulk UPDATE or DELETE: the 21 Sep purge that restarted production was one statement over
--      50,000 rows; the largest statement here writes one row.
--   4. A trigger per source drops a row's multilingual vector when its text changes or it is deleted, so the
--      queue embeds it again (and, for support/ceo, its gte vector with it).
--   5. fn_ml_read_space() — 'gte' until every source except kb_chunks is embedded, then 'ml' (recorded once in
--      knowledge_ml_status); app_secrets 'ml_embed_read' = 'gte' | 'ml' overrides. kb_chunks, the bulk of the
--      backlog, joins as it fills.
--   6. fn_reason_retrieve_ml(seat, ml vector, gte vector, k, own) — the fused search above, with the seat's own
--      rows keeping 3 of the top slots when it has them, reading ceo_knowledge and support_knowledge for their
--      seats. Same answer shape as fn_reason_retrieve; 'similarity' is the multilingual one.
--   7. fn_case_recall_ml — fn_case_recall in the multilingual space. Floor 0.85, measured for this model
--      (scripts/eval/case_recall_floor_calibration.mjs): same case EN 0.876-0.954, AR 0.803-0.899; different
--      case 0.759-0.849. gte-small's 0.84 is not inherited: another model is another scale.
--   8. resilience_step 'mlEmbed' — new and changed rows after the backfill, 8 a tick.
--
-- WHAT IT DOES NOT CHANGE. The embedding_gte columns and every routine reading them stay: gte-small remains the
-- path whenever the multilingual embedder is unavailable (the caller falls back; a vector is never put to the
-- other space's routine). The per-seat assist routines (fn_sales_assist, fn_accountant_assist,
-- fn_it_engineer_assist, fn_marketing_assist, fn_faq_answer) keep gte-small and their calibrated thresholds:
-- moving each is its own recalibration. leads, taxonomy_trade_service and llm_cache are not seat knowledge.
--
-- LOCKS. The triggers touch eleven live tables. A rolled-back replay of an earlier draft deadlocked with a live
-- session because "drop trigger if exists" takes ACCESS EXCLUSIVE, and a queued ACCESS EXCLUSIVE blocks every
-- later reader (the mechanism of the 21 Sep apply that locked sign-in). So "create or replace trigger" (SHARE
-- ROW EXCLUSIVE: writers wait, readers never do) and a 3-second lock_timeout, so an apply that cannot get a
-- lock fails and is re-run instead of queueing in front of the company's traffic.
--
-- Pending: scripts/sql/pending/an_arabic_question_finds_the_same_knowledge_as_an_english_one.txt.
-- Proved by: scripts/kb/probe_multilingual_space.mjs (this file + its routines in one aborted transaction).
set local lock_timeout = '3s';

-- ── 1. the vectors ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.knowledge_vector_ml (
  src         text not null check (src in ('seat_case_memory', 'ceo_knowledge', 'support_knowledge', 'accountant_knowledge',
                'it_engineer_knowledge', 'sales_knowledge', 'company_faq', 'agent_knowledge', 'ops_knowledge',
                'reasoning_knowledge_candidate', 'kb_chunks')),
  row_id      text not null,
  text_hash   text not null,
  embedding   vector(384) not null,
  embedded_at timestamptz not null default now(),
  primary key (src, row_id)
);
comment on table public.knowledge_vector_ml is
  'Multilingual-e5-small (384-d) vector of every row the seats reason from. A different space from embedding_gte: never compared with it. Written only by fn_ml_embed_write. Script: an_arabic_question_finds_the_same_knowledge_as_an_english_one.sql.';
-- kb_chunks is the only source big enough to need an index; every other source is scanned exactly (about 15k
-- rows in all), which misses nothing. The index is partial so the planner uses it only for kb_chunks.
create index if not exists knowledge_vector_ml_kb_hnsw on public.knowledge_vector_ml
  using hnsw (embedding vector_cosine_ops) where src = 'kb_chunks';
create index if not exists knowledge_vector_ml_day_idx on public.knowledge_vector_ml (embedded_at);
alter table public.knowledge_vector_ml enable row level security;
drop policy if exists knowledge_vector_ml_service_role_only on public.knowledge_vector_ml;
create policy knowledge_vector_ml_service_role_only on public.knowledge_vector_ml
  as permissive for all to public using (false) with check (false);
revoke all on public.knowledge_vector_ml from anon, authenticated;

create table if not exists public.knowledge_ml_claim (
  src        text not null,
  row_id     text not null,
  claimed_at timestamptz not null default now(),
  primary key (src, row_id)
);
comment on table public.knowledge_ml_claim is 'The 5-minute lease on a row being embedded into knowledge_vector_ml. Removed by fn_ml_embed_write.';
alter table public.knowledge_ml_claim enable row level security;
drop policy if exists knowledge_ml_claim_service_role_only on public.knowledge_ml_claim;
create policy knowledge_ml_claim_service_role_only on public.knowledge_ml_claim
  as permissive for all to public using (false) with check (false);
revoke all on public.knowledge_ml_claim from anon, authenticated;

create table if not exists public.knowledge_ml_status (
  id                    boolean primary key default true check (id),
  priority_complete_at  timestamptz,
  note                  text
);
comment on table public.knowledge_ml_status is
  'One row. priority_complete_at: when every source except kb_chunks was first fully embedded in knowledge_vector_ml; fn_ml_read_space reads it.';
alter table public.knowledge_ml_status enable row level security;
drop policy if exists knowledge_ml_status_service_role_only on public.knowledge_ml_status;
create policy knowledge_ml_status_service_role_only on public.knowledge_ml_status
  as permissive for all to public using (false) with check (false);
revoke all on public.knowledge_ml_status from anon, authenticated;
insert into public.knowledge_ml_status (id) values (true) on conflict (id) do nothing;

-- The two seat tables with no gte-small column. Same definition as PR #892's, so whichever applies first wins
-- and the other is a no-op. 408 + 508 rows: an exact scan, no index.
alter table public.support_knowledge add column if not exists embedding_gte vector(384);
alter table public.ceo_knowledge     add column if not exists embedding_gte vector(384);

-- ── 2. the text each source becomes, and the order it is embedded in ─────────────────────────────
-- priority 1 case memory, 2 the seats' own knowledge (ceo and support first: they had none), 3 company-wide,
-- 9 kb_chunks. The filters are what fn_reason_retrieve_ml can read, so nothing is embedded that no seat reads.
create or replace view public.v_knowledge_ml_source with (security_invoker = true) as
  select 'seat_case_memory'::text src, m.id::text row_id, null::text title, m.situation body, 1 priority from public.seat_case_memory m
  union all select 'ceo_knowledge', c.record_id, c.title, c.body, 2 from public.ceo_knowledge c
  union all select 'support_knowledge', s.record_id, s.title, s.body, 2 from public.support_knowledge s
  union all select 'accountant_knowledge', a.record_id, a.title, a.content, 2 from public.accountant_knowledge a where a.runtime_index_eligible
  union all select 'it_engineer_knowledge', i.record_id, i.title, i.content, 2 from public.it_engineer_knowledge i where i.runtime_index_eligible
  union all select 'sales_knowledge', s.record_id, s.title, s.content, 2 from public.sales_knowledge s where s.runtime_index_eligible
  union all select 'company_faq', f.id::text, f.question, f.answer, 3 from public.company_faq f where f.status = 'approved'
  union all select 'agent_knowledge', g.id::text, g.topic, g.content, 3 from public.agent_knowledge g
     where g.agent_key in ('_global', 'ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing')
  union all select 'ops_knowledge', o.record_id, o.title, o.content, 3 from public.ops_knowledge o
     where o.runtime_eligible and o.supersession_state = 'current' and o.scope_type in ('company', 'external_source', 'category')
  union all select 'reasoning_knowledge_candidate', r.id::text, r.question, r.finding, 3 from public.reasoning_knowledge_candidate r where r.status <> 'rejected'
  union all select 'kb_chunks', k.id::text, k.title, k.content, 9 from public.kb_chunks k;
revoke all on public.v_knowledge_ml_source from public, anon, authenticated;
comment on view public.v_knowledge_ml_source is 'The text every source the seats reason from is embedded from into knowledge_vector_ml, and its backfill priority.';

-- ── 3. the gate, the cap and the queue ──────────────────────────────────────────────────────────
-- SET ON APPLY: the founder approved finishing this (23 Sep 2026). 25,000 rows a day: every source but kb_chunks
-- (about 15,000 rows) on the first day, kb_chunks (150,103) over about six more.
insert into public.app_secrets (key, value) values ('ml_embed_golive', 'true'), ('ml_embed_daily_cap', '25000')
  on conflict (key) do update set value = excluded.value;
insert into public.app_secrets (key, value) values ('ml_embed_read', 'auto') on conflict (key) do nothing;

create or replace function public.fn_ml_embed_claim(p_limit integer default 16)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_go     text := (select value from public.app_secrets where key = 'ml_embed_golive');
  v_cap    integer := coalesce((select nullif(value, '')::integer from public.app_secrets where key = 'ml_embed_daily_cap'), 0);
  v_today  integer;
  v_want   integer;
  v_rows   jsonb := '[]'::jsonb;
  v_src    text;
  v_part   jsonb;
  v_reached_kb boolean := false;
begin
  if coalesce(v_go, 'false') <> 'true' then
    return jsonb_build_object('ok', true, 'rows', v_rows, 'reason', 'ml_embed_golive is not true');
  end if;
  select count(*) into v_today from public.knowledge_vector_ml where embedded_at >= date_trunc('day', now());
  v_want := least(greatest(coalesce(p_limit, 16), 1), 64, greatest(v_cap - v_today, 0));
  if v_want = 0 then
    return jsonb_build_object('ok', true, 'rows', v_rows, 'reason', 'daily cap reached', 'today', v_today, 'cap', v_cap);
  end if;
  delete from public.knowledge_ml_claim where claimed_at < now() - interval '5 minutes';
  -- One source at a time, in priority order: each query is a limited anti-join on one table's key (the view
  -- prunes every other branch on src) and stops as soon as it has enough rows.
  for v_src in select unnest(array['seat_case_memory', 'ceo_knowledge', 'support_knowledge', 'accountant_knowledge',
      'it_engineer_knowledge', 'sales_knowledge', 'company_faq', 'agent_knowledge', 'ops_knowledge',
      'reasoning_knowledge_candidate', 'kb_chunks']) loop
    exit when jsonb_array_length(v_rows) >= v_want;
    -- Reaching kb_chunks with nothing claimed means every earlier source had nothing unclaimed. Only THIS
    -- proves the priority sources are done; an empty answer for another reason (the cap, the gate) proves nothing.
    if v_src = 'kb_chunks' and jsonb_array_length(v_rows) = 0 then v_reached_kb := true; end if;
    with pick as (
      select s.src, s.row_id, s.title, s.body
        from public.v_knowledge_ml_source s
       where s.src = v_src and btrim(coalesce(s.body, '')) <> ''
         and not exists (select 1 from public.knowledge_vector_ml v where v.src = s.src and v.row_id = s.row_id)
         and not exists (select 1 from public.knowledge_ml_claim c where c.src = s.src and c.row_id = s.row_id)
       limit v_want - jsonb_array_length(v_rows)
    ), claimed as (
      insert into public.knowledge_ml_claim (src, row_id) select src, row_id from pick
      on conflict do nothing returning src, row_id
    )
    select coalesce(jsonb_agg(jsonb_build_object('src', p.src, 'row_id', p.row_id, 'title', p.title,
             'body', left(p.body, 8000), 'hash', md5(coalesce(p.title, '') || E'\n' || coalesce(p.body, '')))), '[]'::jsonb)
      into v_part
      from pick p join claimed c using (src, row_id);
    v_rows := v_rows || v_part;
  end loop;
  -- The read switch: the first time nothing but kb_chunks is left, the seats may read the ml space.
  if v_reached_kb and (select priority_complete_at from public.knowledge_ml_status) is null
     and not exists (select 1 from public.knowledge_ml_claim c where c.src <> 'kb_chunks') then
    update public.knowledge_ml_status set priority_complete_at = now(),
      note = 'every source except kb_chunks embedded; fn_ml_read_space answers ml unless ml_embed_read overrides'
     where id and priority_complete_at is null;
  end if;
  return jsonb_build_object('ok', true, 'rows', v_rows, 'today', v_today, 'cap', v_cap);
end $fn$;
revoke execute on function public.fn_ml_embed_claim(integer) from public, anon, authenticated;
grant execute on function public.fn_ml_embed_claim(integer) to service_role;

-- Writes the row's multilingual vector (and, for support/ceo, its gte-small vector) only if the source text is
-- still the text the caller embedded (p_hash); otherwise the lease is dropped and the row is claimed again.
-- Both are 384-d, so the database cannot tell which model made a vector: that p_embedding is multilingual and
-- p_embedding_gte is gte-small is guaranteed by the one caller, _shared/ml_embed.ts embedQueueOnce (embedRaw and
-- embedLine respectively). Execute is service_role only.
create or replace function public.fn_ml_embed_write(p_src text, p_row_id text, p_hash text, p_embedding vector(384),
  p_embedding_gte vector(384) default null)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare v_now_hash text;
begin
  if p_embedding is null then raise exception 'fn_ml_embed_write: no vector for %/%', p_src, p_row_id; end if;
  if p_src in ('support_knowledge', 'ceo_knowledge') and p_embedding_gte is null then
    raise exception 'fn_ml_embed_write: % rows carry their gte-small vector too', p_src;
  end if;
  select md5(coalesce(s.title, '') || E'\n' || coalesce(s.body, '')) into v_now_hash
    from public.v_knowledge_ml_source s where s.src = p_src and s.row_id = p_row_id;
  delete from public.knowledge_ml_claim where src = p_src and row_id = p_row_id;
  if v_now_hash is distinct from p_hash then return false; end if;
  insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values (p_src, p_row_id, p_hash, p_embedding)
  on conflict (src, row_id) do update set text_hash = excluded.text_hash, embedding = excluded.embedding, embedded_at = now();
  if p_src = 'support_knowledge' then
    update public.support_knowledge set embedding_gte = p_embedding_gte where record_id = p_row_id;
  elsif p_src = 'ceo_knowledge' then
    update public.ceo_knowledge set embedding_gte = p_embedding_gte where record_id = p_row_id;
  end if;
  return true;
end $fn$;
revoke execute on function public.fn_ml_embed_write(text, text, text, vector, vector) from public, anon, authenticated;
grant execute on function public.fn_ml_embed_write(text, text, text, vector, vector) to service_role;

-- ── 4. a changed or deleted row loses its vector, so the queue embeds it again ──────────────────
-- TG_ARGV[0] = the src name, TG_ARGV[1] = the key column. One row per firing, never a bulk delete.
create or replace function public.fn_ml_vectors_stale()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  delete from public.knowledge_vector_ml where src = tg_argv[0] and row_id = to_jsonb(old) ->> tg_argv[1];
  return null;
end $fn$;
revoke execute on function public.fn_ml_vectors_stale() from public, anon, authenticated;

create or replace trigger z_ml_vectors_stale after update of situation or delete on public.seat_case_memory
  for each row execute function public.fn_ml_vectors_stale('seat_case_memory', 'id');
create or replace trigger z_ml_vectors_stale after update of title, body or delete on public.ceo_knowledge
  for each row execute function public.fn_ml_vectors_stale('ceo_knowledge', 'record_id');
create or replace trigger z_ml_vectors_stale after update of title, body or delete on public.support_knowledge
  for each row execute function public.fn_ml_vectors_stale('support_knowledge', 'record_id');
create or replace trigger z_ml_vectors_stale after update of title, content or delete on public.accountant_knowledge
  for each row execute function public.fn_ml_vectors_stale('accountant_knowledge', 'record_id');
create or replace trigger z_ml_vectors_stale after update of title, content or delete on public.it_engineer_knowledge
  for each row execute function public.fn_ml_vectors_stale('it_engineer_knowledge', 'record_id');
create or replace trigger z_ml_vectors_stale after update of title, content or delete on public.sales_knowledge
  for each row execute function public.fn_ml_vectors_stale('sales_knowledge', 'record_id');
create or replace trigger z_ml_vectors_stale after update of question, answer or delete on public.company_faq
  for each row execute function public.fn_ml_vectors_stale('company_faq', 'id');
create or replace trigger z_ml_vectors_stale after update of topic, content or delete on public.agent_knowledge
  for each row execute function public.fn_ml_vectors_stale('agent_knowledge', 'id');
create or replace trigger z_ml_vectors_stale after update of title, content or delete on public.ops_knowledge
  for each row execute function public.fn_ml_vectors_stale('ops_knowledge', 'record_id');
create or replace trigger z_ml_vectors_stale after update of question, finding or delete on public.reasoning_knowledge_candidate
  for each row execute function public.fn_ml_vectors_stale('reasoning_knowledge_candidate', 'id');
create or replace trigger z_ml_vectors_stale after update of title, content or delete on public.kb_chunks
  for each row execute function public.fn_ml_vectors_stale('kb_chunks', 'id');

-- ── 5. which space the seats read ───────────────────────────────────────────────────────────────
create or replace function public.fn_ml_read_space()
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case coalesce((select value from public.app_secrets where key = 'ml_embed_read'), 'auto')
           when 'gte' then 'gte'
           when 'ml' then 'ml'
           else case when (select priority_complete_at from public.knowledge_ml_status) is not null then 'ml' else 'gte' end
         end;
$fn$;
revoke execute on function public.fn_ml_read_space() from public, anon, authenticated;
grant execute on function public.fn_ml_read_space() to service_role;

-- ── 6. the knowledge search over both spaces ────────────────────────────────────────────────────
-- Same contract as fn_reason_retrieve: a jsonb array of {source, id, title, excerpt, citation, similarity, trust},
-- k * 2 rows, best first; plus 'own' and 'score'. 'similarity' is the multilingual cosine (think.ts compares it
-- with CORROBORATION_FLOOR_ML).
--
-- HOW A ROW IS RANKED (the measured variant in scripts/eval/multilingual_recall_eval.mjs, same N, same K, same OWN):
--   candidates  per source, the N = 20 nearest in EACH space (multilingual from knowledge_vector_ml, gte-small
--               from the source's own embedding_gte), so each source uses its own index.
--   fusion      score = wg / (60 + rank under gte) + wm / (60 + rank under ml), ranks over the candidates; a space
--               the row has no vector in adds nothing. wg and wm are each space's decisiveness for THIS question
--               — its best similarity minus its 21st — divided by their sum. An Arabic question is flat under
--               gte-small, so gte-small's weight falls by itself. No language test, no word list.
--   per source  the best K by score, as fn_reason_retrieve takes the best K by distance.
--   own first   the seat's own rows (its table; for customer_support the trade packs; agent_knowledge under its
--               own key) come FIRST, up to p_own of them, then everything else by score, k * 2 rows in all — so
--               the first five a caller reads are the seat's best three and the two best of the rest. kb_chunks'
--               150k general rows had been out-ranking the seat's own verified knowledge.
create or replace function public.fn_reason_retrieve_ml(p_seat text, p_embedding vector(384), p_embedding_gte vector(384) default null,
  p_k integer default 6, p_own integer default 3)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  k    integer := greatest(1, least(coalesce(p_k, 6), 12));
  own  integer := greatest(0, least(coalesce(p_own, 3), 2 * k));
  n    constant integer := 20;
  g    vector(384) := p_embedding_gte;
  m    vector(384) := p_embedding;
  out  jsonb := '[]'::jsonb;
begin
  if m is null then return out; end if;
  with cand as (
    -- kb_chunks: both spaces through their HNSW indexes
    (select 'kb_chunks' src, v.row_id from public.knowledge_vector_ml v where v.src = 'kb_chunks' order by v.embedding <=> m limit n)
    union (select 'kb_chunks', c.id::text from public.kb_chunks c where g is not null and c.embedding_gte is not null order by c.embedding_gte <=> g limit n)
    union (select 'ops_knowledge', o.record_id from public.knowledge_vector_ml v join public.ops_knowledge o on v.src = 'ops_knowledge' and o.record_id = v.row_id
            where o.runtime_eligible and o.supersession_state = 'current' and o.scope_type in ('company', 'external_source', 'category')
            order by v.embedding <=> m limit n)
    union (select 'ops_knowledge', o.record_id from public.ops_knowledge o
            where g is not null and o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
              and o.scope_type in ('company', 'external_source', 'category') order by o.embedding_gte <=> g limit n)
    union (select 'agent_knowledge', a.id::text from public.knowledge_vector_ml v join public.agent_knowledge a on v.src = 'agent_knowledge' and a.id::text = v.row_id
            where a.agent_key in (p_seat, '_global') order by v.embedding <=> m limit n)
    union (select 'agent_knowledge', a.id::text from public.agent_knowledge a
            where g is not null and a.embedding_gte is not null and a.agent_key in (p_seat, '_global') order by a.embedding_gte <=> g limit n)
    union (select 'company_faq', f.id::text from public.knowledge_vector_ml v join public.company_faq f on v.src = 'company_faq' and f.id::text = v.row_id
            where f.status = 'approved' order by v.embedding <=> m limit n)
    union (select 'company_faq', f.id::text from public.company_faq f
            where g is not null and f.embedding_gte is not null and f.status = 'approved' order by f.embedding_gte <=> g limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text from public.knowledge_vector_ml v
             join public.reasoning_knowledge_candidate r on v.src = 'reasoning_knowledge_candidate' and r.id::text = v.row_id
            where r.status <> 'rejected' order by v.embedding <=> m limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text from public.reasoning_knowledge_candidate r
            where g is not null and r.embedding_gte is not null and r.status <> 'rejected' order by r.embedding_gte <=> g limit n)
    -- sales_knowledge: the sales engineer reads all of it; customer_support reads the TRADE packs (what a trade
    -- needs), never the sales seat's own playbook
    union (select 'sales_knowledge', s.record_id from public.knowledge_vector_ml v join public.sales_knowledge s on v.src = 'sales_knowledge' and s.record_id = v.row_id
            where s.runtime_index_eligible and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and exists (select 1 from unnest(s.tags) t where t like 'trade:%')))
            order by v.embedding <=> m limit n)
    union (select 'sales_knowledge', s.record_id from public.sales_knowledge s
            where g is not null and s.embedding_gte is not null and s.runtime_index_eligible
              and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and exists (select 1 from unnest(s.tags) t where t like 'trade:%')))
            order by s.embedding_gte <=> g limit n)
    union (select 'accountant_knowledge', s.record_id from public.knowledge_vector_ml v join public.accountant_knowledge s on v.src = 'accountant_knowledge' and s.record_id = v.row_id
            where p_seat = 'accountant' and s.runtime_index_eligible order by v.embedding <=> m limit n)
    union (select 'accountant_knowledge', s.record_id from public.accountant_knowledge s
            where p_seat = 'accountant' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible order by s.embedding_gte <=> g limit n)
    union (select 'it_engineer_knowledge', s.record_id from public.knowledge_vector_ml v join public.it_engineer_knowledge s on v.src = 'it_engineer_knowledge' and s.record_id = v.row_id
            where p_seat = 'it_engineer' and s.runtime_index_eligible order by v.embedding <=> m limit n)
    union (select 'it_engineer_knowledge', s.record_id from public.it_engineer_knowledge s
            where p_seat = 'it_engineer' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible order by s.embedding_gte <=> g limit n)
    union (select 'ceo_knowledge', v.row_id from public.knowledge_vector_ml v where p_seat = 'ceo' and v.src = 'ceo_knowledge' order by v.embedding <=> m limit n)
    union (select 'ceo_knowledge', s.record_id from public.ceo_knowledge s
            where p_seat = 'ceo' and g is not null and s.embedding_gte is not null order by s.embedding_gte <=> g limit n)
    union (select 'support_knowledge', v.row_id from public.knowledge_vector_ml v where p_seat = 'customer_support' and v.src = 'support_knowledge' order by v.embedding <=> m limit n)
    union (select 'support_knowledge', s.record_id from public.support_knowledge s
            where p_seat = 'customer_support' and g is not null and s.embedding_gte is not null order by s.embedding_gte <=> g limit n)
  ), sims as (
    -- both similarities for every candidate; a CASE evaluates only its own branch, so a text key is never cast
    select c.src, c.row_id,
           (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = c.src and v.row_id = c.row_id) s_ml,
           case when g is null then null else case c.src
             when 'kb_chunks' then (select 1 - (x.embedding_gte <=> g) from public.kb_chunks x where x.id = c.row_id::bigint)
             when 'ops_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.ops_knowledge x where x.record_id = c.row_id)
             when 'agent_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.agent_knowledge x where x.id = c.row_id::bigint)
             when 'company_faq' then (select 1 - (x.embedding_gte <=> g) from public.company_faq x where x.id = c.row_id::bigint)
             when 'reasoning_knowledge_candidate' then (select 1 - (x.embedding_gte <=> g) from public.reasoning_knowledge_candidate x where x.id = c.row_id::bigint)
             when 'sales_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.sales_knowledge x where x.record_id = c.row_id)
             when 'accountant_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.accountant_knowledge x where x.record_id = c.row_id)
             when 'it_engineer_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.it_engineer_knowledge x where x.record_id = c.row_id)
             when 'ceo_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.ceo_knowledge x where x.record_id = c.row_id)
             when 'support_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.support_knowledge x where x.record_id = c.row_id)
           end end s_gte
      from cand c
  ), ranked as (
    select s.*,
           case when s_ml is not null then row_number() over (order by s_ml desc nulls last) end r_ml,
           case when s_gte is not null then row_number() over (order by s_gte desc nulls last) end r_gte
      from sims s
  ), gaps as (
    -- decisiveness: best minus 21st (or the last, when there are fewer candidates)
    select coalesce(max(s_ml) - coalesce(max(s_ml) filter (where r_ml = n + 1), min(s_ml)), 0) d_ml,
           coalesce(max(s_gte) - coalesce(max(s_gte) filter (where r_gte = n + 1), min(s_gte)), 0) d_gte
      from ranked
  ), scored as (
    select r.*,
           coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_ml / (gp.d_ml + gp.d_gte) else 1 end / (60 + r.r_ml), 0)
         + coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_gte / (gp.d_ml + gp.d_gte) else 0 end / (60 + r.r_gte), 0) score
      from ranked r cross join gaps gp
  ), hits as (
    -- a bigint key is cast only inside its own source's rows (scored is materialised; the filter runs first)
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation, sc.s_ml, sc.score, 'reviewed' trust, false mine
       from (select *, row_id::bigint key from scored where src = 'kb_chunks') sc join public.kb_chunks c on c.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path, sc.s_ml, sc.score, 'reviewed', false
       from scored sc join public.ops_knowledge o on sc.src = 'ops_knowledge' and o.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref, sc.s_ml, sc.score, 'reviewed', a.agent_key = p_seat
       from (select *, row_id::bigint key from scored where src = 'agent_knowledge') sc join public.agent_knowledge a on a.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id, sc.s_ml, sc.score, 'reviewed', false
       from (select *, row_id::bigint key from scored where src = 'company_faq') sc join public.company_faq f on f.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url', sc.s_ml, sc.score,
            case when r.status = 'approved' then 'reviewed' else 'pending_review' end, false
       from (select *, row_id::bigint key from scored where src = 'reasoning_knowledge_candidate') sc join public.reasoning_knowledge_candidate r on r.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.sales_knowledge s on sc.src = 'sales_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.accountant_knowledge s on sc.src = 'accountant_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.it_engineer_knowledge s on sc.src = 'it_engineer_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.ceo_knowledge s on sc.src = 'ceo_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.support_knowledge s on sc.src = 'support_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
  ), own_rows as (
    select * from hits where mine order by score desc limit own
  ), chosen as (
    select o.*, true reserved from own_rows o
    union all
    select *, false from (select h.* from hits h where not exists (select 1 from own_rows o where o.src = h.src and o.id = h.id)
                    order by h.score desc limit greatest(k * 2 - (select count(*) from own_rows), 0)) rest
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(coalesce(s_ml, 0)::numeric, 4), 'score', round(score::numeric, 6),
           'trust', trust, 'own', mine) order by reserved desc, score desc), '[]'::jsonb)
    into out
    from chosen;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve_ml(text, vector, vector, integer, integer) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_ml(text, vector, vector, integer, integer) to service_role;

-- ── 7. case memory in the multilingual space ────────────────────────────────────────────────────
-- fn_case_recall's rules, unchanged (exact scan, other seats, case kind, the exact-trade rule, the exclusion,
-- the +0.05 for a corrected case in the ranking only); the vector is the case's row in knowledge_vector_ml.
create or replace function public.fn_case_recall_ml(
  p_seat text, p_embedding vector(384), p_trade text default null, p_k integer default 5,
  p_case_kind text default null, p_other_seats boolean default true, p_floor real default 0.85,
  p_exclude_source_table text default null, p_exclude_source_id text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  v_trade text := nullif(lower(btrim(p_trade)), '');
  v_out   jsonb;
begin
  if p_embedding is null then
    return jsonb_build_object('ok', false, 'reason', 'no_embedding', 'cases', '[]'::jsonb);
  end if;
  with c as (
    select m.*, (1 - (v.embedding <=> p_embedding))::real as sim
      from public.knowledge_vector_ml v
      join public.seat_case_memory m on v.src = 'seat_case_memory' and m.id::text = v.row_id
     where (p_other_seats or m.seat = p_seat)
       and (p_case_kind is null or m.case_kind = p_case_kind)
       and (v_trade is null or m.trade is null or m.trade = v_trade)
       and (m.source_table, m.source_id) is distinct from (p_exclude_source_table, p_exclude_source_id)
  ), top as (
    select * from c where sim >= coalesce(p_floor, 0.85)
     order by sim + case when correction is not null then 0.05 else 0 end desc
     limit greatest(1, least(coalesce(p_k, 5), 20))
  )
  -- The answer is fn_case_recall's, key for key (the source is named only to its own seat), plus 'space'.
  select coalesce(jsonb_agg(jsonb_build_object(
           'case_id', t.id, 'seat', t.seat, 'case_kind', t.case_kind, 'trade', t.trade,
           'situation', t.situation, 'decision', t.decision, 'reasoning', t.reasoning,
           'outcome', t.outcome, 'finalised', t.finalised, 'finalised_at', t.finalised_at,
           'lessons', to_jsonb(t.lessons), 'correction', t.correction, 'corrected_by', t.corrected_by,
           'similarity', round(t.sim::numeric, 3), 'opened_at', t.opened_at,
           'source', case when t.seat = p_seat then t.source_table || ':' || t.source_id end)
         order by t.sim + case when t.correction is not null then 0.05 else 0 end desc), '[]'::jsonb)
    into v_out from top t;
  return jsonb_build_object('ok', true, 'space', 'ml', 'floor', coalesce(p_floor, 0.85), 'cases', v_out,
                            'finalised_precedent', exists (select 1 from jsonb_array_elements(v_out) e where (e->>'finalised')::boolean));
end $fn$;
revoke execute on function public.fn_case_recall_ml(text, vector, text, integer, text, boolean, real, text, text) from public, anon, authenticated;
grant execute on function public.fn_case_recall_ml(text, vector, text, integer, text, boolean, real, text, text) to service_role;

-- ── 8. on the heartbeat: new and changed rows after the backfill ─────────────────────────────────
-- The backlog is drained by .github/workflows/ml-embed-backfill.yml (the clock that can hold a connection
-- for 30 minutes). This step embeds what arrives afterwards: resilience_ping asks ai_gateway to claim and
-- embed up to 8 rows per tick, the same bound the gte case-memory tick keeps for the edge CPU cap.
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('mlEmbed', interval '15 minutes', 8000, 'plan', 0,
   'knowledge_vector_ml trickle: up to 8 new or changed rows per tick embedded with multilingual-e5-small in ai_gateway (free, in-region, not OpenRouter); gated by ml_embed_golive and ml_embed_daily_cap',
   'it_engineer')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note, owner_seat = excluded.owner_seat;
