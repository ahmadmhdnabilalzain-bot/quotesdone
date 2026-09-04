-- REGISTER the four crons re-enabled by the routing/reputation packet as Phase D committed-scenario
-- cron sources.
--
-- reallocate_monthly, model_benchmark_daily, sop_update_weekly and reputation_weekly were switched
-- back on (3 Sep 2026) as traced kernel components. Each reaches a kernel-WATCHED relation through
-- the routine it runs, and fn_phase_d_committed_scenario_open refuses to open while any ACTIVE cron
-- that reaches a watched relation is unregistered ("every_active_cron_that_reaches_a_watched_
-- relation_is_registered") — which is what turned the kernel_positive_controls door
-- fn_phase_d_committed_scenario_close red. `reaches` below is what each routine's body actually
-- writes (read from the deployed definitions, not assumed); `quarantine` is why a committed fixture
-- scenario is not contaminated by it.
--
-- SAFE, same as the 60+ monitors already registered: each runs on its own cron tick in its own
-- transaction, so it cannot see a scenario's uncommitted ZZ DEMO fixture; it only ever writes rows
-- about the REAL estate (budgets, models, the scheduler, employees); and close() asserts that the
-- rows THIS scenario created are gone by id/marker, not by a watermark count, so these background
-- writes do not move the watermark or fail close().
--
--   node scripts/apply_sql.mjs scripts/sql/register_routing_reputation_crons_phase_d.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
  (166, 'reallocate_monthly',
   'fn_reallocate: moves AI budget from idle to saturated departments — writes public.allocation_change (the ledger row per move, policy cited), updates public.department_budget.monthly_aed, and writes public.agent_runs (its run-log). Reads department_budget only; no marketplace relation.',
   'Budget reallocation (3 Sep 2026). Own transaction on a monthly tick; reads department_budget, which no scenario fixture seeds; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.'),
  (173, 'model_benchmark_daily',
   'fn_model_benchmark: compares models over 90 days of ai_cost_log/llm_attempt — deletes and re-inserts today''s public.model_outcome rows (fn = fn_model_benchmark), updates public.model_registry.quality_score, writes public.agent_runs. Arithmetic over history; no provider call, no marketplace relation.',
   'Model benchmark (3 Sep 2026). Own transaction on a daily tick; reads only the model call ledgers, which a fixture scenario does not write while the paid model is held; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker.'),
  (158, 'sop_update_weekly',
   'fn_sop_update: re-derives the manual from the scheduler — inserts public.cron_registry rows for active undocumented jobs and deletes rows for jobs that no longer exist, inserts public.os_runbooks from graded institutional_memory lessons, writes public.agent_runs. Reads cron.job and institutional_memory; no marketplace relation.',
   'Manual regeneration (3 Sep 2026). Own transaction on a weekly tick; reads the scheduler and the lessons ledger, neither of which a fixture scenario seeds; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker.'),
  (161, 'reputation_weekly',
   'fn_reputation_recompute: scores every org_agents row on six dimensions from outcome_record, review_chain, decision_log, agent_training_attempt, ai_cost_log, org_tasks and agent_runs — upserts public.agent_reputation, updates public.employee_authority.max_tier on probation/recovery, inserts public.autonomy_control_audit for each authority change, writes public.agent_runs. Pauses itself while a company_stand_down is open.',
   'Reputation recompute (3 Sep 2026). Own transaction on a weekly tick; scores employees over their whole recorded history, so a scenario''s rows (ZZ DEMO customers, suppliers, inquiries) are not among its sources; cannot see a scenario''s uncommitted fixture; close() asserts scenario rows by id/marker, so its writes do not move the watermark.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

commit;
