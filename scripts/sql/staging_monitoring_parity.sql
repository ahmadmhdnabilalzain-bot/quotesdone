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
    perform cron.schedule('control_mode_sweep_5min', '*/5 * * * *', 'select public.fn_control_mode_sweep()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'smoke_test_30min') then
    perform cron.schedule('smoke_test_30min', '*/30 * * * *', 'select public.fn_smoke()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'watch_failed_runs_hourly') then
    perform cron.schedule('watch_failed_runs_hourly', '15 * * * *', 'select public.fn_watch_failed_runs();');
  end if;
end $$;
