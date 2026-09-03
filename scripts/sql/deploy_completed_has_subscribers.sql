-- deploy.completed HAS CONSUMERS (3 Sep 2026, MASTER_PLAN A5).
--
-- scripts/deploy_functions.mjs now emits deploy.completed after every verified deploy (proven:
-- company_event 478546 -> change_deployment run 681163b8 on the next bridge tick). The connectivity
-- register then reported the one thing left directionless: the event had no active subscriber, so
-- the dispatcher delivered it nowhere. Two seats of Platform & Reliability consume it — the Deploy
-- agent (eng_manager), whose work order a verified deploy is, and the Test-triage agent
-- (qa_manager), which re-runs the suites against a fresh deploy. Both subscriptions are declared as
-- components the way every other event subscription is.
--
--   node scripts/apply_sql.mjs scripts/sql/deploy_completed_has_subscribers.sql --apply --ddl
begin;
insert into public.event_subscription (agent_key, event_type, reason, active) values
  ('eng_manager', 'deploy.completed', 'Deploy agent (STAFF_ORG seat 41): a verified deploy is its work order — watch for errors, roll back if needed.', true),
  ('qa_manager',  'deploy.completed', 'Test-triage agent (STAFF_ORG seat 42): re-run the suites against a fresh deploy and route real breaks.', true)
on conflict (agent_key, event_type) do nothing;

insert into public.phase_c_component
  (component_id, component_type, source_path_or_db_object, entry_method, current_callers,
   external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor,
   accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id,
   idempotency_strategy, retry_policy, activation_state, classification, gap,
   repair_or_keep_action, evidence) values
  ('evsub:eng_manager@deploy.completed', 'event_subscription', 'public.event_subscription', 'event delivery', 'event_dispatch_15min', 'no', 'deploy.completed', true, 'agent eng_manager', 'system.event_dispatcher', 'engineering_manager', 'product_eng', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'event:event_id:consumer', 'outbox_retry_with_backoff', 'active', 'WIRE_TO_CANONICAL', '', 'route through the Phase C outbox so delivery state is explicit', 'event_subscription: agent_key=eng_manager event_type=deploy.completed active=true; reason="Deploy agent (STAFF_ORG seat 41): a verified deploy is its work order" (declared 3 Sep 2026 with the emitter in scripts/deploy_functions.mjs)'),
  ('evsub:qa_manager@deploy.completed',  'event_subscription', 'public.event_subscription', 'event delivery', 'event_dispatch_15min', 'no', 'deploy.completed', true, 'agent qa_manager',  'system.event_dispatcher', 'quality_and_release_director', 'product_eng', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'event:event_id:consumer', 'outbox_retry_with_backoff', 'active', 'WIRE_TO_CANONICAL', '', 'route through the Phase C outbox so delivery state is explicit', 'event_subscription: agent_key=qa_manager event_type=deploy.completed active=true; reason="Test-triage agent (STAFF_ORG seat 42): re-run the suites against a fresh deploy" (declared 3 Sep 2026 with the emitter in scripts/deploy_functions.mjs)')
on conflict (component_id) do nothing;

do $proof$
declare v_subs int; v_gaps int;
begin
  select count(*) into v_subs from public.event_subscription where event_type = 'deploy.completed' and active;
  select count(*) into v_gaps from public.fn_company_connectivity_register();
  if v_subs < 2 then raise exception 'deploy.completed has % active subscribers, expected 2', v_subs; end if;
  if v_gaps > 0 then raise exception 'the connectivity register still reports % gap(s): %', v_gaps,
    (select string_agg(gap_class || ' ' || subject, '; ') from public.fn_company_connectivity_register()); end if;
  raise notice 'proof: deploy.completed has % subscribers; connectivity register 0 gaps', v_subs;
end $proof$;
commit;
