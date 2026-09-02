-- Static declaration for the 1 new cron component from the PCCR-009 re-enablement
-- (employee_kpi_assign_daily). phase_c_component_crosswalk requires every runtime component be
-- declared in committed SQL; the row already exists in production (idempotent no-op re-apply).
--
--   node scripts/apply_sql.mjs scripts/sql/pccr009_declare_the_new_cron_component.sql --apply --ddl

begin;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
values (
  'cron:employee_kpi_assign_daily', 'cron_job', 'cron.job/290', 'pg_cron schedule', 'pg_cron', 'no', '40 4 * * *', true, 'system.scheduler', 'system.scheduler', 'chief_operating_officer', 'people_ops', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)', 'wrapped + re-enabled 2 Sep 2026')
on conflict (component_id) do nothing;

commit;
