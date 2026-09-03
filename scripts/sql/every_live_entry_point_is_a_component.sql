-- EVERY LIVE ENTRY POINT IS A COMPONENT (3 Sep 2026).
--
-- The first run of scripts/checks/phase_c_components_are_owned.test.mjs — the production-side
-- check that replaced the crosswalk mirror — found what the mirror never could, because the mirror
-- compared the registry to a copy of the registry and never to the estate:
--   * 4 active cron jobs owned by nobody: phase_c_outbox_deliver_1min (278), company_self_knowledge_
--     sync_15min (292), it_security_live_posture_hourly (303), kb_embed_ops_knowledge (315);
--   * 10 active event subscriptions with no component — five moved to their successors by the
--     STAFF_ORG re-carve while their components kept the parked persona's id, five never declared;
--   * 9 subscription components whose subscription is gone (parked personas', and content.published
--     / rfq.classified subscriptions that no longer exist).
-- Each cron gets an owner from the department whose work it is; each live subscription gets a
-- component keyed to the agent that actually holds it; each dead subscription component is
-- recorded INACTIVE_HISTORICAL. Nothing is deleted.
--
--   node scripts/apply_sql.mjs scripts/sql/every_live_entry_point_is_a_component.sql --apply --ddl
begin;

-- 1. The four unowned cron jobs, declared from a live cron component as the template so every
--    kernel column (actor, trace policy, idempotency, retry) is the one the wrapped jobs carry.
insert into public.phase_c_component
  (component_id, component_type, source_path_or_db_object, entry_method, current_callers,
   external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor,
   accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id,
   idempotency_strategy, retry_policy, activation_state, classification, gap,
   repair_or_keep_action, evidence)
select 'cron:' || j.jobname, 'cron_job', 'cron.job/' || j.jobid, t.entry_method, t.current_callers,
       'no', j.schedule, true, t.current_actor, t.canonical_system_actor,
       o.role_id, r.primary_department_id, 'SYSTEM_SCOPE', '', t.authority_class, t.trace_policy_id,
       t.idempotency_strategy, t.retry_policy, 'active', 'WIRE_TO_CANONICAL', '',
       'declared 3 Sep 2026: an active job that no component owned (' || o.why || ')',
       'cron.job ' || j.jobid || ' ' || j.jobname || ' schedule ' || j.schedule || ' active=true; cron_registry: ' || coalesce(left(g.purpose, 120), '(none)')
  from cron.job j
  join (values
    ('phase_c_outbox_deliver_1min',       'it_operations_engineer', 'kernel infrastructure: the outbox drain belongs to reliability'),
    ('company_self_knowledge_sync_15min', 'knowledge_director',     'the company self-knowledge record is knowledge'),
    ('it_security_live_posture_hourly',   'cybersecurity_engineer', 'the live security posture record is security'),
    ('kb_embed_ops_knowledge',            'knowledge_director',     'embedding ops_knowledge is knowledge')
  ) o(jobname, role_id, why) on o.jobname = j.jobname
  join public.org_role r on r.role_id = o.role_id and r.status = 'active'
  left join public.cron_registry g on g.jobname = j.jobname
  cross join (select * from public.phase_c_component where component_id = 'cron:ads_autopilot_daily') t
 where j.active
   and not exists (select 1 from public.phase_c_component c where c.component_id = 'cron:' || j.jobname);

-- 2. Every active subscription with no component gets one, keyed to the agent that holds it, owned
--    by that agent's active canonical role, from a live subscription component as the template.
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
       'event_subscription: agent_key=' || s.agent_key || ' event_type=' || s.event_type || ' active=true; reason="' || left(coalesce(s.reason, ''), 80) || '" (declared 3 Sep 2026: the subscription was live and no component owned it)'
  from public.event_subscription s
  join public.org_agents a on a.agent_key = s.agent_key and a.active
  join public.org_role r on r.runtime_agent_key = s.agent_key and r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
  cross join (select * from public.phase_c_component where component_id = 'evsub:strategy_director@kpi.missed') t
 where s.active
   and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type);

-- 3. A subscription component whose subscription is gone or inactive is history, not a live door.
update public.phase_c_component c
   set activation_state = 'inactive', classification = 'INACTIVE_HISTORICAL',
       repair_or_keep_action = 'recorded inactive 3 Sep 2026: the subscription this component described no longer exists or is inactive (persona parked in the STAFF_ORG re-carve, or the subscription was retired); its successor, where one exists, is declared under its own id',
       evidence = coalesce(c.evidence, '') || ' | 3 Sep 2026: no active event_subscription row matches this id'
 where c.component_id like 'evsub:%' and c.activation_state = 'active'
   and not exists (select 1 from public.event_subscription s where s.active
                    and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id);

-- PROOF: the four properties the check asserts.
do $proof$
declare v_cron_missing int; v_cron_orphan int; v_sub_missing int; v_sub_orphan int; v_role int; v_dept int;
begin
  select count(*) into v_cron_missing from cron.job j where j.active and not exists (select 1 from public.phase_c_component c where c.component_id = 'cron:' || j.jobname);
  select count(*) into v_cron_orphan from public.phase_c_component c where c.component_id like 'cron:%' and not exists (select 1 from cron.job j where 'cron:' || j.jobname = c.component_id);
  select count(*) into v_sub_missing from public.event_subscription s where s.active and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type);
  select count(*) into v_sub_orphan from public.phase_c_component c where c.component_id like 'evsub:%' and c.activation_state = 'active' and not exists (select 1 from public.event_subscription s where s.active and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id);
  select count(*) into v_role from public.phase_c_component c left join public.org_role r on r.role_id = c.accountable_role_id where r.role_id is null or r.status <> 'active';
  select count(*) into v_dept from public.phase_c_component c join public.org_role r on r.role_id = c.accountable_role_id and r.status = 'active' left join public.org_departments d on d.dept_key = c.department_id where d.dept_key is null or not d.active or c.department_id is distinct from r.primary_department_id;
  if v_cron_missing + v_cron_orphan + v_sub_missing + v_sub_orphan + v_role + v_dept > 0 then
    raise exception 'entry points still unowned: cron missing %, cron orphan %, sub missing %, sub orphan %, bad role %, bad dept %',
      v_cron_missing, v_cron_orphan, v_sub_missing, v_sub_orphan, v_role, v_dept;
  end if;
  raise notice 'proof: every active cron and subscription is an owned component; 0 orphans';
end $proof$;
commit;
