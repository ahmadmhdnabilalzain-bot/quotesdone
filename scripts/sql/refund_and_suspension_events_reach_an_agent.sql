-- REFUND AND SUSPENSION EVENTS REACH AN AGENT AS WELL AS A WORKFLOW (4 Sep 2026, MASTER_PLAN §4.6).
--
-- Measured after the emitters landed: refund.requested and supplier.suspension_proposed each start
-- their workflow (refund, supplier_suspension — proven in an aborted transaction) but had NO
-- event_subscription, so the dispatcher delivered them to nobody and the register's class C
-- (event_emitted_no_subscriber) would have gone red on the first real occurrence. The plan's
-- contract names the consumers: Finance consumes refund.requested (STAFF_ORG seat 27, Refund-prep —
-- "assembles the full case for any refund so the founder can decide in one look"; the refund
-- workflow's step 2 actor is the same Billing & Reconciliation Specialist) and Trust & Safety
-- consumes supplier.suspension_proposed (seat 34, T&S lead — the supplier_suspension workflow's
-- step 1 actor and W17's accountable role). Both agents are active and hold an active canonical
-- role, so their subscription components are declared the same way every other live subscription's
-- is (every_live_entry_point_is_a_component.sql, step 2).
--
--   node scripts/apply_sql.mjs scripts/sql/refund_and_suspension_events_reach_an_agent.sql --apply --ddl
begin;

insert into public.event_subscription (agent_key, event_type, reason, active)
values
  ('billing_specialist', 'refund.requested',
   'Refund-prep (STAFF_ORG seat 27): assembles the case — fn_refund_state, the working-day ladder, supplier response — so the founder decides in one look. The refund itself stays founder-gated. (added 4 Sep 2026: the event started the refund workflow and reached no agent)', true),
  ('trust_safety_mgr', 'supplier.suspension_proposed',
   'T&S lead (STAFF_ORG seat 34): owns the suspension proposal through the approval chain; step 1 of supplier_suspension and W17 accountable role. (added 4 Sep 2026: the event started the workflow and reached no agent)', true)
on conflict do nothing;

update public.event_subscription set active = true
 where (agent_key, event_type) in (('billing_specialist','refund.requested'), ('trust_safety_mgr','supplier.suspension_proposed'))
   and not active;

insert into public.phase_c_component
  (component_id, component_type, source_path_or_db_object, entry_method, current_callers,
   external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor,
   accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id,
   idempotency_strategy, retry_policy, activation_state, classification, gap,
   repair_or_keep_action, evidence)
select 'evsub:' || s.agent_key || '@' || s.event_type, 'event_subscription', 'public.event_subscription',
       t.entry_method, t.current_callers, 'no', s.event_type, true, 'agent ' || s.agent_key, t.canonical_system_actor,
       r.role_id, r.primary_department_id, 'SYSTEM_SCOPE', '', t.authority_class, t.trace_policy_id,
       t.idempotency_strategy, t.retry_policy, 'active', 'WIRE_TO_CANONICAL', '',
       t.repair_or_keep_action,
       'event_subscription: agent_key=' || s.agent_key || ' event_type=' || s.event_type || ' active=true; reason="' || left(coalesce(s.reason, ''), 80) || '" (declared 4 Sep 2026)'
  from public.event_subscription s
  join public.org_agents a on a.agent_key = s.agent_key and a.active
  join public.org_role r on r.runtime_agent_key = s.agent_key and r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
  cross join (select * from public.phase_c_component where component_id = 'evsub:strategy_director@kpi.missed') t
 where s.active
   and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type);

update public.phase_c_component c
   set activation_state = 'active', classification = 'WIRE_TO_CANONICAL'
 where c.component_id in ('evsub:billing_specialist@refund.requested', 'evsub:trust_safety_mgr@supplier.suspension_proposed')
   and c.activation_state <> 'active';

do $proof$
declare v_subs int; v_comp int; v_gaps int;
begin
  select count(*) into v_subs from public.event_subscription s join public.org_agents a on a.agent_key = s.agent_key and a.active
   where s.active and (s.agent_key, s.event_type) in (('billing_specialist','refund.requested'), ('trust_safety_mgr','supplier.suspension_proposed'));
  select count(*) into v_comp from public.phase_c_component where activation_state = 'active'
     and component_id in ('evsub:billing_specialist@refund.requested', 'evsub:trust_safety_mgr@supplier.suspension_proposed');
  select count(*) into v_gaps from public.fn_company_connectivity_register();
  if v_subs <> 2 or v_comp <> 2 or v_gaps <> 0 then
    raise exception 'subs % of 2, components % of 2, register gaps %', v_subs, v_comp, v_gaps;
  end if;
  raise notice 'proof: 2 live subscriptions to active agents, 2 active components, register 0 gaps';
end $proof$;
commit;
