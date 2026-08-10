-- Two pack artefacts that had a runner and no schedule. Both routines already existed and had
-- ZERO callers, which is the same "stored, never run" shape as the corpus itself.
--
--  * kb_operational_route_test  — 344 cases, last executed 2026-08-02, guarded nothing since.
--  * ops_kb_stage.scenarios     — 282 pack scenarios; fn_ops_run_scenarios() has no caller, so
--                                 last_run has not moved and a scenario that stops being RUNNABLE
--                                 would never be noticed.
--
-- Deliberately off the hour: 05 and 25 past, so they do not land on the same minute as the
-- ~90 existing jobs that already cluster on :00, :10, :15, :20 and :35.
select cron.schedule('kb_route_tests_hourly', '5 * * * *', $$select public.fn_kb_route_test_run(400);$$);
select cron.schedule('ops_scenarios_hourly',  '25 * * * *', $$select public.fn_ops_run_scenarios();$$);
