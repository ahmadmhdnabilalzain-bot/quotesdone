-- ONE KNOWLEDGE LIBRARY IS BUILT BESIDE THE NINE STORES AND READ BEHIND A FLAG.
-- Seat: it_engineer. 5 Oct 2026. Ledger 1085, stage 2, PHASE 1 of 2 (stage 1 = #1203, stage 4 = #1204).
--
-- MEASURED 5 Oct 2026 on production (htdblwldjkcgjvmqkbeh), read-only:
--   * Nine stores feed fn_reason_retrieve / fn_reason_retrieve_ml: kb_chunks 148,326 (57,838 once #1204's clause 6
--     takes the uncited qd_kb_pack rows), ops_knowledge 9,140 (1,431 runtime-eligible), agent_knowledge 2,556,
--     sales_knowledge 5,898, accountant 397, it_engineer 415, marketing 282, ceo 790, support 716.
--   * Identical content (md5) ACROSS stores exists only between kb_chunks, agent_knowledge and ops_knowledge
--     (agent+kb 2,024 groups, agent+ops 385). The six seat stores repeat nothing, so no exam id can be merged away
--     (every seat_knowledge_eval_question.expected id is a seat-store record id).
--   * The two readers disagree today on three rules, all of which select the SAME rows on today's data: customer_support
--     reading sales_knowledge (gte: pack 'verified:trade:%'; ml: also any 'trade:' tag; 0 rows differ), ceo/support
--     eligibility (0 ineligible rows), and the ceo/support citation (ml: source_path; gte: coalesce with the pack; 1
--     support row has no source_path). The library takes the wider rule and the coalesced citation.
--   * knowledge_vector_ml holds 51,999 ml vectors keyed by (src, row_id) of the stores.
--
-- WHAT THIS PHASE BUILDS (nothing is read from it until the flag is set; nothing is dropped)
--   knowledge_library         one row per distinct piece of knowledge: content, title, trade, tags, seats[], lang,
--                             source_ref (the citation the reader returns), source_ids (the store's citation list),
--                             verified, runtime_eligible, origin_store/origin_id (the PRIMARY origin, which the reader
--                             returns as source/id so think(), the exam and sales_decision_log.cited are unchanged),
--                             embedding_gte. seats '{*}' = every seat.
--   knowledge_library_origin  EVERY origin row (primary or merged) -> library id, with its own citations. This is the id
--                             map: counts reconcile store by store, and no citation of a merged row is lost.
--   fn_knowledge_library_source(store, id)   each store's row in the library's shape (one place for the mapping).
--   fn_knowledge_library_sync(store, id)     brings ONE origin into line: insert, update, merge an exact duplicate
--                             (kb_chunks / agent_knowledge / ops_knowledge only, the seat union kept), split a merged row
--                             whose text changed, or remove a deleted / excluded one. The ml vector is copied by id
--                             mapping (src 'knowledge_library', row_id = library id) - never re-embedded.
--                             A shared text's primary is chosen by store priority (kb_chunks, ops, agent), never by
--                             arrival order; an eligible text never merges with an ineligible copy.
--   triggers on the nine stores (UPDATE only of the columns the library maps), on knowledge_vector_ml and on
--                             sales_decision_log.cited (a qd_kb_pack row is knowledge exactly while it is cited) call
--                             it, so every existing writer (15 routines, the pack loaders and seed scripts) lands in the
--                             library unchanged until phase 2 switches them. A writer never fails on the library: one
--                             shared advisory lock per transaction, and a row with no text yet stays outside.
--   fn_knowledge_library_fill_page(store, n)  the backfill, at most 5,000 origins per call (default 2,000);
--                             scripts/kb/fill_knowledge_library.mjs drives it at night under the purge's load guard.
--   fn_knowledge_library_reconcile()          rows and citations per store, source vs library.
--   fn_reason_retrieve_library / fn_reason_retrieve_ml_library   the two readers over the library ONLY (plus
--                             company_faq and reasoning_knowledge_candidate, which are not among the nine stores and
--                             stay where they are). Same signatures, same per-store quotas, same predicates, same
--                             output; a store's rows are filtered by origin_store and the seat by seats[].
--   fn_knowledge_library_read()               app_secrets 'knowledge_library_read': 'library' or anything else
--                             = legacy. fn_reason_retrieve and fn_reason_retrieve_ml gain ONE line at the top that hands
--                             the call to the library reader when it says 'library'; every other line is the live body
--                             read back on 5 Oct 2026.
--
-- PROBED 5 Oct 2026 on production, this file plus its _probe in rolled-back transactions (six slices of 8 questions per
-- seat and language, 562 questions; every accountant/ceo/it/marketing question, 48 of ~500 for sales and support):
-- recall@5 library minus legacy, gte path: accountant/en +0.038, it_engineer/en -0.010, every other group 0.000;
-- fused ml path: ceo/ar -0.017, ceo/en -0.007, sales_engineer/en +0.010, every other group 0.000. No group drops more
-- than 0.02. Library call 0.07 s (gte) and 0.10-0.12 s (ml) against 0.015 s and 0.04-0.06 s legacy, with the sampled
-- library; the fill of the eight small stores (~19,000 origins) took 16-22 s with the HNSW indexes off.
--
-- PHASE 2 (its own PR, after this is applied and filled): set the flag, prove the exam, switch the writers to the
-- library, rename the nine stores *_legacy, read-only, excluded in the export registry "migrated to knowledge_library
-- on <date>"; a later PR drops them after 30 days.
-- Prevented by: scripts/checks/the_knowledge_library_reads_like_the_nine_stores.test.mjs and
--   scripts/sql/one_knowledge_library_is_built_beside_the_nine_stores_and_read_behind_a_flag_probe.sql

create table if not exists public.knowledge_library (
  id               bigint generated always as identity primary key,
  origin_store     text not null,
  origin_id        text not null,
  title            text,
  content          text not null,
  content_md5      text generated always as (md5(content)) stored,
  trade            text,
  tags             text[] not null default '{}',
  seats            text[] not null,
  lang             text not null default 'en',
  source_ref       text,
  source_ids       text[] not null default '{}',
  verified         boolean not null default false,
  runtime_eligible boolean not null default true,
  embedding_gte    vector(384),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint knowledge_library_origin_uq unique (origin_store, origin_id),
  constraint knowledge_library_store_ck check (origin_store in ('kb_chunks', 'ops_knowledge', 'agent_knowledge',
    'sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge', 'ceo_knowledge',
    'support_knowledge')),
  constraint knowledge_library_seats_ck check (cardinality(seats) > 0)
);
create index if not exists knowledge_library_md5_idx on public.knowledge_library (content_md5)
  where origin_store in ('kb_chunks', 'agent_knowledge', 'ops_knowledge');
create index if not exists knowledge_library_store_idx on public.knowledge_library (origin_store);
create index if not exists knowledge_library_seats_idx on public.knowledge_library using gin (seats);
create index if not exists knowledge_library_tags_idx on public.knowledge_library using gin (tags);
-- the three stores that had an HNSW index keep one; the small stores were read exactly and still are
create index if not exists knowledge_library_kb_hnsw on public.knowledge_library using hnsw (embedding_gte vector_cosine_ops)
  where origin_store = 'kb_chunks';
create index if not exists knowledge_library_ops_hnsw on public.knowledge_library using hnsw (embedding_gte vector_cosine_ops)
  where origin_store = 'ops_knowledge';
create index if not exists knowledge_library_sales_hnsw on public.knowledge_library using hnsw (embedding_gte vector_cosine_ops)
  where origin_store = 'sales_knowledge';
-- the library's ml vectors live in knowledge_vector_ml under src 'knowledge_library' (row_id = library id)
alter table public.knowledge_vector_ml drop constraint if exists knowledge_vector_ml_src_check;
alter table public.knowledge_vector_ml add constraint knowledge_vector_ml_src_check check (src = any (array['seat_case_memory',
  'ceo_knowledge', 'support_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge', 'sales_knowledge',
  'company_faq', 'agent_knowledge', 'ops_knowledge', 'reasoning_knowledge_candidate', 'kb_chunks', 'knowledge_library']));
create index if not exists knowledge_vector_ml_library_hnsw on public.knowledge_vector_ml using hnsw (embedding vector_cosine_ops)
  where src = 'knowledge_library';

create table if not exists public.knowledge_library_origin (
  origin_store text not null,
  origin_id    text not null,
  library_id   bigint not null references public.knowledge_library (id) on delete cascade,
  source_ref   text,
  source_ids   text[] not null default '{}',
  primary key (origin_store, origin_id)
);
create index if not exists knowledge_library_origin_lib_idx on public.knowledge_library_origin (library_id);

alter table public.knowledge_library enable row level security;
alter table public.knowledge_library_origin enable row level security;
drop policy if exists knowledge_library_service_role_only on public.knowledge_library;
create policy knowledge_library_service_role_only on public.knowledge_library
  as permissive for all to public using (false) with check (false);
drop policy if exists knowledge_library_origin_service_role_only on public.knowledge_library_origin;
create policy knowledge_library_origin_service_role_only on public.knowledge_library_origin
  as permissive for all to public using (false) with check (false);
revoke all on public.knowledge_library from anon, authenticated;
revoke all on public.knowledge_library_origin from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('knowledge_library', true, 'knowledge', 'the one knowledge library every seat reads (ledger 1085 stage 2): one row per distinct piece of knowledge', 'it_engineer'),
  ('knowledge_library_origin', true, 'knowledge', 'every origin row of the knowledge library with its own citations: the id map from the nine stores (ledger 1085 stage 2)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ---------------------------------------------------------------------------------------------------------------------
-- Each store's rows in the library's shape, as ONE select per store (the single place the mapping lives). The fill and
-- the reconciliation wrap it and read only the columns they need; fn_knowledge_library_source picks one origin through
-- the store's own primary key (the /*KEY*/ marker sits in the store's top-level WHERE).
-- kb_chunks: the rows #1204 keeps - an uncited qd_kb_pack row is not knowledge (ledger 1085 clause 6).
-- lang: the store's language column, else an '@ar' record id, else 'ar' when the first letter is Arabic.
create or replace function public.fn_knowledge_library_source_sql(p_store text, out sel text, out key text)
language plpgsql immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_lang constant text := 'case when %s like ''%%@ar'' or %s ~ ''^[^A-Za-z]*[\u0621-\u064A]'' then ''ar'' else ''en'' end';
begin
  case p_store
  when 'kb_chunks' then
    key := 'c.id = any($1::bigint[])';
    sel := 'select ''kb_chunks''::text, c.id::text, c.title, c.content, c.category_norm, ''{}''::text[], ''{*}''::text[], '
          || format(v_lang, 'c.id::text', 'c.content') || ', c.citation, ''{}''::text[], true, true, c.embedding_gte
               from public.kb_chunks c
              where /*KEY*/ not (c.source_kind is not distinct from ''qd_kb_pack''
                                 and c.id not in (select split_part(x, '':'', 2)::bigint from public.sales_decision_log s, unnest(s.cited) x
                                                   where x ~ ''^kb_chunks:[0-9]+$''))';   -- a hashed subplan, read once
  when 'ops_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''ops_knowledge''::text, c.record_id, c.title, c.content, c.category_key, ''{}''::text[], ''{*}''::text[], '
          || format(v_lang, 'c.record_id', 'c.content') || ', c.source_path, coalesce(c.source_ids, ''{}''), c.validation_status <> ''draft'',
                    coalesce(c.runtime_eligible and c.supersession_state = ''current''
                             and c.scope_type in (''company'', ''external_source'', ''category''), false), c.embedding_gte
               from public.ops_knowledge c where /*KEY*/ true';
  when 'agent_knowledge' then
    key := 'c.id = any($1::bigint[])';
    sel := 'select ''agent_knowledge''::text, c.id::text, c.topic, c.content, null::text, ''{}''::text[],
                    case when c.agent_key = ''_global'' then ''{*}''::text[] else array[c.agent_key] end, '
          || format(v_lang, 'c.id::text', 'c.content') || ', c.source_ref, ''{}''::text[],
                    coalesce(c.validation_status not in (''unsourced'', ''unvalidated'', ''quarantined''), false), true, c.embedding_gte
               from public.agent_knowledge c where /*KEY*/ true';
  when 'sales_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''sales_knowledge''::text, c.record_id, c.title, c.content,
                    (select substr(t, 7) from unnest(c.tags) t where t like ''trade:%%'' limit 1), coalesce(c.tags, ''{}''),
                    case when c.pack_id like ''verified:trade:%%'' or exists (select 1 from unnest(c.tags) t where t like ''trade:%%'')
                         then array[''sales_engineer'', ''customer_support''] else array[''sales_engineer''] end, '
          || format(v_lang, 'c.record_id', 'c.content') || ', c.pack_id, coalesce(c.source_ids, ''{}''),
                    c.epistemic_status = ''verified_pack_sourced'', coalesce(c.runtime_index_eligible, false), c.embedding_gte
               from public.sales_knowledge c where /*KEY*/ true';
  when 'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge' then
    key := 'c.record_id = any($1)';
    sel := format('select %L::text, c.record_id, c.title, c.content, null::text, coalesce(c.tags, ''{}''), array[%L], ',
                    p_store, case p_store when 'accountant_knowledge' then 'accountant' when 'it_engineer_knowledge' then 'it_engineer'
                                          else 'marketing' end)
          || format(v_lang, 'c.record_id', 'c.content') || ', c.pack_id, coalesce(c.source_ids, ''{}''),
                    c.epistemic_status = ''verified_pack_sourced'', coalesce(c.runtime_index_eligible, false), c.embedding_gte
               from public.' || p_store || ' c where /*KEY*/ true';
  when 'ceo_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''ceo_knowledge''::text, c.record_id, c.title, c.body, null::text, coalesce(c.tags, ''{}''), array[''ceo''],
                    coalesce(nullif(c.language, ''''), ' || format(v_lang, 'c.record_id', 'c.body') || '),
                    coalesce(c.source_path, c.pack_fingerprint), coalesce(c.source_ids, ''{}''), c.review_status = ''verified_sourced'',
                    coalesce(c.runtime_index_eligible, false), c.embedding_gte
               from public.ceo_knowledge c where /*KEY*/ true';
  when 'support_knowledge' then
    key := 'c.record_id = any($1)';
    sel := 'select ''support_knowledge''::text, c.record_id, c.title, c.body, null::text, coalesce(c.tags, ''{}''), array[''customer_support''],
                    coalesce(nullif(c.language, ''''), ' || format(v_lang, 'c.record_id', 'c.body') || '),
                    coalesce(c.source_path, c.pack_id), coalesce(c.source_ids, ''{}''), c.review_status = ''verified_sourced'',
                    coalesce(c.runtime_index_eligible, true), c.embedding_gte
               from public.support_knowledge c where /*KEY*/ true';
  else
    raise exception 'fn_knowledge_library_source: % is not one of the nine stores', p_store;
  end case;
  -- columns: origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref, source_ids, verified,
  -- runtime_eligible, embedding_gte. key: the predicate that picks the origins listed in $1 (text[]).
  -- A row with no text yet (a placeholder a loader fills later) is not knowledge: it waits outside the library, so the
  -- mirror trigger can never fail the writer's own insert on the library's NOT NULL.
  sel := 'select * from (' || sel || ') s (origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref, '
      || 'source_ids, verified, runtime_eligible, embedding_gte) where s.content is not null';
end $fn$;
revoke execute on function public.fn_knowledge_library_source_sql(text) from public, anon, authenticated;

create or replace function public.fn_knowledge_library_source(p_store text, p_id text)
returns table (origin_store text, origin_id text, title text, content text, trade text, tags text[], seats text[],
               lang text, source_ref text, source_ids text[], verified boolean, runtime_eligible boolean,
               embedding_gte vector)
language plpgsql stable security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare q record := public.fn_knowledge_library_source_sql(p_store);
begin
  return query execute replace(q.sel, '/*KEY*/', q.key || ' and ') using array[p_id];
end $fn$;
revoke execute on function public.fn_knowledge_library_source(text, text) from public, anon, authenticated;

-- One library row from ALL its origins. THE PRIMARY is the first origin by store priority - kb_chunks, then
-- ops_knowledge, then agent_knowledge, then the store itself (a seat store never merges) - then origin_id, so the
-- outcome is the same whatever order the fill or the writers reach the rows in. The row takes the primary's text,
-- title, tags, citation and BOTH vectors (re-pointed by id; never an alias's: probed 5 Oct 2026, a kb row the ml
-- queue had not reached yet took its agent copy's ml vector and outranked a ceo exam row, ceo/en ml 0.750 -> 0.667 on
-- the sample; the ml queue embeds the kb row itself and the mirror trigger brings that vector here). seats = the union
-- over the origins ('*' absorbs every seat); verified when any origin is. Every origin of a row shares its
-- eligibility (an eligible text never merges with an ineligible copy), so an ineligible row is never served on the
-- strength of an alias. Nothing is written when nothing changed.
create or replace function public.fn_knowledge_library_recompute(p_library_id bigint)
returns void
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  o record; s record; p record; v_have boolean := false;
  v_seats text[] := '{}'; v_elig boolean := false; v_ver boolean := false;
  v_ml vector(384); v_ml_hash text;
begin
  for o in select * from public.knowledge_library_origin where library_id = p_library_id
            order by case origin_store when 'kb_chunks' then 1 when 'ops_knowledge' then 2 when 'agent_knowledge' then 3 else 4 end,
                     origin_id loop
    select * into s from public.fn_knowledge_library_source(o.origin_store, o.origin_id);
    if not found then continue; end if;
    if not v_have then p := s; v_have := true; end if;
    v_seats := v_seats || s.seats;
    v_elig := v_elig or s.runtime_eligible;
    v_ver := v_ver or s.verified;
  end loop;
  if not v_have then return; end if;
  select v.embedding, v.text_hash into v_ml, v_ml_hash from public.knowledge_vector_ml v
   where v.src = p.origin_store and v.row_id = p.origin_id;
  v_seats := case when '*' = any(v_seats) then '{*}'::text[]
                  else array(select distinct x from unnest(v_seats) x order by x) end;
  update public.knowledge_library l
     set origin_store = p.origin_store, origin_id = p.origin_id, title = p.title, content = p.content, trade = p.trade,
         tags = p.tags, lang = p.lang, source_ref = p.source_ref, source_ids = p.source_ids, seats = v_seats,
         runtime_eligible = v_elig, verified = v_ver, embedding_gte = p.embedding_gte, updated_at = now()
   where l.id = p_library_id
     and (l.origin_store, l.origin_id, l.title, l.content, l.trade, l.tags, l.lang, l.source_ref, l.source_ids, l.seats,
          l.runtime_eligible, l.verified, l.embedding_gte)
         is distinct from
         (p.origin_store, p.origin_id, p.title, p.content, p.trade, p.tags, p.lang, p.source_ref, p.source_ids, v_seats,
          v_elig, v_ver, p.embedding_gte);
  if v_ml is null then
    delete from public.knowledge_vector_ml where src = 'knowledge_library' and row_id = p_library_id::text;
  else
    insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding, embedded_at)
    values ('knowledge_library', p_library_id::text, v_ml_hash, v_ml, now())
    on conflict (src, row_id) do update set embedding = excluded.embedding, text_hash = excluded.text_hash,
      embedded_at = excluded.embedded_at
    where knowledge_vector_ml.embedding is distinct from excluded.embedding;
  end if;
end $fn$;
revoke execute on function public.fn_knowledge_library_recompute(bigint) from public, anon, authenticated;

-- Take one origin out of its row. The row stays while another origin holds it (recomputed: it may get a new primary);
-- the last origin out takes the row and its ml vector with it.
create or replace function public.fn_knowledge_library_detach(p_store text, p_id text)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_lib bigint;
begin
  delete from public.knowledge_library_origin where origin_store = p_store and origin_id = p_id returning library_id into v_lib;
  if v_lib is null then return; end if;
  if exists (select 1 from public.knowledge_library_origin where library_id = v_lib) then
    perform public.fn_knowledge_library_recompute(v_lib);
  else
    delete from public.knowledge_vector_ml where src = 'knowledge_library' and row_id = v_lib::text;
    delete from public.knowledge_library where id = v_lib;
  end if;
end $fn$;
revoke execute on function public.fn_knowledge_library_detach(text, text) from public, anon, authenticated;

-- Bring ONE origin into line. It holds the library's advisory lock SHARED (one lock entry per transaction, however many
-- rows a loader writes: a lock per row ran out of shared memory at 5,000, probed 5 Oct 2026), and a backfill page holds
-- it EXCLUSIVE, so a writer's trigger and a page never insert the same origin twice (a unique violation there would
-- fail the WRITER's transaction). Two writers adding the same text at the same instant can still leave two rows;
-- fn_knowledge_library_reconcile counts duplicate_texts so that is seen.
create or replace function public.fn_knowledge_library_sync(p_store text, p_id text)
returns text
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  s record; m record;
  v_dedup constant boolean := p_store in ('kb_chunks', 'agent_knowledge', 'ops_knowledge');
  v_md5 text; v_target bigint; v_alone boolean;
begin
  perform pg_advisory_xact_lock_shared(hashtext('public.knowledge_library'));
  select * into s from public.fn_knowledge_library_source(p_store, p_id);
  select o.library_id, l.content_md5, l.runtime_eligible
    into m from public.knowledge_library_origin o join public.knowledge_library l on l.id = o.library_id
   where o.origin_store = p_store and o.origin_id = p_id;

  if s.origin_id is null then                               -- deleted, empty, or not knowledge (an uncited qd_kb_pack row)
    if m.library_id is null then return 'absent'; end if;
    perform public.fn_knowledge_library_detach(p_store, p_id);
    return 'removed';
  end if;
  v_md5 := md5(s.content);

  if m.library_id is not null then
    select count(*) = 1 into v_alone from public.knowledge_library_origin where library_id = m.library_id;
    -- in place while it still belongs to its group: same text and same eligibility, or a store that never merges
    if (m.content_md5 = v_md5 and m.runtime_eligible = s.runtime_eligible) or (v_alone and not v_dedup) then
      update public.knowledge_library_origin set source_ref = s.source_ref, source_ids = s.source_ids
       where origin_store = p_store and origin_id = p_id
         and (source_ref, source_ids) is distinct from (s.source_ref, s.source_ids);
      perform public.fn_knowledge_library_recompute(m.library_id);
      return 'updated';
    end if;
    perform public.fn_knowledge_library_detach(p_store, p_id); -- its text or eligibility changed: it finds its group again
  end if;

  if v_dedup then
    select l.id into v_target from public.knowledge_library l
     where l.content_md5 = v_md5 and l.runtime_eligible = s.runtime_eligible
       and l.origin_store in ('kb_chunks', 'agent_knowledge', 'ops_knowledge')
     order by l.id limit 1;
  end if;
  if v_target is null then
    insert into public.knowledge_library (origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref,
                                          source_ids, verified, runtime_eligible, embedding_gte)
    values (p_store, p_id, s.title, s.content, s.trade, s.tags, s.seats, s.lang, s.source_ref, s.source_ids, s.verified,
            s.runtime_eligible, s.embedding_gte)
    returning id into v_target;
  end if;
  insert into public.knowledge_library_origin values (p_store, p_id, v_target, s.source_ref, s.source_ids);
  perform public.fn_knowledge_library_recompute(v_target);
  return case when (select count(*) from public.knowledge_library_origin where library_id = v_target) = 1 then 'inserted' else 'merged' end;
end $fn$;
revoke execute on function public.fn_knowledge_library_sync(text, text) from public, anon, authenticated;

-- Every writer of the nine stores lands in the library (phase 1 keeps the writers as they are).
create or replace function public.fn_knowledge_library_mirror()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_col constant text := case when tg_table_name in ('kb_chunks', 'agent_knowledge') then 'id' else 'record_id' end;
  v_new text; v_old text;
begin
  if tg_op <> 'INSERT' then v_old := to_jsonb(old) ->> v_col; end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new) ->> v_col; end if;
  if v_old is not null and v_old is distinct from v_new then
    perform public.fn_knowledge_library_sync(tg_table_name, v_old);
  end if;
  if v_new is not null then
    perform public.fn_knowledge_library_sync(tg_table_name, v_new);
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_knowledge_library_mirror() from public, anon, authenticated;

-- UPDATE fires only on the columns the library maps (23 routines touch agent_knowledge.updated_at alone; the embed
-- queue claims kb_chunks rows by embed_claimed_at): a write the library cannot see costs nothing.
drop trigger if exists zz_knowledge_library_mirror on public.kb_chunks;
create trigger zz_knowledge_library_mirror after insert or delete or update of id, title, content, citation, category_norm,
  source_kind, embedding_gte on public.kb_chunks for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.ops_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, content, category_key,
  source_path, source_ids, validation_status, runtime_eligible, supersession_state, scope_type, embedding_gte
  on public.ops_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.agent_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of id, topic, content, agent_key, source_ref,
  validation_status, embedding_gte on public.agent_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.sales_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, content, tags, pack_id,
  source_ids, epistemic_status, runtime_index_eligible, embedding_gte
  on public.sales_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.accountant_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, content, tags, pack_id,
  source_ids, epistemic_status, runtime_index_eligible, embedding_gte
  on public.accountant_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.it_engineer_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, content, tags, pack_id,
  source_ids, epistemic_status, runtime_index_eligible, embedding_gte
  on public.it_engineer_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.marketing_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, content, tags, pack_id,
  source_ids, epistemic_status, runtime_index_eligible, embedding_gte
  on public.marketing_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.ceo_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, body, tags, language,
  source_path, pack_fingerprint, source_ids, review_status, runtime_index_eligible, embedding_gte
  on public.ceo_knowledge for each row execute function public.fn_knowledge_library_mirror();
drop trigger if exists zz_knowledge_library_mirror on public.support_knowledge;
create trigger zz_knowledge_library_mirror after insert or delete or update of record_id, title, body, tags, language,
  source_path, pack_id, source_ids, review_status, runtime_index_eligible, embedding_gte
  on public.support_knowledge for each row execute function public.fn_knowledge_library_mirror();

-- A qd_kb_pack row belongs to the library exactly while sales_decision_log cites it (#1204 clause 6), so a citation
-- written or removed re-syncs the kb rows it names.
create or replace function public.fn_knowledge_library_mirror_citation()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  x text; v text[] := '{}';
begin
  if tg_op <> 'DELETE' then v := v || coalesce(new.cited, '{}'); end if;
  if tg_op <> 'INSERT' then v := v || coalesce(old.cited, '{}'); end if;
  for x in select distinct split_part(c, ':', 2) from unnest(v) c where c ~ '^kb_chunks:[0-9]+$' loop
    perform public.fn_knowledge_library_sync('kb_chunks', x);
  end loop;
  return null;
end $fn$;
revoke execute on function public.fn_knowledge_library_mirror_citation() from public, anon, authenticated;
drop trigger if exists zz_knowledge_library_mirror_citation on public.sales_decision_log;
create trigger zz_knowledge_library_mirror_citation after insert or delete or update of cited on public.sales_decision_log
  for each row execute function public.fn_knowledge_library_mirror_citation();

-- An ml vector written for an origin reaches its library row by id mapping (never re-embedded). Two triggers, because
-- an INSERT trigger's WHEN cannot name OLD and a DELETE trigger's cannot name NEW.
create or replace function public.fn_knowledge_library_mirror_ml()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_src text; v_row text; v_lib bigint;
begin
  if tg_op = 'DELETE' then v_src := old.src; v_row := old.row_id; else v_src := new.src; v_row := new.row_id; end if;
  select library_id into v_lib from public.knowledge_library_origin where origin_store = v_src and origin_id = v_row;
  if v_lib is not null then perform public.fn_knowledge_library_recompute(v_lib); end if;
  return null;
end $fn$;
revoke execute on function public.fn_knowledge_library_mirror_ml() from public, anon, authenticated;
drop trigger if exists zz_knowledge_library_mirror_ml on public.knowledge_vector_ml;
create trigger zz_knowledge_library_mirror_ml after insert or update of src, row_id, embedding on public.knowledge_vector_ml
  for each row when (new.src in ('kb_chunks', 'ops_knowledge', 'agent_knowledge', 'sales_knowledge',
    'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge', 'ceo_knowledge', 'support_knowledge'))
  execute function public.fn_knowledge_library_mirror_ml();
drop trigger if exists zz_knowledge_library_mirror_ml_delete on public.knowledge_vector_ml;
create trigger zz_knowledge_library_mirror_ml_delete after delete on public.knowledge_vector_ml
  for each row when (old.src in ('kb_chunks', 'ops_knowledge', 'agent_knowledge', 'sales_knowledge',
    'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge', 'ceo_knowledge', 'support_knowledge'))
  execute function public.fn_knowledge_library_mirror_ml();

-- THE BACKFILL: the next p_n origins of one store not yet in the library, at most 5,000 a call, set-based (the same
-- outcome fn_knowledge_library_sync gives one row at a time): a new text becomes a library row; a kb_chunks /
-- agent_knowledge / ops_knowledge text already in the library (or earlier in the page) joins that row as a merged
-- origin, and the row is recomputed (seat union, eligibility, vectors). The page is chosen by key alone, so no content
-- or vector is detoasted to choose it. ML vectors are copied by id mapping.
create or replace function public.fn_knowledge_library_fill_page(p_store text, p_n integer default 2000)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'extensions', 'pg_temp'
set lock_timeout to '2s'
as $fn$
declare
  q constant record := public.fn_knowledge_library_source_sql(p_store);
  v_n constant integer := greatest(1, least(coalesce(p_n, 2000), 5000));
  v_dedup constant boolean := p_store in ('kb_chunks', 'agent_knowledge', 'ops_knowledge');
  v_unmapped text;
  v_keys text[]; v_ins integer := 0; v_mrg integer := 0; v_left bigint; v_lib bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then   -- never beside a purge or trim batch
    raise exception 'fn_knowledge_library_fill_page: a kb purge or trim batch is running';
  end if;
  v_unmapped := format('select s.origin_id from (%s) s where not exists (select 1 from public.knowledge_library_origin o
                          where o.origin_store = %L and o.origin_id = s.origin_id)', replace(q.sel, '/*KEY*/', ''), p_store);
  execute 'select array_agg(origin_id) from (' || v_unmapped || ' order by s.origin_id limit ' || v_n || ') k' into v_keys;
  if v_keys is not null then
    drop table if exists qd_kl_page;
    execute 'create temp table qd_kl_page on commit drop as select s.*, md5(s.content) md5, null::bigint lib_id from ('
         || replace(q.sel, '/*KEY*/', q.key || ' and ') || ') s' using v_keys;
    -- the library's lock EXCLUSIVE (writers' triggers hold it shared), then drop what a trigger mapped meanwhile
    perform pg_advisory_xact_lock(hashtext('public.knowledge_library'));
    delete from qd_kl_page p using public.knowledge_library_origin o where o.origin_store = p_store and o.origin_id = p.origin_id;
    if v_dedup then   -- a text already in the library with the same eligibility: merge into its row
      update qd_kl_page p set lib_id = (select l.id from public.knowledge_library l where l.content_md5 = p.md5
                                         and l.runtime_eligible = p.runtime_eligible
                                         and l.origin_store in ('kb_chunks', 'agent_knowledge', 'ops_knowledge') order by l.id limit 1);
    end if;
    -- new texts: one library row per text (per origin when the store does not merge), the first origin its primary
    with firsts as (
      select distinct on (case when v_dedup then p.md5 || ':' || p.runtime_eligible else p.origin_id end) p.*
        from qd_kl_page p where p.lib_id is null
       order by case when v_dedup then p.md5 || ':' || p.runtime_eligible else p.origin_id end, p.origin_id),
    ins as (
      insert into public.knowledge_library (origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref,
                                            source_ids, verified, runtime_eligible, embedding_gte)
      select origin_store, origin_id, title, content, trade, tags, seats, lang, source_ref, source_ids, verified,
             runtime_eligible, embedding_gte from firsts
      returning id, origin_id, content_md5, runtime_eligible)
    update qd_kl_page p set lib_id = i.id from ins i
     where p.lib_id is null
       and (p.origin_id = i.origin_id or (v_dedup and p.md5 = i.content_md5 and p.runtime_eligible = i.runtime_eligible));
    get diagnostics v_ins = row_count;
    insert into public.knowledge_library_origin (origin_store, origin_id, library_id, source_ref, source_ids)
    select p.origin_store, p.origin_id, p.lib_id, p.source_ref, p.source_ids from qd_kl_page p;
    -- ml vectors of the new primaries, by id mapping
    insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding, embedded_at)
    select 'knowledge_library', l.id::text, v.text_hash, v.embedding, now()
      from public.knowledge_library l join public.knowledge_vector_ml v on v.src = l.origin_store and v.row_id = l.origin_id
     where l.id in (select lib_id from qd_kl_page) and l.origin_store = p_store
    on conflict (src, row_id) do nothing;
    -- rows that gained a merged origin: primary by store priority, seat union, vectors
    for v_lib in select p.lib_id from qd_kl_page p join public.knowledge_library_origin o on o.library_id = p.lib_id
                  group by p.lib_id having count(distinct (o.origin_store, o.origin_id)) > 1 loop
      perform public.fn_knowledge_library_recompute(v_lib);
      v_mrg := v_mrg + 1;
    end loop;
    v_ins := (select count(*) from qd_kl_page p join public.knowledge_library l on l.id = p.lib_id
               where l.origin_store = p.origin_store and l.origin_id = p.origin_id);
    drop table qd_kl_page;
  end if;
  execute 'select count(*) from (' || v_unmapped || ') k' into v_left;
  return jsonb_build_object('store', p_store, 'page', coalesce(cardinality(v_keys), 0), 'inserted', v_ins,
                            'rows_merged_into', v_mrg, 'left', v_left);
end $fn$;
revoke execute on function public.fn_knowledge_library_fill_page(text, integer) from public, anon, authenticated;

-- Rows and citations, store by store: what the store holds vs what the library maps. A citation is the row's
-- source_ref plus every entry of its source_ids; a merged origin keeps its own in knowledge_library_origin.
create or replace function public.fn_knowledge_library_reconcile()
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_store text; v_out jsonb := '{}'; v_ok boolean := true; n bigint; refs bigint; ids bigint; ln bigint; lrefs bigint; lids bigint; lprim bigint;
begin
  foreach v_store in array array['kb_chunks', 'ops_knowledge', 'agent_knowledge', 'sales_knowledge', 'accountant_knowledge',
                                 'it_engineer_knowledge', 'marketing_knowledge', 'ceo_knowledge', 'support_knowledge'] loop
    execute 'select count(*), count(s.source_ref), coalesce(sum(cardinality(s.source_ids)), 0) from ('
         || replace((public.fn_knowledge_library_source_sql(v_store)).sel, '/*KEY*/', '') || ') s' into n, refs, ids;
    select count(*), count(o.source_ref), coalesce(sum(cardinality(o.source_ids)), 0),
           count(*) filter (where l.origin_store = o.origin_store and l.origin_id = o.origin_id)
      into ln, lrefs, lids, lprim
      from public.knowledge_library_origin o join public.knowledge_library l on l.id = o.library_id where o.origin_store = v_store;
    v_ok := v_ok and n = ln and refs = lrefs and ids = lids;
    v_out := v_out || jsonb_build_object(v_store, jsonb_build_object('source_rows', n, 'mapped', ln, 'primaries', lprim,
               'source_refs', refs, 'mapped_refs', lrefs, 'source_ids', ids, 'mapped_ids', lids));
  end loop;
  return jsonb_build_object('stores', v_out, 'reconciled', v_ok,
    'library_rows', (select count(*) from public.knowledge_library),
    'merged_origins', (select count(*) from public.knowledge_library_origin o join public.knowledge_library l on l.id = o.library_id
                        where (l.origin_store, l.origin_id) is distinct from (o.origin_store, o.origin_id)),
    'ml_vectors', (select count(*) from public.knowledge_vector_ml where src = 'knowledge_library'),
    'gte_vectors', (select count(*) from public.knowledge_library where embedding_gte is not null),
    'duplicate_texts', (select count(*) - count(distinct (content_md5, runtime_eligible)) from public.knowledge_library
                         where origin_store in ('kb_chunks', 'agent_knowledge', 'ops_knowledge')));
end $fn$;
revoke execute on function public.fn_knowledge_library_reconcile() from public, anon, authenticated;

create or replace function public.fn_knowledge_library_read()
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case when (select value from public.app_secrets where key = 'knowledge_library_read') = 'library'
              then 'library' else 'legacy' end;
$fn$;
revoke execute on function public.fn_knowledge_library_read() from public, anon, authenticated;

-- seat -> the store whose area tags resolve its p_area (as the legacy readers did)
create or replace function public.fn_knowledge_library_seat_store(p_seat text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case p_seat when 'sales_engineer' then 'sales_knowledge' when 'accountant' then 'accountant_knowledge'
                     when 'it_engineer' then 'it_engineer_knowledge' when 'customer_support' then 'support_knowledge'
                     when 'ceo' then 'ceo_knowledge' when 'marketing' then 'marketing_knowledge' end;
$fn$;
revoke execute on function public.fn_knowledge_library_seat_store(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- THE GTE READER OVER THE LIBRARY. Line for line fn_reason_retrieve: per store k nearest, then the best 2k.
create or replace function public.fn_reason_retrieve_library(p_seat text, p_embedding vector, p_k integer default 6,
  p_trade text default null, p_kind text default null, p_area text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
  v_seats constant text[] := array[p_seat, '*'];
  v_trade text[];
  v_kind  text;
  v_area  text;
begin
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = 'sales_knowledge' and x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = public.fn_knowledge_library_seat_store(p_seat) and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  if p_embedding is null then return out; end if;

  with lib as (
    select l.*, 1 - (l.embedding_gte <=> p_embedding) sim from public.knowledge_library l
     where false
  ), hits as (
    (select 'kb_chunks' src, l.origin_id id, l.title, left(l.content, 1200) excerpt, l.source_ref citation,
            1 - (l.embedding_gte <=> p_embedding) sim, 'reviewed' trust
       from public.knowledge_library l
      where l.origin_store = 'kb_chunks' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = 'ops_knowledge' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = 'agent_knowledge' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed'
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = 'sales_knowledge' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_trade is null or not exists (select 1 from unnest(l.tags) t where t like 'trade:%')
             or (l.tags && v_trade and (v_kind is null or l.tags @> array['kind:' || v_kind])))
        and (v_area is null or l.tags @> array['area:' || v_area] or not exists (select 1 from unnest(l.tags) t where t like 'area:%'))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select l.origin_store, l.origin_id, l.title, left(l.content, 1200), l.source_ref, 1 - (l.embedding_gte <=> p_embedding), 'reviewed'
       from public.knowledge_library l
      where l.origin_store = public.fn_knowledge_library_seat_store(p_seat) and l.origin_store <> 'sales_knowledge'
        and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
        and (v_area is null or l.tags @> array['area:' || v_area] or not exists (select 1 from unnest(l.tags) t where t like 'area:%'))
      order by l.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected'
      order by r.embedding_gte <=> p_embedding limit k)
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust) order by sim desc), '[]'::jsonb)
    into out
    from (select * from hits order by sim desc limit k * 2) t;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve_library(text, vector, integer, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_library(text, vector, integer, text, text, text) to service_role;

-- THE FUSED READER OVER THE LIBRARY. Line for line fn_reason_retrieve_ml: per store n candidates in each space, both
-- similarities, reciprocal-rank fusion weighted by decisiveness, per store k, the seat's own rows reserved, then 2k.
-- A store's ml vector is the library row's (src 'knowledge_library'). The kb_chunks ml branch walks the HNSW index as
-- before; the other stores were read exactly before (no index on their src) and still are ('+ 0' keeps the index off).
create or replace function public.fn_reason_retrieve_ml_library(p_seat text, p_embedding vector, p_embedding_gte vector default null,
  p_k integer default 6, p_own integer default 3, p_trade text default null, p_kind text default null, p_area text default null)
returns jsonb
language plpgsql stable security definer
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
  v_seats constant text[] := array[p_seat, '*'];
  v_own_store constant text := public.fn_knowledge_library_seat_store(p_seat);
  v_trade text[];
  v_kind  text;
  v_area  text;
begin
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = 'sales_knowledge' and x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (select 1 from public.knowledge_library x
       where x.origin_store = v_own_store and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  if m is null then return out; end if;
  with elig as materialized (
    -- every non-kb library row this seat may read, with the legacy reader's store predicates: the trade only on
    -- sales_knowledge, the area only on the seat stores (sales_knowledge and the seat's own)
    select l.id, l.origin_store, l.origin_id from public.knowledge_library l
     where l.origin_store in ('ops_knowledge', 'agent_knowledge', 'sales_knowledge', v_own_store)
       and l.runtime_eligible and l.seats && v_seats
       and (l.origin_store <> 'sales_knowledge' or v_trade is null or not exists (select 1 from unnest(l.tags) t where t like 'trade:%')
            or (l.tags && v_trade and (v_kind is null or l.tags @> array['kind:' || v_kind])))
       and (l.origin_store in ('ops_knowledge', 'agent_knowledge') or v_area is null
            or l.tags @> array['area:' || v_area] or not exists (select 1 from unnest(l.tags) t where t like 'area:%'))
  ), cand as (
    (select 'kb_chunks' src, l.origin_id row_id, l.id lib_id from public.knowledge_vector_ml v
       join public.knowledge_library l on v.src = 'knowledge_library' and l.id = v.row_id::bigint
      where l.origin_store = 'kb_chunks' and l.runtime_eligible and l.seats && v_seats
      order by v.embedding <=> m limit n)
    union (select 'kb_chunks', l.origin_id, l.id from public.knowledge_library l
            where g is not null and l.origin_store = 'kb_chunks' and l.embedding_gte is not null and l.runtime_eligible and l.seats && v_seats
            order by l.embedding_gte <=> g limit n)
    union (select x.src, x.row_id, x.lib_id from (
             select e.origin_store src, e.origin_id row_id, e.id lib_id, row_number() over (partition by e.origin_store order by e.d) rn
               from (select e.*, (select v.embedding <=> m from public.knowledge_vector_ml v      -- one pkey probe a row: a join
                                   where v.src = 'knowledge_library' and v.row_id = e.id::text) d -- here was planned as 2,303
                       from elig e) e                                                             -- seq scans (4.5 s)
              where e.d is not null) x
            where x.rn <= n)
    union (select x.src, x.row_id, x.lib_id from (
             select e.origin_store src, e.origin_id row_id, e.id lib_id,
                    row_number() over (partition by e.origin_store order by l.embedding_gte <=> g) rn
               from elig e join public.knowledge_library l on l.id = e.id
              where g is not null and l.embedding_gte is not null) x
            where x.rn <= n)
    union (select 'company_faq', f.id::text, null::bigint from public.knowledge_vector_ml v join public.company_faq f on v.src = 'company_faq' and f.id::text = v.row_id
            where f.status = 'approved' order by v.embedding <=> m limit n)
    union (select 'company_faq', f.id::text, null::bigint from public.company_faq f
            where g is not null and f.embedding_gte is not null and f.status = 'approved' order by f.embedding_gte <=> g limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text, null::bigint from public.knowledge_vector_ml v
             join public.reasoning_knowledge_candidate r on v.src = 'reasoning_knowledge_candidate' and r.id::text = v.row_id
            where r.status <> 'rejected' order by v.embedding <=> m limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text, null::bigint from public.reasoning_knowledge_candidate r
            where g is not null and r.embedding_gte is not null and r.status <> 'rejected' order by r.embedding_gte <=> g limit n)
  ), sims as (
    select c.src, c.row_id, c.lib_id,
           case when c.lib_id is not null
                then (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = 'knowledge_library' and v.row_id = c.lib_id::text)
                else (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = c.src and v.row_id = c.row_id) end s_ml,
           case when g is null then null
                when c.lib_id is not null then (select 1 - (x.embedding_gte <=> g) from public.knowledge_library x where x.id = c.lib_id)
                when c.src = 'company_faq' then (select 1 - (x.embedding_gte <=> g) from public.company_faq x where x.id = c.row_id::bigint)
                else (select 1 - (x.embedding_gte <=> g) from public.reasoning_knowledge_candidate x where x.id = c.row_id::bigint)
           end s_gte
      from cand c
  ), ranked as (
    select s.*,
           case when s_ml is not null then row_number() over (order by s_ml desc nulls last) end r_ml,
           case when s_gte is not null then row_number() over (order by s_gte desc nulls last) end r_gte
      from sims s
  ), gaps as (
    select coalesce(max(s_ml) - coalesce(max(s_ml) filter (where r_ml = n + 1), min(s_ml)), 0) d_ml,
           coalesce(max(s_gte) - coalesce(max(s_gte) filter (where r_gte = n + 1), min(s_gte)), 0) d_gte
      from ranked
  ), scored as materialized (
    select r.*,
           coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_ml / (gp.d_ml + gp.d_gte) else 1 end / (60 + r.r_ml), 0)
         + coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_gte / (gp.d_ml + gp.d_gte) else 0 end / (60 + r.r_gte), 0) score
      from ranked r cross join gaps gp
  ), lib_hits as (
    select l.origin_store src, l.origin_id id, l.title, left(l.content, 1200) excerpt, l.source_ref citation, sc.s_ml, sc.score,
           'reviewed' trust, not ('*' = any(l.seats)) mine,
           row_number() over (partition by l.origin_store order by sc.score desc) rn
      from scored sc join public.knowledge_library l on l.id = sc.lib_id
  ), hits as (
    select src, id, title, excerpt, citation, s_ml, score, trust, mine from lib_hits where rn <= k
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id, sc.s_ml, sc.score, 'reviewed', false
       from (select *, row_id::bigint key from scored where src = 'company_faq') sc join public.company_faq f on f.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url', sc.s_ml, sc.score,
            case when r.status = 'approved' then 'reviewed' else 'pending_review' end, false
       from (select *, row_id::bigint key from scored where src = 'reasoning_knowledge_candidate') sc join public.reasoning_knowledge_candidate r on r.id = sc.key
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
revoke execute on function public.fn_reason_retrieve_ml_library(text, vector, vector, integer, integer, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve_ml_library(text, vector, vector, integer, integer, text, text, text) to service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- THE TWO READERS ARE NOT TOUCHED HERE (release operator, 19 Oct 2026). This file was written on 5 Oct against the
-- six/eight-argument readers; #1567 replaced those with the audience-guarded seven/nine-argument versions and dropped
-- the old ones, because the old ones let a customer-facing call read internal rows. Applying the old bodies recreated
-- the unguarded overloads beside the guarded ones; they were dropped again within minutes, and the dispatch lines are
-- removed from this file. The library is read by nothing until its flag is set, so phase 2 must add the dispatch to
-- the guarded readers (a_seats_own_entry_reaches_the_answer_whole.sql) and give the library readers the same
-- audience guard first.
DROP FUNCTION IF EXISTS public.fn_reason_retrieve(text, vector, integer, text, text, text);
DROP FUNCTION IF EXISTS public.fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text);
