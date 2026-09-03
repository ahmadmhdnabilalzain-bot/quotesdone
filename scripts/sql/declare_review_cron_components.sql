-- COMPONENT DECLARATIONS for the two review crons enabled with the self-management loop.
--
-- objective_review_weekly (job 285) and promotion_review_weekly (job 282) were wrapped and enabled by
-- fn_kernel_wrap_and_enable_cron (a non-literal insert...select, which the component-crosswalk check
-- records but does not read as a declaration). Every crosswalk row must be backed by a committed
-- literal declaration OR a historical exception — so this file declares them, matching the live rows
-- the wrap function created (current_actor 'system.scheduler', workflow_id 'SYSTEM_SCOPE') and the
-- crosswalk rows in docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv exactly. Idempotent: live
-- already holds these rows, so this is a no-op on re-apply and exists to satisfy the declaration audit.
--
--   node scripts/apply_sql.mjs scripts/sql/declare_review_cron_components.sql --apply --ddl

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
  schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id,
  department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
  activation_state, classification, gap, repair_or_keep_action, evidence
) values
  ('cron:objective_review_weekly', 'cron_job', 'cron.job/285', 'pg_cron schedule', 'pg_cron', 'no', '30 5 * * 1', true, 'system.scheduler', 'system.scheduler', 'ceo', 'exec', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026'),
  ('cron:promotion_review_weekly', 'cron_job', 'cron.job/282', 'pg_cron schedule', 'pg_cron', 'no', '30 6 * * 1', true, 'system.scheduler', 'system.scheduler', 'corporate_performance_director', 'exec', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026')
on conflict (component_id) do nothing;
