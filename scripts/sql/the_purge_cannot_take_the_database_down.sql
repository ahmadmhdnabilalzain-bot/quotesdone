-- THE PURGE CANNOT TAKE THE DATABASE DOWN
--
-- Seat: it_engineer. 21 Sep 2026. Supersedes fn_kb_purge_batch from
-- the_foreign_bulk_leaves_the_knowledge_library_permanently.sql and trg_table_export_change from
-- we_back_up_the_extra_stuff_only_unless_they_got_updated.sql (both bodies carried over; changes below).
--
-- WHAT HAPPENED (measured, 21 Sep 2026): `purge_kb_bulk.mjs --run` called fn_kb_purge_batch(50000) at
-- ~17:35 UTC. No batch completed (ledger: 0 batches). At 17:44:10 UTC PostgreSQL restarted with
-- "database system was interrupted; last known up at 17:39:59" and NO shutdown line before it: a hard
-- kill. The dashboard's memory chart for the window: Used rose from ~0.45 GB (17:34) to ~2.2 GB (17:43),
-- memory commitment crossed the 2.87 GB commit limit at ~17:39 and reached ~4.2 GB at 17:43, swap
-- spiked at 17:43, then the restart. Compute is Medium: 2 shared vCPU, 4 GB RAM; disk 18 GB, 5.4 GB free.
-- Other sessions' applies (PR 783, PR 788, supplier-invite probes) ran in the same minutes and waited
-- on locks on notifications/auth.users; they share the blame for the memory, and nothing in the logs
-- the platform exposes attributes the 1.7 GB to one backend. What IS measured about the purge:
--   1. THE PLAN FLIPS AT ~7,000 ROWS. The planner estimates 6,989 rows match
--      `fn_kb_purge_clause(...) = 5` (a function's default selectivity). For LIMIT 5,000 it walks the
--      primary key (Gather Merge over the pkey); for LIMIT 50,000 it plans a parallel SEQUENTIAL SCAN
--      of all 2.6 M rows evaluating three regexes each, then a sort — ~210 s at the measured
--      12,500 rows/s. So every 50,000 batch outlived the ~100 s gateway (524) by design.
--   2. THE DRIVER RETRIED IT. The batch call went through sql()'s default retry5xx=true, so each 524
--      started ANOTHER full-scan delete while the first backend was still running (a 524 does not
--      cancel the backend): up to 7 overlapping batches, each with its parallel worker.
--   3. One rolled-back transaction (fn_kb_purge_batch at 500, 2,000, 5,000 in sequence, then raise):
--        500   rows: 3.05 s, 17.7 MB WAL (first batch after a checkpoint: full-page images), cursor walked ids 0..180,446
--        2,000 rows: 2.04 s, 14.0 MB WAL, backend memory 6.8 MB
--        5,000 rows: 2.44 s, 22.6 MB WAL, backend memory 10.8 MB (~0.8 KB per row deleted in the transaction)
--      table_export_change gained exactly one row per deleted row (500 / 2,000 / 5,000).
--      WAL is ~4.5 KB per deleted row: the whole purge (2,467,071 rows) writes ~11 GB of WAL, on a disk
--      with 5.4 GB free and max_wal_size 4 GB. The pace must be bounded, not only the batch.
--   4. DELETE does not touch the HNSW or GIN index; the cost of those comes at VACUUM (index cleanup).
--      A rebuild of HNSW on 150,000 rows did not finish inside an 85 s statement (measured, rolled back),
--      so the rebuild runs from a direct session without the 2-minute cap (purge_kb_bulk.mjs prints it).
--
-- WHAT CHANGES
--   fn_kb_purge_batch v2: default 2,000, hard maximum 5,000 (was 50,000 / 200,000). SET enable_seqscan
--     off and max_parallel_workers_per_gather 0 on the function, so the pick is ALWAYS the pkey walk and
--     never a whole-table scan or a parallel worker, whatever the estimate. SET lock_timeout 2s, and a
--     transaction advisory lock: a second overlapping batch refuses instead of queueing behind the first.
--     It marks its own transaction (set_config('qd.export_change_bulk','kb_chunks', true)) so the
--     export trigger records the batch compactly (below).
--   trg_table_export_change v2: on a DELETE inside a transaction marked by the purge, it writes NO row
--     per deleted id; it moves table_export_change_tracked.tracking_since forward — the TRUNCATE rule
--     already in this function — which makes fn_table_export_due force the next export day to be a FULL
--     copy of kb_chunks (fn_table_export_due: `x.tracking_since > v_full_at`). The deleted ids are
--     recorded as ranges in kb_purge_ledger (id_from/id_to per batch), and the 2026-09-18 full copy holds
--     every deleted row. Why not one marker row: fn_table_export_replay casts every deleted row_key to the
--     key type, so a text marker in table_export_change would break the restore drill. Without this,
--     2.47 M change rows would be written and table_export_change (exported whole every day until the
--     next full prunes it) would carry them nightly.
--   fn_kb_purge_load(): the load guard the driver reads before EVERY batch — pg_wal bytes, other active
--     client backends, the longest running statement, another purge backend, today's export running.
--
-- NOT CHANGED: fn_kb_purge_clause, fn_kb_is_us_code, kb_purge_ledger and its census, every index, the
-- INSERT/UPDATE/TRUNCATE branches of the trigger, and the unmarked DELETE branch (every other delete of
-- kb_chunks is still logged row by row).
--
-- PROOF: the verdict row at the end is read-only (catalog + a no-op set_config), PROBE OK / PROBE FAILED.

begin;

-- ── 1. The export trigger: a purge batch forces a full copy instead of logging 2.47 M ids ──────────
create or replace function public.trg_table_export_change()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_pk text := tg_argv[0];
  v_proj text := coalesce(tg_argv[1], '');
begin
  if tg_op = 'TRUNCATE' then
    update public.table_export_change_tracked x set tracking_since = clock_timestamp() where x.table_name = tg_table_name;
    insert into public.table_export_change (table_name, row_key, deleted)
    values (tg_table_name, '(truncate: no row-level record is possible; the next export day is a full copy)', true);
    return null;
  end if;
  -- A bulk purge marks its own transaction (fn_kb_purge_batch). Its deletions are recorded as id ranges
  -- in kb_purge_ledger; the export learns them by the next day being a FULL copy, as for a truncate.
  if tg_op = 'DELETE' and current_setting('qd.export_change_bulk', true) = tg_table_name then
    update public.table_export_change_tracked x set tracking_since = clock_timestamp() where x.table_name = tg_table_name;
    return null;
  end if;
  if tg_op = 'INSERT' then
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, n.%I::text, false from new_rows n',
      tg_table_name, v_pk);
  elsif tg_op = 'DELETE' then
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, o.%I::text, true from old_rows o',
      tg_table_name, v_pk);
  elsif v_proj = '' then
    -- no projection recorded: log every touched row rather than guess that nothing changed
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, n.%I::text, false from new_rows n',
      tg_table_name, v_pk);
  else
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted)
         select %1$L, n.%2$I::text, false from new_rows n join old_rows o on o.%2$I = n.%2$I
          where (%3$s) is distinct from (%4$s)',
      tg_table_name, v_pk,
      'n.' || replace(v_proj, ',', ', n.'), 'o.' || replace(v_proj, ',', ', o.'));
  end if;
  return null;
end $fn$;
revoke execute on function public.trg_table_export_change() from public, anon, authenticated;

-- ── 2. One batch, bounded ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_kb_purge_batch(p_limit integer default 2000)
returns table (batch_no integer, deleted_count bigint, deleted_bytes bigint,
               cursor_from bigint, cursor_to bigint, remaining_count bigint)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set enable_seqscan to 'off'                     -- the pick is the pkey walk, never a 2.6 M-row scan (measured flip at ~7,000)
set max_parallel_workers_per_gather to '0'      -- no parallel worker per batch
set lock_timeout to '2s'
as $$
declare
  v_planned bigint;
  v_done    bigint;
  v_from    bigint;
  v_to      bigint;
  v_batch   integer;
  v_deleted bigint;
  v_bytes   bigint;
begin
  -- 5,000 measured at 2.4 s and 22.6 MB WAL; the ceiling is the measured safe size, not a guess.
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_kb_purge_batch: p_limit must be 1..5000 (got %) — scripts/sql/the_purge_cannot_take_the_database_down.sql', p_limit;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('public.fn_kb_purge_batch')) then
    raise exception 'fn_kb_purge_batch: another purge batch is running — refusing to overlap it';
  end if;

  select sum(l.rows) into v_planned
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.clause = 5 and l.batch_no is null;
  if v_planned is null then
    raise exception 'fn_kb_purge_batch: no census in kb_purge_ledger — run scripts/kb/purge_kb_bulk.mjs, which writes it before the first batch';
  end if;

  select coalesce(max(l.id_to), 0), coalesce(max(l.batch_no), 0), coalesce(sum(l.rows), 0)
    into v_from, v_batch, v_done
    from public.kb_purge_ledger l where l.verdict = 'DELETE' and l.batch_no is not null;
  v_batch := v_batch + 1;

  -- this transaction's deletes are recorded by range here, not id by id (trg_table_export_change)
  perform set_config('qd.export_change_bulk', 'kb_chunks', true);

  with pick as (
    select k.id
      from public.kb_chunks k
     where k.id > v_from
       and public.fn_kb_purge_clause(k.source_kind, k.category, k.citation) = 5
       and k.id not in (select split_part(x, ':', 2)::bigint
                          from public.sales_decision_log s, unnest(s.cited) x
                         where x ~ '^kb_chunks:[0-9]+$')            -- clause 2
     order by k.id
     limit p_limit
  ), del as (
    delete from public.kb_chunks k
     using pick p
     where k.id = p.id
    returning k.id, k.source_kind, k.category, octet_length(k.content) as b
  ), rec as (
    insert into public.kb_purge_ledger (verdict, clause, source_kind, category, rows, bytes, batch_no, id_from, id_to)
    select 'DELETE', 5, d.source_kind, d.category, count(*), sum(d.b), v_batch, v_from, (select max(id) from del)
      from del d
     group by d.source_kind, d.category
    returning rows, bytes, id_to
  )
  select coalesce(sum(r.rows), 0), coalesce(sum(r.bytes), 0), coalesce(max(r.id_to), v_from)
    into v_deleted, v_bytes, v_to
    from rec r;

  return query select v_batch, v_deleted, v_bytes, v_from, v_to,
                      greatest(v_planned - v_done - v_deleted, 0);
end $$;
revoke all on function public.fn_kb_purge_batch(integer) from public, anon, authenticated;
comment on function public.fn_kb_purge_batch(integer) is
  'Deletes one id-ordered batch (1..5000, default 2000) of kb_chunks rows that docs/KNOWLEDGE_DOCTRINE.md §6 classes DELETE (clause 5), skipping ids cited in sales_decision_log.cited. Always a pkey walk (enable_seqscan off), never overlapping (advisory lock), recorded by range in kb_purge_ledger; the export learns the deletes by a forced full copy. the_purge_cannot_take_the_database_down.sql';

-- ── 3. The load guard, read before every batch ─────────────────────────────────────────────────────
create or replace function public.fn_kb_purge_load()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'wal_bytes',        (select coalesce(sum(w.size), 0)::bigint from pg_ls_waldir() w),
    'active_others',    (select count(*)::int from pg_stat_activity a
                          where a.backend_type = 'client backend' and a.state <> 'idle' and a.pid <> pg_backend_pid()),
    'longest_active_s', (select coalesce(max(extract(epoch from now() - a.query_start)), 0)::int from pg_stat_activity a
                          where a.backend_type = 'client backend' and a.state = 'active' and a.pid <> pg_backend_pid()
                            and a.query not ilike '%fn_kb_purge_load%'),
    'purge_running',    (select count(*)::int from pg_stat_activity a
                          where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.query ilike '%fn_kb_purge_batch(%'),
    'export_running',   exists (select 1 from public.table_export_run r
                                 where r.status = 'running' and r.heartbeat_at > now() - interval '10 minutes'),
    'dubai_time',       to_char(now() at time zone 'Asia/Dubai', 'HH24:MI'));
$$;
revoke all on function public.fn_kb_purge_load() from public, anon, authenticated;
comment on function public.fn_kb_purge_load() is
  'What scripts/kb/purge_kb_bulk.mjs reads before every purge batch: pg_wal bytes, other active client backends, the longest running statement, another purge batch, a running export. Decided by scripts/kb/purge_guard.mjs. the_purge_cannot_take_the_database_down.sql';

commit;

-- ── PROOF, AS A ROW (read-only) ────────────────────────────────────────────────────────────────────
with f as (
  select p.proconfig, pg_get_function_arguments(p.oid) as args, p.prosrc
    from pg_proc p where p.oid = 'public.fn_kb_purge_batch(integer)'::regprocedure
), t as (
  select p.prosrc from pg_proc p where p.oid = 'public.trg_table_export_change()'::regprocedure
), m as (
  select
    (select args from f) like '%DEFAULT 2000%'                                         as default_2000,
    (select prosrc from f) like '%p_limit > 5000%'                                      as max_5000,
    (select 'enable_seqscan=off' = any(proconfig) from f)                               as no_seqscan,
    (select 'max_parallel_workers_per_gather=0' = any(proconfig) from f)                as no_parallel,
    (select prosrc from f) like '%pg_try_advisory_xact_lock%'                           as no_overlap,
    (select prosrc from t) like '%qd.export_change_bulk%'                               as trigger_knows_bulk,
    (select count(*) from pg_trigger where tgrelid = 'public.kb_chunks'::regclass and tgname like 'z90_kb_chunks_export_change_%') as export_triggers,
    (public.fn_kb_purge_load() ? 'wal_bytes')                                          as load_guard,
    has_function_privilege('anon', 'public.fn_kb_purge_load()', 'execute')              as anon_can_read_load
)
select case when m.default_2000 and m.max_5000 and m.no_seqscan and m.no_parallel and m.no_overlap
             and m.trigger_knows_bulk and m.export_triggers = 4 and m.load_guard and not m.anon_can_read_load
            then 'PROBE OK' else 'PROBE FAILED' end
       || format(': default_2000=%s max_5000=%s no_seqscan=%s no_parallel=%s no_overlap=%s trigger_knows_bulk=%s export_triggers=%s load_guard=%s anon_can_read_load=%s',
                 m.default_2000, m.max_5000, m.no_seqscan, m.no_parallel, m.no_overlap, m.trigger_knows_bulk,
                 m.export_triggers, m.load_guard, m.anon_can_read_load) as verdict
  from m;
