-- THE KB_CHUNKS ROLLBACK COPY IS DROPPED, AND THE SCHEDULER'S HISTORY KEEPS SEVEN DAYS.
--
-- Seat: it_engineer. 9 Nov 2026. Founder approved both deletes the same day ("Yes, do both"), after a Supabase
-- account email reported the database at 11.3 GB for a company with no customers yet.
--
-- MEASURED ON PRODUCTION, 9 Nov 2026 22:35 UTC (pg_database_size = 11 GB):
--   public.kb_chunks_old      8,089 MB   54,360 rows (the live public.kb_chunks: 54,360 rows, 352 MB)
--     The bloated pre-rebuild copy kept as the rollback of the 6-7 Oct copy-and-swap (#1220, #1274).
--     docs/runbooks/kb_chunks_rewrite.md: drop it a day after a passing read-back. It was never dropped.
--     Nothing reads it: pg_depend shows only its own column defaults and trigger; no view, no routine body,
--     no foreign key names it; 0 inserts/updates/deletes since the rebuild. 74% of the whole database.
--   cron.job_run_details      349 MB    698,599 rows since 19 Jul 2026, ~26,000 more a day (92 jobs, 82 of them
--     every 5 minutes), and no job ever deleted any. Supabase's own guidance is to purge it on a schedule.
--
-- WHAT THIS DOES
--   1. Drops public.kb_chunks_old (its own trigger and defaults go with it). Not the copy-and-swap tooling:
--      kb_chunks_swap_log and fn_kb_chunks_swap_log stay for the next rewrite.
--   2. fn_cron_history_purge(keep, batch): deletes finished scheduler runs older than `keep` (7 days), at most
--      `batch` (20,000) rows per call, by runid (the primary key), so no call is the 50k-row seq-scan delete that
--      restarted production on 21 Sep (.claude/memory/a-big-batch-delete-restarted-production.md). Hourly, the
--      ~520,000-row backlog is gone in about a day; after that each run removes about an hour's worth.
--   3. Schedules it hourly at minute 37 (off the :00 and the 5-minute marks the seat duties fire on).
--
-- Prevented by: scripts/checks/the_scheduler_history_is_purged_and_no_rollback_copy_lingers.test.mjs.

drop table if exists public.kb_chunks_old;

create or replace function public.fn_cron_history_purge(p_keep interval default interval '7 days', p_batch int default 20000)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $fn$
declare
  v_cut bigint;
  v_n integer;
begin
  -- The newest run that is old enough. runid rises with start_time, so everything at or below it is older.
  select max(runid) into v_cut
    from cron.job_run_details
   where start_time < now() - p_keep
     and status in ('succeeded', 'failed');
  if v_cut is null then return 0; end if;
  delete from cron.job_run_details
   where runid in (select runid from cron.job_run_details where runid <= v_cut order by runid limit greatest(p_batch, 1));
  get diagnostics v_n = row_count;
  return v_n;
end
$fn$;

revoke execute on function public.fn_cron_history_purge(interval, int) from public, anon, authenticated;

comment on function public.fn_cron_history_purge(interval, int) is
  'Deletes finished pg_cron run history older than p_keep (default 7 days), at most p_batch rows per call, by runid. it_engineer, 9 Nov 2026.';

select cron.schedule('cron_history_purge_hourly', '37 * * * *', $CRON$select public.fn_cron_history_purge();$CRON$);

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with j as (select count(*) n from cron.job where jobname = 'cron_history_purge_hourly' and active),
     f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname = 'fn_cron_history_purge' and p.prosecdef),
     anon as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
               where s.nspname = 'public' and p.proname = 'fn_cron_history_purge' and has_function_privilege('anon', p.oid, 'execute')),
     old as (select to_regclass('public.kb_chunks_old') is not null as still_there),
     live as (select count(*) n from public.kb_chunks)
select case
  when (select still_there from old) then 'PROBE FAILED: public.kb_chunks_old still exists'
  when (select n from live) = 0 then 'PROBE FAILED: public.kb_chunks is empty'
  when (select n from f) <> 1 then 'PROBE FAILED: fn_cron_history_purge missing or not security definer'
  when (select n from anon) <> 0 then 'PROBE FAILED: anon can execute fn_cron_history_purge'
  when (select n from j) <> 1 then 'PROBE FAILED: cron_history_purge_hourly not scheduled and active'
  else 'PROBE OK: kb_chunks_old gone, kb_chunks has ' || (select n from live) || ' rows, hourly purge scheduled, anon cannot run it'
end as verdict;
