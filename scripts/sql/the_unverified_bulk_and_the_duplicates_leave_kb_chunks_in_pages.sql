-- THE UNVERIFIED BULK AND THE DUPLICATES LEAVE kb_chunks, IN PAGES, AT NIGHT (5 Oct 2026, it_engineer; ledger 1085 stage 4).
--
-- Founder ruling, ledger 1085 (5 Oct 2026): one knowledge library, Arabic-capable search, bulk trimmed. The brief names
-- what goes: the unverified qd_kb_pack rows and the exact duplicates. This supersedes, for qd_kb_pack only,
-- docs/KNOWLEDGE_DOCTRINE.md §6 clause 1, which kept every qd_kb_pack row as QuotesDone-authored (18-21 Sep).
--
-- MEASURED (production, read-only, 5 Oct 2026):
--   kb_chunks 148,326 live rows; 8,089 MB total, 4,124 MB heap, 26,756 dead tuples, last autovacuum 22 Sep.
--   qd_kb_pack 90,488 rows, all created 10 Aug 2026, none in any verified pack (knowledge/packs holds no QD-KB entry).
--   Identical content (md5 of content): 12,272 rows beyond the first of their group (standard, cert, trade). With the
--   title in the key only 5,078, so the brief's "exact duplicates" is the content, which is what this file uses.
--   Hashing the whole table: 36.6 s, so it runs ONCE, at census, into kb_trim_plan, never per batch.
--
-- WHAT GOES (clause numbers continue the purge ledger's 1..5):
--   6  a qd_kb_pack row (unverified: no verified pack carries it).
--   7  a row whose content is identical to a lower-id row that stays. The keeper of a group is its lowest id that is
--      not itself going under clause 6, so trimming qd_kb_pack never removes the last copy of a text.
--   Never: an id cited in sales_decision_log.cited (clause 2 of §6), which is skipped by both clauses.
--
-- HOW (the same guards as the 21 Sep purge, scripts/sql/the_purge_cannot_take_the_database_down.sql):
--   fn_kb_trim_census()   fills kb_trim_plan and writes the census rows to kb_purge_ledger (verdict TRIM, batch_no
--                         NULL) BEFORE any delete. Refuses if a census exists with rows left to delete.
--   fn_kb_trim_batch(n)   deletes at most n (1..5000, default 2000) planned ids in id order: a pkey walk, never
--                         overlapping a purge or another trim (the purge's advisory lock), lock_timeout 2 s, deletes
--                         recorded by range for the export. Driven by scripts/kb/trim_kb_chunks.mjs, which reads the
--                         load guard (fn_kb_purge_load) before every batch and runs only 23:00-06:00 Dubai.
--   No VACUUM FULL, no pg_repack: that rewrite is docs/runbooks/kb_chunks_rewrite.md, and needs the founder's go.
--   The deleted rows remain in the daily export (table_export_change records every delete range).
--
-- Prevented by: scripts/checks/the_kb_trim_keeps_one_copy_and_never_a_cited_row.test.mjs.

alter table public.kb_purge_ledger drop constraint if exists kb_purge_ledger_verdict_check;
alter table public.kb_purge_ledger add constraint kb_purge_ledger_verdict_check
  check (verdict in ('KEEP', 'UNSURE', 'DELETE', 'SIZE', 'TRIM'));
alter table public.kb_purge_ledger drop constraint if exists kb_purge_ledger_clause_check;
alter table public.kb_purge_ledger add constraint kb_purge_ledger_clause_check check (clause between 0 and 7);

create table if not exists public.kb_trim_plan (
  id bigint primary key,
  clause smallint not null check (clause in (6, 7)),
  content_md5 text,                 -- clause 7: the text whose surviving copy the read-back proves
  planned_at timestamptz not null default now()
);
alter table public.kb_trim_plan enable row level security;
drop policy if exists kb_trim_plan_service_role_only on public.kb_trim_plan;
create policy kb_trim_plan_service_role_only on public.kb_trim_plan as permissive for all to public using (false) with check (false);
revoke all on public.kb_trim_plan from anon, authenticated;

create or replace function public.fn_kb_trim_census()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '110s'
as $fn$
declare v6 bigint; v7 bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then
    raise exception 'fn_kb_trim_census: a purge or trim batch is running';
  end if;
  if exists (select 1 from public.kb_trim_plan p join public.kb_chunks k on k.id = p.id) then
    raise exception 'fn_kb_trim_census: a plan with rows still to delete exists; finish it with scripts/kb/trim_kb_chunks.mjs --run';
  end if;
  delete from public.kb_trim_plan;
  delete from public.kb_purge_ledger where verdict = 'TRIM' and batch_no is null;

  with cited as (select split_part(x, ':', 2)::bigint id from public.sales_decision_log s, unnest(s.cited) x
                  where x ~ '^kb_chunks:[0-9]+$'),
  h as (select k.id, k.source_kind, md5(k.content) c,
               (k.source_kind = 'qd_kb_pack' and k.id not in (select id from cited)) goes6
          from public.kb_chunks k),
  keep as (select c, min(id) id from h where not goes6 group by c),
  plan as (
    select id, 6::smallint clause, null::text c from h where goes6
    union all
    select h.id, 7, h.c from h join keep on keep.c = h.c
     where not h.goes6 and h.id <> keep.id and h.id not in (select id from cited))
  insert into public.kb_trim_plan (id, clause, content_md5) select id, clause, c from plan;

  insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, note)
  select 'TRIM', p.clause, k.source_kind, null, count(*), 'census before the first trim batch (ledger 1085)'
    from public.kb_trim_plan p join public.kb_chunks k on k.id = p.id group by p.clause, k.source_kind;
  select count(*) filter (where clause = 6), count(*) filter (where clause = 7) into v6, v7 from public.kb_trim_plan;
  return jsonb_build_object('clause6_qd_kb_pack', v6, 'clause7_duplicate', v7);
end $fn$;
revoke execute on function public.fn_kb_trim_census() from public, anon, authenticated;

create or replace function public.fn_kb_trim_batch(p_limit integer default 2000)
returns table (batch_no integer, deleted_count bigint, deleted_bytes bigint, cursor_from bigint, cursor_to bigint, remaining_count bigint)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set enable_seqscan to 'off'
set max_parallel_workers_per_gather to '0'
set lock_timeout to '2s'
as $fn$
declare v_from bigint; v_to bigint; v_batch integer; v_deleted bigint; v_bytes bigint; v_left bigint;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_kb_trim_batch: p_limit must be 1..5000 (got %)', p_limit;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then
    raise exception 'fn_kb_trim_batch: a purge or trim batch is running - refusing to overlap it';
  end if;
  if not exists (select 1 from public.kb_purge_ledger l where l.verdict = 'TRIM' and l.batch_no is null) then
    raise exception 'fn_kb_trim_batch: no census in kb_purge_ledger - run select public.fn_kb_trim_census() first';
  end if;
  select coalesce(max(l.batch_no), 0) + 1 into v_batch
    from public.kb_purge_ledger l where l.verdict = 'TRIM' and l.batch_no is not null;
  perform set_config('qd.export_change_bulk', 'kb_chunks', true);

  with pick as (
    select p.id, p.clause from public.kb_trim_plan p
     where exists (select 1 from public.kb_chunks k where k.id = p.id)
     order by p.id limit p_limit
  ), del as (
    delete from public.kb_chunks k using pick p where k.id = p.id
    returning k.id, p.clause, k.source_kind, octet_length(k.content) b
  ), rec as (
    insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, bytes, batch_no, id_from, id_to)
    select 'TRIM', d.clause, d.source_kind, null, count(*), sum(d.b), v_batch, (select min(id) from del), (select max(id) from del)
      from del d group by d.clause, d.source_kind
    returning rows, bytes, id_from, id_to
  )
  select coalesce(sum(r.rows), 0), coalesce(sum(r.bytes), 0), min(r.id_from), max(r.id_to)
    into v_deleted, v_bytes, v_from, v_to from rec r;
  select count(*) into v_left from public.kb_trim_plan p where exists (select 1 from public.kb_chunks k where k.id = p.id);
  return query select v_batch, v_deleted, v_bytes, v_from, v_to, v_left;
end $fn$;
revoke execute on function public.fn_kb_trim_batch(integer) from public, anon, authenticated;

-- Probe (nothing kept): a census and one 50-row batch inside a rolled-back block. The batch deletes exactly what it
-- reports, every deleted id was planned, and no cited id is planned. (That every clause-7 row keeps a surviving copy
-- is asserted by the driver's read-back after the last batch: hashing the table twice does not fit an apply.)
create temporary table if not exists qd_probe_trim (planned6 bigint, planned7 bigint, deleted bigint, live_drop bigint, cited bigint) on commit drop;
do $$ declare c jsonb; b record; v_live bigint := (select count(*) from public.kb_chunks); v_drop bigint; v_cited bigint; begin
  begin
    c := public.fn_kb_trim_census();
    select * into b from public.fn_kb_trim_batch(50);
    v_drop := v_live - (select count(*) from public.kb_chunks);
    select count(*) into v_cited from public.kb_trim_plan p where p.id in (select split_part(x, ':', 2)::bigint
             from public.sales_decision_log s, unnest(s.cited) x where x ~ '^kb_chunks:[0-9]+$');
    raise exception 'qd_probe_rollback';
  exception when others then
    if sqlerrm <> 'qd_probe_rollback' then raise; end if;
  end;
  insert into qd_probe_trim values ((c->>'clause6_qd_kb_pack')::bigint, (c->>'clause7_duplicate')::bigint, b.deleted_count, v_drop, v_cited);
end $$;
select case when t.planned6 > 0 and t.planned7 > 0 and t.deleted = 50 and t.live_drop = 50 and t.cited = 0
             and (select count(*) from public.kb_trim_plan) = 0
             and (select count(*) from public.kb_purge_ledger where verdict = 'TRIM') = 0
            then 'PROBE OK (planned qd_kb_pack ' || t.planned6 || ', duplicates ' || t.planned7 || ')'
            else 'PROBE FAILED: ' || row_to_json(t)::text end as verdict
  from qd_probe_trim t;
