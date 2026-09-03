-- The literal declaration of the ad spend autopilot tick (3 Sep 2026).
-- fn_kernel_wrap_and_enable_cron declared cron:ads_autopilot_daily DYNAMICALLY (insert ... select) when
-- scripts/sql/ads_autopilot_schedule.sql wrapped job 316, and stamped it with the wrap's re-enable
-- boilerplate. CI wants a literal declaration, and the truth is that this component was BUILT today,
-- not re-enabled — so this file both declares it literally and corrects evidence / repair_or_keep_action
-- on the live row to the same values the committed crosswalk carries.
insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
  schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id,
  department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
  activation_state, classification, gap, repair_or_keep_action, evidence
) values
  ('cron:ads_autopilot_daily', 'cron_job', 'cron.job/316', 'pg_cron schedule', 'pg_cron', 'no', '20 4 * * *', true, 'system.scheduler', 'system.scheduler', 'marketing_director', 'growth', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick', 'active', 'WIRE_TO_CANONICAL', '',
   'built 3 Sep 2026: the deterministic paid-media manager tick (scripts/sql/ads_autopilot_schedule.sql); executes only through the ceiling-guarded ad_decision ledger',
   'scheduled and wrapped 3 Sep 2026 as the ad spend autopilot daily tick; first traced tick 8881606 (0 real campaigns / 0 decisions)')
on conflict (component_id) do update set repair_or_keep_action = excluded.repair_or_keep_action, evidence = excluded.evidence;
