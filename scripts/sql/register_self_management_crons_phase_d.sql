-- REGISTER the self-management crons as Phase D committed-scenario cron sources.
--
-- The deterministic KPI / review / learning crons enabled this session reach kernel-WATCHED relations
-- (org_tasks, company_event, org_agents, plus their own agent_runs run-log) through the routines they
-- call. fn_phase_d_committed_scenario_open refuses to open while any ACTIVE cron that reaches a watched
-- relation is unregistered ("every_active_cron_that_reaches_a_watched_relation_is_registered"), which
-- is what made the kernel_positive_controls door fn_phase_d_committed_scenario_close fail. Registering
-- them here — exactly as reenable_the_dispatch_and_action_runtime.sql registered the dispatch tier —
-- records what each writes and why it is safe for the committed-scenario mechanism.
--
-- SAFE, same as the 50+ monitors already registered: each runs on its own cron tick in its own
-- transaction, so it cannot see a scenario's uncommitted ZZ DEMO fixture; it only ever writes rows
-- about the REAL estate; and close() asserts that the rows THIS scenario created are gone by id/marker,
-- not by a watermark count, so these background writes do not move the watermark or fail close().
--
--   node scripts/apply_sql.mjs scripts/sql/register_self_management_crons_phase_d.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
  (285, 'objective_review_weekly',
   'Reviews department/company objectives and records the outcome: writes public.agent_runs (its run-log) and org_tasks/company_event rows about the real estate.',
   'Self-management review (3 Sep 2026). Own transaction on a weekly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (205, 'improvement_handover_hourly',
   'Hands a graded improvement to its owning department: writes public.agent_runs and org_tasks about the real estate.',
   'Self-management handover (3 Sep 2026). Own transaction on an hourly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (140, 'kpi_review_weekly',
   'Reviews the KPI scoreboard and opens follow-ups: writes public.agent_runs and org_tasks about the real estate.',
   'Self-management review (3 Sep 2026). Own transaction on a weekly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (184, 'improvement_plan_daily',
   'Refreshes the improvement plan against measured outcomes: writes public.agent_runs and org_tasks about the real estate.',
   'Self-management planner (3 Sep 2026). Own transaction on a daily tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (84, 'strategy_ai_daily',
   'Refreshes deterministic company strategy signals: writes public.agent_runs and company_event/org_tasks about the real estate.',
   'Self-management strategy refresh (3 Sep 2026). Own transaction on a daily tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (204, 'learning_loop_sweep_hourly',
   'Sweeps the learning loop, promoting what worked: writes public.agent_runs and org_tasks about the real estate.',
   'Self-management learning loop (3 Sep 2026). Own transaction on an hourly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (282, 'promotion_review_weekly',
   'Reviews employee promotions on measured performance: writes public.agent_runs and org_agents/org_tasks about the real estate.',
   'Self-management review (3 Sep 2026). Own transaction on a weekly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (139, 'self_review_weekly',
   'Runs the process self-review, flagging repeated failures: writes public.agent_runs and company_event (process.repeated_failure) about the real estate.',
   'Self-management review (3 Sep 2026). Own transaction on a weekly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (156, 'os_review_weekly',
   'Runs the weekly operating-system review: writes public.agent_runs and org_tasks about the real estate.',
   'Self-management review (3 Sep 2026). Own transaction on a weekly tick; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

commit;
