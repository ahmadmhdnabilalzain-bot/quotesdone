-- ROLLBACK for phase_d_m01_a_committed_scenario_that_proves_it_left_nothing.sql
--
-- Drops the operation's registers and its guard, watermark and attribution helpers. Run
-- phase_d_m02_..._down.sql FIRST: open() and close() read every one of these.
drop function if exists public.fn_phase_d_row_is_ours(xid);
drop function if exists public.fn_phase_d_committed_scenario_watermarks();
drop function if exists public.fn_phase_d_committed_scenario_guards();
drop table if exists public.phase_d_committed_scenario_cron;
drop table if exists public.phase_d_committed_scenario_watch;
drop table if exists public.phase_d_committed_scenario;
