-- THE RESTORE DRILL RUNS UNTIL IT PASSES, ONCE EVERY CALENDAR MONTH.
--
-- Assigned: it_engineer (IT duty 19, restore_table).
--
-- MEASURED (28 Sep 2026, production htdblwldjkcgjvmqkbeh): it_restore_drill_result holds 2 rows ever -
--   #3  14 Sep  supplier_dues  restored 0  ok false
--   #70 15 Sep  quotes         restored 0  ok true (vacuous: the_restore_drill_passes_only_on_rows_it_actually_restored.sql
--                                           made an empty restore a failure on 23 Sep)
-- and fn_it_restore_table_due() answered false: the cadence is "30 days since the last ATTEMPT"
-- (it_duty_schedule 'restore_table'), so the next drill would be ~15 Oct and no drill has ever restored a row.
-- A backup is proved restorable only by a PASS - rows restored from the newest export into scratch and found
-- identical to live - so the schedule now keys on passes, not on attempts:
--   due when the current calendar month has no passing drill, at most once every 20 hours,
--   OR the old conditions (the 30-day schedule, or an open restore finding).
-- So the drill runs on the first tick of every month (and on the first tick after this applies), and a failing
-- drill is retried daily until it passes, while fn_it_restore_table_overdue keeps paging on the silence.
-- Everything else in the body is the canonical one in the_it_engineer_restores_a_table_sample_every_month.sql.
--
-- Prevented by: scripts/checks/the_restore_drill_runs_until_it_passes_once_every_calendar_month.test.mjs and the
-- verdict row at the end of this file.

create or replace function public.fn_it_restore_table_due()
returns boolean language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set lock_timeout to '250ms'
as $fn$
begin
  return ('restore_table' = any (public.fn_it_scheduled_due())
          -- no passing drill yet this calendar month: run, and retry at most once every 20 hours until one passes
          or (not exists (select 1 from public.it_restore_drill_result d
                           where d.ok and coalesce((d.detail->>'restored')::int, 0) > 0
                             and d.ran_at >= date_trunc('month', now()))
              and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                               and started_at > now() - interval '20 hours'))
          or (exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key like 'duty:restore\_table:%')
              and (not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                                and started_at > now() - interval '20 hours')
                   -- a finished export newer than the one the last drill read: re-check at once, so a
                   -- stale-export finding closes the tick after the export lands, inside the loop's window
                   or exists (select 1 from public.table_export_run r
                               where r.status = 'done' and r.stamp::text > coalesce(
                                 (select d.detail->>'newest_export_day' from public.it_restore_drill_result d order by d.id desc limit 1), '')))))
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick'
                      and started_at > now() - interval '6 hours');
exception when lock_not_available then
  -- In the postgres log, which the db_health duty reads: a skipped tick is never silent.
  raise warning 'fn_it_restore_table_due: a lock held elsewhere outlived lock_timeout 250ms; not due this tick (55P03)';
  return false;   -- another transaction holds a lock on something this reads: not due this tick
end $fn$;

-- ── VERDICT: the function RUNS (a probe runs the routine) and, with no passing drill this month, is due ──
select case
  when exists (select 1 from public.it_restore_drill_result d where d.ok and coalesce((d.detail->>'restored')::int, 0) > 0
                 and d.ran_at >= date_trunc('month', now()))
    then case when public.fn_it_restore_table_due() is not null then 'PROBE OK' else 'PROBE FAILED: the due check returned null' end
  when exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' in ('duty:restore_table', 'restore_table_pick')
                 and started_at > now() - interval '20 hours')
    then 'PROBE OK'
  when public.fn_it_restore_table_due() then 'PROBE OK'
  else 'PROBE FAILED: no passing drill this month and none in 20 hours, yet the drill is not due' end as verdict;
