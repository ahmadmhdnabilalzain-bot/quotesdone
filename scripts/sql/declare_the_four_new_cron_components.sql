-- Static literal declarations for the 4 genuinely-new cron components created when the
-- deterministic automation was re-enabled (2 Sep 2026). phase_c_component_crosswalk.test.mjs
-- requires every runtime component to be DECLARED in committed SQL with literal values; the dynamic
-- fn_kernel_wrap_and_enable_cron insert (now an insert...select) is not a literal declaration. These
-- 4 rows already exist in production (inserted by that function); this file is their committed
-- declaration and re-applies as a no-op (ON CONFLICT DO NOTHING). The other 22 re-enabled crons were
-- already declared before the stand-down.
--
--   node scripts/apply_sql.mjs scripts/sql/declare_the_four_new_cron_components.sql --apply --ddl

begin;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
values (
  'cron:handoff_watchdog_6h', 'cron_job', 'cron.job/289', 'pg_cron schedule', 'pg_cron', 'no', '0 */6 * * *', true, 'system.scheduler', 'system.scheduler', 'it_operations_engineer', 'assurance', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026')
on conflict (component_id) do nothing;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
values (
  'cron:incident_watchdog_hourly', 'cron_job', 'cron.job/279', 'pg_cron schedule', 'pg_cron', 'no', '20 * * * *', true, 'system.scheduler', 'system.scheduler', 'it_operations_engineer', 'assurance', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026')
on conflict (component_id) do nothing;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
values (
  'cron:org_task_sla_watch_daily', 'cron_job', 'cron.job/286', 'pg_cron schedule', 'pg_cron', 'no', '0 6 * * *', true, 'system.scheduler', 'system.scheduler', 'it_operations_engineer', 'assurance', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026')
on conflict (component_id) do nothing;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
values (
  'cron:remediation_escalate_consume_daily', 'cron_job', 'cron.job/281', 'pg_cron schedule', 'pg_cron', 'no', '15 5 * * *', true, 'system.scheduler', 'system.scheduler', 'chief_of_staff', 'exec', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026')
on conflict (component_id) do nothing;

commit;
