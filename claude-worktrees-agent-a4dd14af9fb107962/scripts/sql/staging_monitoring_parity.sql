-- Staging monitoring parity, and a monitoring gate that measures monitors instead of counting jobs.
--
-- fn_os_portals_gates measured on STAGING showed five gates short of production, and three of
-- them were staging simply not being configured the same way rather than anything about the packs:
--   control_mode_sweep_5min  scheduled on production, absent on staging
--   smoke_test_30min         scheduled on production, absent on staging (0 runs in 24 hours)
--   "monitoring configured"  keyed to an arbitrary "more than 50 cron jobs" — production has 162,
--                            staging has 33, and the count says nothing about whether anything is
--                            being watched
-- Both functions already exist on staging; only the schedules were missing. A rehearsal surface
-- that does not run the monitors cannot rehearse a monitoring failure.
--
-- The gate predicate is replaced with the named monitors it is actually about — the failure
-- watcher, the control-mode sweep and the smoke test, each scheduled AND having succeeded inside
-- its own window. That is narrower than "more than 50 jobs exist", so it is a harder check, and
-- it is the same check on both projects.
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'control_mode_sweep_5min') then
    -- CRON REMOVED 7 Sep 2026 (founder: "Remove it from the code. Delete, not archive.").
    -- This scheduled control_mode_sweep_5min, which was deleted from cron.job in the same change.
    -- The notice replaces the call so this routine still runs and still reports, rather
    -- than silently doing nothing or quietly recreating a job nobody asked for.
    raise notice 'cron scheduling removed on 7 Sep 2026: control_mode_sweep_5min is not recreated';
  end if;
  if not exists (select 1 from cron.job where jobname = 'smoke_test_30min') then
    -- CRON REMOVED 7 Sep 2026 (founder: "Remove it from the code. Delete, not archive.").
    -- This scheduled smoke_test_30min, which was deleted from cron.job in the same change.
    -- The notice replaces the call so this routine still runs and still reports, rather
    -- than silently doing nothing or quietly recreating a job nobody asked for.
    raise notice 'cron scheduling removed on 7 Sep 2026: smoke_test_30min is not recreated';
  end if;
  if not exists (select 1 from cron.job where jobname = 'watch_failed_runs_hourly') then
    -- CRON REMOVED 7 Sep 2026 (founder: "Remove it from the code. Delete, not archive.").
    -- This scheduled watch_failed_runs_hourly, which was deleted from cron.job in the same change.
    -- The notice replaces the call so this routine still runs and still reports, rather
    -- than silently doing nothing or quietly recreating a job nobody asked for.
    raise notice 'cron scheduling removed on 7 Sep 2026: watch_failed_runs_hourly is not recreated';
  end if;
end $$;
