-- THE UNVERIFIED BULK AND THE DUPLICATES LEAVE kb_chunks, IN PAGES, AT NIGHT (5 Oct 2026, it_engineer; ledger 1085 stage 4).
--
-- Founder ruling, ledger 1085 (5 Oct 2026): one knowledge library, Arabic-capable search, bulk trimmed. The brief names
-- what goes: the unverified qd_kb_pack rows and the exact duplicates. This supersedes, for qd_kb_pack only,
-- docs/KNOWLEDGE_DOCTRINE.md §6 clause 1, which kept every qd_kb_pack row as QuotesDone-authored (18-21 Sep).
--
-- MEASURED (production, read-only, 5 Oct 2026):
--   kb_chunks 148,326 live rows; heap 4,324 MB, total 8,482 MB (TOAST ~3.3 GB, indexes 821 MB); newest row 31 Aug.
--   qd_kb_pack 90,488 rows, all created 10 Aug 2026, none in any verified pack (knowledge/packs holds no QD-KB entry).
--   EXACT duplicates, keyed on content AND title AND category (a copy that would lose its title, trade or category is
--   not a duplicate): 3,478 rows beyond the keeper of their group, none qd_kb_pack, none cited. Keyed on content
--   alone it was 8,465; the other 4,987 differ in title or category and now stay. (One read-only pass, 29 s.)
--
-- WHAT GOES (clause numbers continue the purge ledger's 1..5):
--   6  a qd_kb_pack row (unverified: no verified pack carries it).
--   7  an exact duplicate of its group's keeper. The keeper is chosen in order: not qd_kb_pack, then has a citation
--      (the verified copy), then the lowest id. A verified copy is never dropped in favour of an unverified one, and
--      a group whose keeper is qd_kb_pack plans nothing under clause 7.
--   Never: an id cited in sales_decision_log.cited (clause 2 of §6), skipped by both clauses; never a keeper.
--
-- THE APPLY IS LIGHT: two tables, three routines, and a probe over 200 rows. No census, no plan, no full-table hash.
-- (The first version hashed all 148 k rows and wrote ~99 k plan rows inside the apply, ~36 s; an apply can lock
-- sign-in.) scripts/kb/trim_kb_chunks.mjs --run builds the census at run time, at night, under the load guard:
--   fn_kb_trim_hash_page(after, n)  hashes n rows (1..5000) after an id into kb_trim_hash: a pkey walk, one page.
--   fn_kb_trim_plan_build()        from the narrow kb_trim_hash only (no kb_chunks read) picks keepers, fills
--                                  kb_trim_plan and writes the census (verdict TRIM, batch_no NULL) before any delete.
--   fn_kb_trim_batch(n)            deletes at most n (1..5000) planned ids in id order and takes them out of the plan,
--                                  so no batch re-walks done ids; advisory lock shared with the purge; lock_timeout 2 s.
--   Read-back: every clause-7 row's keeper_id is still in kb_chunks (pkey lookups, no re-hash).
--   No VACUUM FULL, no pg_repack: that rewrite is docs/runbooks/kb_chunks_rewrite.md, and needs the founder's go.
--   The deleted rows remain in the newest full export (the driver resolves it and refuses if it is older than the table).
--
-- Prevented by: scripts/checks/the_kb_trim_keeps_one_copy_and_never_a_cited_row.test.mjs.

alter table public.kb_purge_ledger drop constraint if exists kb_purge_ledger_verdict_check;
alter table public.kb_purge_ledger add constraint kb_purge_ledger_verdict_check
  check (verdict in ('KEEP', 'UNSURE', 'DELETE', 'SIZE', 'TRIM'));
alter table public.kb_purge_ledger drop constraint if exists kb_purge_ledger_clause_check;
alter table public.kb_purge_ledger add constraint kb_purge_ledger_clause_check check (clause between 0 and 7);

-- One narrow row per kb_chunks row: the exact-duplicate key and the keeper preference. Kept after the trim: the read-back.
create table if not exists public.kb_trim_hash (
  id bigint primary key,
  k text not null,                  -- md5(content) || md5(title || US || category)
  pref smallint not null,           -- 0 not qd_kb_pack with a citation (verified), 1 no citation, 2 qd_kb_pack
  is_qd boolean not null,
  clause smallint check (clause in (6, 7)),
  keeper_id bigint                  -- clause 7: the copy that stays
);
alter table public.kb_trim_hash enable row level security;
drop policy if exists kb_trim_hash_service_role_only on public.kb_trim_hash;
create policy kb_trim_hash_service_role_only on public.kb_trim_hash as permissive for all to public using (false) with check (false);
revoke all on public.kb_trim_hash from anon, authenticated;

-- The work queue: a deleted id leaves it, so a batch never re-walks done ids.
create table if not exists public.kb_trim_plan (
  id bigint primary key,
  clause smallint not null check (clause in (6, 7)),
  planned_at timestamptz not null default now()
);
alter table public.kb_trim_plan enable row level security;
drop policy if exists kb_trim_plan_service_role_only on public.kb_trim_plan;
create policy kb_trim_plan_service_role_only on public.kb_trim_plan as permissive for all to public using (false) with check (false);
revoke all on public.kb_trim_plan from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('kb_trim_hash', false, 'cache', 'Working hashes of kb_chunks for the night trim, rebuilt from kb_chunks on every run.', 'it_engineer'),
  ('kb_trim_plan', false, 'cache', 'The night trim''s work list, rebuilt from kb_trim_hash on every run and emptied as it goes.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_kb_trim_hash_page(p_after bigint, p_limit integer default 2000)
returns table (last_id bigint, hashed bigint)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set enable_seqscan to 'off'
set max_parallel_workers_per_gather to '0'
as $fn$
declare v_last bigint; v_n bigint;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_kb_trim_hash_page: p_limit must be 1..5000 (got %)', p_limit;
  end if;
  if exists (select 1 from public.kb_trim_plan) then
    raise exception 'fn_kb_trim_hash_page: a plan is being worked; finish it with scripts/kb/trim_kb_chunks.mjs --run';
  end if;
  with pg as (
    select k.id, md5(k.content) || md5(coalesce(k.title, '') || chr(31) || coalesce(k.category, '')) k,
           (case when k.source_kind = 'qd_kb_pack' then 2 when coalesce(k.citation, '') = '' then 1 else 0 end)::smallint pref,
           k.source_kind = 'qd_kb_pack' is_qd
      from public.kb_chunks k where k.id > coalesce(p_after, 0) order by k.id limit p_limit
  ), ins as (
    insert into public.kb_trim_hash (id, k, pref, is_qd) select id, k, pref, is_qd from pg
    on conflict (id) do update set k = excluded.k, pref = excluded.pref, is_qd = excluded.is_qd, clause = null, keeper_id = null
    returning id
  )
  select max(id), count(*) into v_last, v_n from ins;
  return query select v_last, v_n;
end $fn$;
revoke execute on function public.fn_kb_trim_hash_page(bigint, integer) from public, anon, authenticated;

-- p_upto is for the apply's probe only (plan a hashed subset); the driver passes nothing and the full reach is checked.
create or replace function public.fn_kb_trim_plan_build(p_upto bigint default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v6 bigint; v7 bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then
    raise exception 'fn_kb_trim_plan_build: a purge or trim batch is running';
  end if;
  if exists (select 1 from public.kb_trim_plan) then
    raise exception 'fn_kb_trim_plan_build: a plan is being worked; finish it with scripts/kb/trim_kb_chunks.mjs --run';
  end if;
  if p_upto is null and exists (select 1 from public.kb_chunks where id > coalesce((select max(id) from public.kb_trim_hash), 0)) then
    raise exception 'fn_kb_trim_plan_build: kb_trim_hash does not reach the newest kb_chunks id; hash the remaining pages first';
  end if;
  delete from public.kb_purge_ledger where verdict = 'TRIM' and batch_no is null;
  delete from public.kb_trim_hash h where not exists (select 1 from public.kb_chunks k where k.id = h.id);

  with cited as (select distinct split_part(x, ':', 2)::bigint id from public.sales_decision_log s, unnest(s.cited) x
                  where x ~ '^kb_chunks:[0-9]+$'),
  r as (select h.id, h.is_qd, (c.id is not null) is_cited,
               first_value(h.id) over w keeper, first_value(h.is_qd) over w keeper_qd
          from public.kb_trim_hash h left join cited c on c.id = h.id
         where h.id <= coalesce(p_upto, h.id)
        window w as (partition by h.k order by h.pref, h.id)),
  v as (select id, keeper,
               (case when is_cited then null
                     when is_qd then 6
                     when id <> keeper and not keeper_qd then 7 end)::smallint clause from r)
  update public.kb_trim_hash h set clause = v.clause, keeper_id = case when v.clause = 7 then v.keeper end
    from v where v.id = h.id;
  insert into public.kb_trim_plan (id, clause)
  select id, clause from public.kb_trim_hash where clause is not null and id <= coalesce(p_upto, id);

  insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, note)
  select 'TRIM', c.clause, case c.clause when 6 then 'qd_kb_pack' else 'duplicate' end, null,
         (select count(*) from public.kb_trim_plan p where p.clause = c.clause),
         'census before the first trim batch (ledger 1085)'
    from (values (6::smallint), (7::smallint)) c(clause);   -- both rows always: an empty clause is a census too
  select count(*) filter (where clause = 6), count(*) filter (where clause = 7) into v6, v7 from public.kb_trim_plan;
  return jsonb_build_object('clause6_qd_kb_pack', v6, 'clause7_duplicate', v7);
end $fn$;
revoke execute on function public.fn_kb_trim_plan_build(bigint) from public, anon, authenticated;

drop function if exists public.fn_kb_trim_census();

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
    raise exception 'fn_kb_trim_batch: no census in kb_purge_ledger - run select public.fn_kb_trim_plan_build() first';
  end if;
  select coalesce(max(l.batch_no), 0) + 1 into v_batch
    from public.kb_purge_ledger l where l.verdict = 'TRIM' and l.batch_no is not null;
  perform set_config('qd.export_change_bulk', 'kb_chunks', true);

  with pick as (
    select p.id, p.clause from public.kb_trim_plan p order by p.id limit p_limit
  ), done as (
    delete from public.kb_trim_plan p using pick where p.id = pick.id returning p.id
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
  select count(*) into v_left from public.kb_trim_plan p;
  return query select v_batch, v_deleted, v_bytes, v_from, v_to, v_left;
end $fn$;
revoke execute on function public.fn_kb_trim_batch(integer) from public, anon, authenticated;

-- Probe (nothing kept; 200 rows from the first qd_kb_pack id, a few seconds): the full build refuses while the hash does not reach the newest id;
-- the build then plans the 200 hashed ids; one 20-row batch deletes exactly what it reports and takes those ids out of
-- the plan; no cited id and no keeper is planned. All inside a block that ends in raise exception.
create temporary table if not exists qd_probe_trim (hashed bigint, refused boolean, planned bigint, deleted bigint,
  live_drop bigint, cited bigint, keeper_planned bigint, plan_left bigint) on commit drop;
do $$ declare hp record; b record; v_ref boolean := false; v_planned bigint; v_drop bigint; v_cited bigint;
  v_kp bigint; v_left bigint; v_live0 bigint; begin
  begin
    select * into hp from public.fn_kb_trim_hash_page((select min(id) - 1 from public.kb_chunks where source_kind = 'qd_kb_pack'), 200);
    begin
      perform public.fn_kb_trim_plan_build();
    exception when others then v_ref := sqlerrm like '%does not reach%';
    end;
    perform public.fn_kb_trim_plan_build(hp.last_id);
    select count(*) into v_planned from public.kb_trim_plan;
    select count(*) into v_live0 from public.kb_chunks where id <= hp.last_id;
    select * into b from public.fn_kb_trim_batch(20);
    v_drop := v_live0 - (select count(*) from public.kb_chunks where id <= hp.last_id);
    select count(*) into v_cited from public.kb_trim_hash h where h.clause is not null and h.id in
      (select split_part(x, ':', 2)::bigint from public.sales_decision_log s, unnest(s.cited) x where x ~ '^kb_chunks:[0-9]+$');
    select count(*) into v_kp from public.kb_trim_hash h where h.clause = 7
       and exists (select 1 from public.kb_trim_hash q where q.id = h.keeper_id and q.clause is not null);
    select count(*) into v_left from public.kb_trim_plan;
    raise exception 'qd_probe_rollback';
  exception when others then
    if sqlerrm <> 'qd_probe_rollback' then raise; end if;
  end;
  insert into qd_probe_trim values (hp.hashed, v_ref, v_planned, b.deleted_count, v_drop, v_cited, v_kp, v_left);
end $$;
select case when t.hashed = 200 and t.refused and t.planned > 0 and t.deleted = least(20, t.planned)
             and t.live_drop = t.deleted and t.plan_left = t.planned - t.deleted and t.cited = 0 and t.keeper_planned = 0
             and (select count(*) from public.kb_trim_plan) = 0 and (select count(*) from public.kb_trim_hash) = 0
             and (select count(*) from public.kb_purge_ledger where verdict = 'TRIM') = 0
            then 'PROBE OK (200 hashed, ' || t.planned || ' planned, ' || t.deleted || ' deleted and rolled back)'
            else 'PROBE FAILED: ' || row_to_json(t)::text end as verdict
  from qd_probe_trim t;
