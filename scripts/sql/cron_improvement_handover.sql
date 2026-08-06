-- The schedule that makes fn_improvement_handover a MECHANISM rather than a one-off sweep.
--
-- Hourly, at :10, deliberately away from :40 (fn_task_approve) and :50 (cos_execute) so the three
-- hourly governance jobs do not contend. The questions are raised WEEKLY by fn_os_improve, so an
-- hour of latency is immaterial; what the hourly cadence buys is that a question raised at any time
-- is in its owner's queue within the hour, and that the sweep self-heals — switch it off and the
-- undelivered count climbs until comp-17 goes MISSING inside its 21-day window.
--
-- cron.schedule() UPSERTS on the job name, so re-applying this file cannot create a second job.
-- Wrapped in a guard so the file is a no-op where pg_cron is absent rather than an error, which is
-- the difference between a project that is behind and a deploy that fails halfway.
--
-- The guard is a pg_proc lookup, NOT to_regproc('cron.schedule'): cron.schedule is OVERLOADED
-- (2-arg and 3-arg), to_regproc returns NULL on an ambiguous name, and the first version of this
-- file therefore skipped the schedule on both projects while reporting success. Measured, then
-- fixed — a guard that is silently always-false is worse than no guard.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise notice 'pg_cron not installed; improvement_handover_hourly not scheduled';
    return;
  end if;
  perform cron.schedule('improvement_handover_hourly', '10 * * * *',
                        'select public.fn_improvement_handover();');
end $$;
