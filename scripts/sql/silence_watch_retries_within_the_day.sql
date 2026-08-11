-- THE WATCHDOG THAT WATCHES FOR SILENCE WENT SILENT, AND HAD NO SECOND CHANCE.
--
-- MEASURED, production, 11 Aug 2026:
--   agent_silence_watch_daily  06:40:00  status=failed  duration=120.0s
--   "canceling statement due to statement timeout ... fn_agent_silence_watch() line 21"
--   last success: 10 Aug 06:40. Schedule: '40 6 * * *' — once a day.
--
-- IT IS NOT SLOW, AND THE OBVIOUS DIAGNOSIS WAS WRONG. The suspicion was the two full aggregate
-- passes over cron.job_run_details (144,198 rows / 80 MB, growing ~6k/day because cron_history_prune
-- is off). Measured before changing anything:
--   one aggregate pass over the whole history .......... 136 ms
--   the per-job founder_alerts de-dupe LIKE ............ 0.44 ms x ~500 = ~220 ms
--   fn_agent_silence_watch() end to end, on production .. 465 ms   (aborted transaction)
-- So the routine completes in under half a second and the scans are not the cause. Rewriting them
-- would have been a confident fix to a defect that was not there.
--
-- WHAT ACTUALLY HAPPENED. The run lasted 120.0 seconds exactly — the statement timeout — while every
-- other job in that same minute finished in 0.0-0.2s. It was not computing for two minutes; it was
-- blocked for two minutes and then cancelled. A transient.
--
-- THE DEFECT IS THE CADENCE, NOT THE CODE. Three other jobs failed in the same 24 hours
-- (exception_alerts_hourly 07:35, org_task_execute_sweep_hourly x3, action_invoke_collect_5min) and
-- every one of them has already recovered on its own, because they run again within the hour. This
-- one runs at 06:40 and nowhere else, so a single blocked minute takes the company's agent-silence
-- watchdog out for a full day — and it is precisely the routine that would otherwise report its own
-- absence.
--
-- Every alert it can raise is already de-duplicated on a 24-hour window:
--   cron_never_ran, cron_silent, cron_failing  ->  "and created_at > now() - interval '24 hours'"
-- so running it four times a day raises exactly the same alerts as running it once, and simply gives
-- it three more chances to run at all. That is the whole change: the routine is untouched.
-- PRODUCTION-ONLY BY DESIGN. agent_silence_watch_daily is one of the 113 cron jobs listed in
-- scripts/checks/staging_cron_exclusions.json and deliberately does not exist on staging, so the
-- guard is not defensive padding: cron.alter_job(NULL, ...) raises "job_id can not be NULL" and
-- would fail the staging apply on a job that is absent on purpose. project_parity still prints
-- BOTH PROJECTS IN SYNC because the exclusion is declared.
do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'agent_silence_watch_daily';
  if v_job is null then
    raise notice 'agent_silence_watch_daily is not scheduled here (staging excludes it by design); nothing to do';
  else
    perform cron.alter_job(v_job, schedule := '40 */6 * * *');
    raise notice 'agent_silence_watch_daily now runs on 40 */6 * * *';
  end if;
end $$;
