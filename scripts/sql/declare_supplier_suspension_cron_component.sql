-- Static declaration for the new cron component supplier_suspension_proposed_daily (job 313, the
-- CHAIN-02 deterministic supplier-suspension emitter). phase_c_component_crosswalk requires every
-- runtime component be declared in committed SQL as a literal insert; the row already exists in
-- production (created by fn_kernel_wrap_and_enable_cron), so this is an idempotent no-op re-apply.
--
--   node scripts/apply_sql.mjs scripts/sql/declare_supplier_suspension_cron_component.sql --apply --ddl

begin;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
values (
  'cron:supplier_suspension_proposed_daily', 'cron_job', 'cron.job/313', 'pg_cron schedule', 'pg_cron', 'no', '30 2 * * *', true, 'system.scheduler', 'system.scheduler', 'trust_and_safety_manager', 'legal', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '', 'new; the CHAIN-02 supplier-suspension signal wired as a traced daily cron 2 Sep 2026 (company-loop wiring)', 'scheduled + wrapped 2 Sep 2026')
on conflict (component_id) do nothing;

commit;
