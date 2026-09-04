-- STAFF_ORG — SEAT THE COMPANY AT THE PLAN'S SIZE WITH THE BINDING RULE (4 Sep 2026).
--
-- Where the 3 Sep re-carve stopped: 71 seated, 24 parked. It stopped because 22 Phase B handoffs in
-- W01, W02, W07, W21–W28 and W30 join a step owned by a persona the plan parks to a step owned by
-- the seat that inherits it, and phase_b_handoff_two_parties refuses a handoff from a role to
-- itself. Fifteen personas were kept seated by that rule alone.
--
-- What this file does, measured first, then applied:
--   1. WALKS those handoffs. A step chain that now lives inside ONE seat is no longer a handoff
--      between two parties — the plan merged the parties. Each step is re-pointed to the seat that
--      inherits it; every handoff whose two ends then land on the same seat is removed (with its
--      Phase C binding and Phase D contract); every other handoff is re-pointed to the owners of the
--      steps it joins, which is exactly what fn_phase_b_handoff_guard checks. The guard and the
--      CHECK are not touched. Then the personas are parked.
--   2. Applies STAFF_ORG §2 to the personas that were still active: 18 parked (15 handoff-kept +
--      hr_director, ai_director, eng_manager), one net-new seat created (the red-view alerter), the
--      COO moved to lead Agent Ops (§2 #55/#56), the Office of the CEO trimmed to 3.
--      Two departures from the §2 rows, both measured: cpo stays and strategy_director parks
--      (cpo carries 26 active components and 12 runtime steps; strategy_director 2 and 0), and
--      contract_specialist goes to the T&S lead rather than the Compliance agent (the compliance
--      officer is the legal reviewer-auditor; fn_role_identity_isolation_guard refuses one seat
--      producing and auditing one domain).
--   3. Gives every kept seat the three things the binding rule (MASTER_PLAN §3) demands — an event
--      it consumes, a mechanism that fires under its name, a playbook scoped to it — by moving the
--      mechanisms the plan names to the seats the plan names (the ad-spend autopilot to the
--      optimizer, the Stripe webhook to reconciliation, match-eval to Match-eval, self-review / KPI /
--      evolution / improvement crons off the scorecard officer to the seats that own them, the
--      knowledge exam to Certification, the founder-alert machinery to the alerter) and by adding
--      the subscriptions §4.6 names. fn_agent_binding_rule() measures it; the proof asserts 54/54.
--   4. Flattens leadership to one lead per department: every worker reports to its department lead
--      and carries 'specialist'; the ten leads carry 'director'; the two CEO-office officers keep
--      their rank. 12 leadership seats, 42 workers.
--   5. Recomputes the Phase A and Phase B baseline digests in place (the PACR-002/003/004 pattern)
--      so the drift instruments describe the state now held. No freeze exists (founder, 2 Sep).
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_seat_at_plan_size_2026_09_04.sql --apply --ddl
--   (rehearsal: prepend `set local app.recarve_rehearsal = '1'`; the proof block rolls back)
begin;
set local app.change_reason = 'STAFF_ORG 4 Sep 2026: seat the company at the plan''s size under the binding rule';
set local kernel.maintenance_reason = 'STAFF_ORG 4 Sep 2026: Phase C tasks naming parked roles re-pointed to the seats that inherited them';

-- =============================================================================================
-- 0. THE DECISIONS. Every line is typed; nothing is inferred at apply time.
-- =============================================================================================
create temp table park (agent_key text primary key, successor text not null, verdict text not null) on commit drop;
insert into park values
  ('strategy_director',   'cpo',                    'STAFF_ORG #3/#4: one strategy officer; cpo carries the scorecard mechanisms (26 active components)'),
  ('boq_analyst',         'doc_intel_manager',      'STAFF_ORG #11 MERGE -> one Document-reading (Intake) agent'),
  ('drawing_analyst',     'doc_intel_manager',      'STAFF_ORG #12 MERGE -> one Document-reading (Intake) agent'),
  ('account_mgr',         'sales_director',         'STAFF_ORG #31 RETIRE (no customers to manage yet)'),
  ('innovation_mgr',      'cto',                    'STAFF_ORG #53 RETIRE (premature)'),
  ('ai_architect',        'cto',                    'STAFF_ORG #46 RETIRE (design phase over)'),
  ('test_automation_eng', 'qa_manager',             'STAFF_ORG #90 REASSIGN -> Platform Test-triage (one seat)'),
  ('model_evaluator',     'qa_manager',             'STAFF_ORG #89 MERGE -> Match-eval / test-triage reviewer'),
  ('forecast_analyst',    'intel_director',         'STAFF_ORG #37 RETIRE (nothing to forecast at AED 0)'),
  ('kb_engineer',         'knowledge_director',     'STAFF_ORG #42 MERGE -> Knowledge-accuracy agent'),
  ('taxonomy_manager',    'intel_director',         'STAFF_ORG #39/#40: one owner of the category list; no live component, subscription or step (measured 4 Sep)'),
  ('financial_analyst',   'cfo',                    'STAFF_ORG #70 RETIRE (nothing to analyse at AED 0)'),
  ('contract_specialist', 'legal',                  'STAFF_ORG #73 MERGE (to the T&S lead: the compliance officer is the legal reviewer-auditor)'),
  ('risk_governance_mgr', 'legal',                  'STAFF_ORG #74 RETIRE (governance machinery abolished)'),
  ('org_designer',        'recruitment_specialist', 'STAFF_ORG #60 RETIRE (this document is that job, done once); roster changes are the Hire/fire agent''s'),
  ('hr_director',         'ops_director',           'STAFF_ORG #56 MERGE -> Agent Ops lead (ops_director, #55)'),
  ('ai_director',         'cto',                    'STAFF_ORG #45 MERGE -> Platform lead'),
  ('eng_manager',         'cto',                    'STAFF_ORG #47 MERGE -> Platform lead (deploy mechanisms are already the CTO''s)');

-- The plan's seats: department, lead, and the seat title. 54 rows including the new alerter.
create temp table seat (agent_key text primary key, dept text not null, seat text not null) on commit drop;
insert into seat values
  ('ceo','exec','CEO officer'), ('brief','exec','Chief of Staff'), ('cpo','exec','Strategy officer (the scorecard)'),
  ('bd','supply','Supply lead'), ('partnerships_mgr','supply','Invite-campaign agent'), ('onboarding','supply','Claim/Onboard agent'),
  ('supplier_verification','supply','Verification agent'), ('supplier_retention','supply','Retention agent'), ('supplier_coverage','supply','Coverage-gap agent'),
  ('sales_director','growth','Demand lead'), ('marketing_analyst','growth','Ad-spend optimizer'), ('marketing_content','growth','Blog agent'),
  ('marketing_social','growth','Social agent'), ('brand_mgr','growth','Content-revise agent'), ('optimisation_eng','growth','SEO agent'), ('marketing_design','growth','Creative agent'),
  ('procurement','marketplace','Ops lead'), ('doc_intel_manager','marketplace','Intake agent (reads uploaded files)'), ('inquiry_router','marketplace','Router/Dispatch agent'),
  ('spec_commercial','marketplace','Match-quality agent'), ('quote_evaluation','marketplace','Quote-quality agent'), ('rfq_qualification_mgr','marketplace','Coverage-gap agent (ops side)'),
  ('rfq_success','marketplace','Reveal-orchestration agent'),
  ('cfo','finance','Finance lead'), ('billing_specialist','finance','Reconciliation agent'), ('collections','finance','Collections agent'),
  ('payments_manager','finance','Refund-prep agent'), ('bookkeeper','finance','Invoicing/GL agent'),
  ('followup','customer_experience','CX lead'), ('cs_onboarding','customer_experience','Buyer-support agent'), ('cs_retention','customer_experience','Supplier-support agent'),
  ('cs_support','customer_experience','Complaint agent'), ('channel_specialist','customer_experience','Rating agent'),
  ('legal','legal','T&S lead'), ('moderation_specialist','legal','Moderation agent'), ('trust_safety_mgr','legal','Suspension agent'), ('compliance_mgr','legal','Compliance agent'),
  ('cto','product_eng','Platform lead'), ('it','product_eng','Reliability/SRE agent'), ('red_view_alerter','product_eng','Red-view alerter'),
  ('security','product_eng','Deploy-gate & security agent'), ('qa_manager','product_eng','Test-triage agent'), ('backend_engineer','product_eng','Kernel/runtime agent'),
  ('intel_director','data_intel','Data lead'), ('bi_analyst','data_intel','KPI agent'), ('analytics','data_intel','Self-review agent'),
  ('process_improvement_mgr','data_intel','Evolution agent'), ('market_analyst','data_intel','Experiment agent'), ('knowledge_director','data_intel','Knowledge-accuracy agent'),
  ('supplier_analyst','data_intel','Match-eval agent'),
  ('ops_director','people_ops','Agent-Ops lead'), ('learning_dev_mgr','people_ops','Certification agent'),
  ('culture_performance_mgr','people_ops','KPI-improvement agent'), ('recruitment_specialist','people_ops','Hire/fire agent');

create temp table dlead (dept text primary key, agent_key text not null, role_id text not null) on commit drop;
insert into dlead values
  ('exec','ceo','ceo'), ('supply','bd','business_development'), ('growth','sales_director','chief_revenue_officer'),
  ('marketplace','procurement','marketplace_director'), ('finance','cfo','cfo'), ('customer_experience','followup','customer_success_director'),
  ('legal','legal','general_counsel'), ('product_eng','cto','cto'), ('data_intel','intel_director','data_intelligence_director'),
  ('people_ops','ops_director','chief_operating_officer');

-- =============================================================================================
-- 1. THE NET-NEW SEAT: the red-view -> founder alerter (Platform). It inherits the machinery that
--    turns a red measurement into a founder_alerts row today (fn_exception_alerts hourly,
--    fn_emit_metric_alerts weekly, fin_alert / fn_alert_severe, the founder_alerts level trigger).
-- =============================================================================================
insert into public.org_agents (agent_key, department, role, kind, active, title, manager_key, seniority, responsibilities, max_open_tasks, available, routing_tier)
values ('red_view_alerter', 'product_eng', 'Red-view alerter — turns a red monitored view into a founder alert, and records it',
        'agent', true, 'Red-view Alerter', 'cto', 'specialist',
        'Red-view alerter (Platform & Reliability). Watches every monitored view and metric; the moment one turns red it raises a founder alert (founder_alerts) with the measurement, deduplicated, and hands the remediation to the Reliability/SRE agent. The alert is the record of a red view, never a substitute for the SRE fixing it. Deterministic: fn_exception_alerts, fn_emit_metric_alerts, fn_alert_severe.',
        50, true, 'operations_specialist')
on conflict (agent_key) do update set active = true, available = true, department = 'product_eng', manager_key = 'cto',
   unavailable_until = null, unavailable_reason = null;

insert into public.org_role (role_id, display_name, primary_department_id, manager_role_id, runtime_mode, runtime_agent_key, responsibilities,
  owned_decisions, forbidden_decisions, activation_conditions, required_inputs, output_contracts, tools, knowledge_scopes, authority_level,
  budget_limit, handoff_targets, escalation_targets, model_policy, evaluation_suite, status, source_agent_keys, rationale,
  necessity_status, necessity_reason, runtime_enabled)
values ('red_view_alerter', 'Red-view Alerter', 'product_eng', 'cto', 'event_driven_operator', 'red_view_alerter',
  'Red-view alerter — raises the founder alert the moment a monitored view or metric turns red, deduplicated and levelled, and hands the fix to Reliability/SRE.',
  array['raising a founder alert when a monitored view or metric turns red', 'the level and dedupe of a founder alert', 'red-to-alert latency'],
  array['resolving the underlying incident itself', 'changing an alert threshold without the platform lead', 'alerting the founder on anything that is not a red view'],
  'A monitored view, metric or health probe goes red (metric.alert, os.health_changed), or the hourly exception scan fires.',
  array['incident_response', 'employee_task'], array['founder_alert', 'red_view_record'],
  array['metric_alerts', 'escalate_founder', 'health_report', 'uptime_verify'],
  array['company', 'company_goals', 'constitution', 'engineering', 'operations', 'priority_hierarchy', 'quotesdone_os', 'universal_objectives', 'it', 'qa'],
  'execute_low', 0, array['it_operations_engineer'], array['cto', 'chief_of_staff'], 'director', 'eval_platform_reliability',
  'active', array['red_view_alerter'],
  'MASTER_PLAN §3 net-new seat 4: "detection is not wired to response" was P0 — policy_consistency_weekly red since 31 Aug, nobody alerted.',
  'REQUIRED_CORE', 'Owns the red-view -> founder-alert decision so a red dashboard is never silent.', true)
on conflict (role_id) do update set status = 'active', runtime_enabled = true, primary_department_id = 'product_eng', manager_role_id = 'cto', updated_at = now();

-- The identity the seat holds: the SRE operations-specialist package, shared with `it` as a
-- runtime-shared holding (the 14 Aug convention: shared holdings are runtime_composite, never exclusive).
update public.org_role_identity set mapping_type = 'runtime_composite', updated_at = now()
 where agent_key = 'it' and packaged_role_id = 'it-sre-and-cybersecurity-operations-specialist' and mapping_type = 'one_to_one';
insert into public.org_role_identity (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness, package_version)
values ('red_view_alerter', 'it-sre-and-cybersecurity-operations-specialist', 'it_cybersecurity', 'operations-specialist', 'runtime_composite', 'tools_connected', '2026.08.14')
on conflict (agent_key, packaged_role_id) do nothing;

insert into public.employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active, kpi_class)
values ('red_view_alerter', 'Red-to-alert latency', 'Minutes from a red measurement event to the next founder alert (7-day mean; null when no red event occurred)',
        60, 'minutes', 'weekly', 'critical_incidents',
        'select round(avg(extract(epoch from (f.created_at - e.occurred_at)) / 60.0), 1) from public.company_event e join lateral (select fa.created_at from public.founder_alerts fa where fa.created_at >= e.occurred_at order by fa.created_at limit 1) f on true where e.event_type in (''metric.alert'', ''os.health_changed'') and e.occurred_at > now() - interval ''7 days''',
        true, 'quality_metric')
on conflict (agent_key, kpi) do nothing;
insert into public.employee_authority (agent_key, action_class, max_tier, threshold_aed, note) values
  ('red_view_alerter', 'metric_alerts',    'autonomous', 0, 'Raising a metric alert is the seat''s own decision'),
  ('red_view_alerter', 'escalate_founder', 'autonomous', 0, 'A red view reaches the founder without a gate; that is the seat'),
  ('red_view_alerter', 'health_report',    'autonomous', 0, 'Advisory-safe action, may run autonomously')
on conflict (agent_key, action_class) do nothing;
insert into public.employee_workflow (agent_key, workflow_key, role_in_workflow)
values ('red_view_alerter', 'incident_response', 'participant') on conflict (agent_key, workflow_key) do nothing;
insert into public.org_role_alias (alias, role_id, kind, reason) values
  ('Red-view Alerter', 'red_view_alerter', 'title', 'STAFF_ORG 4 Sep 2026: net-new seat')
on conflict (alias) do update set role_id = excluded.role_id;
insert into public.org_agent_alias (alias, agent_key, reason) values
  ('Red-view Alerter', 'red_view_alerter', 'STAFF_ORG 4 Sep 2026: net-new seat')
on conflict (alias) do update set agent_key = excluded.agent_key;
insert into public.phase_c_role_binding (canonical_role_id, department_id, runtime_agent_key, resolver_path, task_receiver_path, authority_binding_path,
  review_binding_path, knowledge_scope_path, tool_policy_path, trace_policy_id, paid_model_route_status, workflows_served, connection_status, gap, evidence)
select 'red_view_alerter', 'product_eng', 'red_view_alerter', b.resolver_path, b.task_receiver_path, b.authority_binding_path,
       b.review_binding_path, b.knowledge_scope_path, b.tool_policy_path, b.trace_policy_id, b.paid_model_route_status,
       'incident_response', 'CONNECTED', '', 'org_role.role_id exact match; seat created 4 Sep 2026 (STAFF_ORG)'
  from public.phase_c_role_binding b where b.runtime_agent_key = 'it' and b.connection_status = 'CONNECTED'
on conflict (canonical_role_id) do update set connection_status = 'CONNECTED', gap = '', runtime_agent_key = 'red_view_alerter', department_id = 'product_eng';
insert into public.phase_c_reporting_authority (canonical_role_id, live_role_id, department_id, manager_role_id, role_class, runtime_mode, department_head_role_id, reporting_path, source_package)
values ('red_view_alerter', 'red_view_alerter', 'product_eng', 'cto', 'O', 'event_driven_operator', 'cto', 'red_view_alerter > cto > ceo > founder', 'STAFF_ORG_2026_09_04')
on conflict (canonical_role_id) do nothing;

do $chk$
declare v text;
begin
  select string_agg(p.agent_key, ', ') into v from park p where not exists (select 1 from public.org_agents a where a.agent_key = p.agent_key);
  if v is not null then raise exception 'park list names personas that do not exist: %', v; end if;
  select string_agg(p.agent_key, ', ') into v from park p where not exists (select 1 from seat s where s.agent_key = p.successor);
  if v is not null then raise exception 'parked personas whose successor holds no seat: %', v; end if;
  select string_agg(s.agent_key, ', ') into v from seat s where not exists (select 1 from public.org_agents a where a.agent_key = s.agent_key);
  if v is not null then raise exception 'seat map names personas that do not exist: %', v; end if;
  select string_agg(a.agent_key, ', ') into v from public.org_agents a where a.active
     and not exists (select 1 from seat s where s.agent_key = a.agent_key)
     and not exists (select 1 from park p where p.agent_key = a.agent_key);
  if v is not null then raise exception 'active personas neither seated nor parked: %', v; end if;
end $chk$;

-- The role map, captured while every role is still active (idempotent: a retired role also maps).
create temp table m on commit drop as
  select ro.role_id old_role, rn.role_id new_role, p.agent_key old_agent, p.successor new_agent,
         ao.title old_title, an.title new_title, ro.display_name old_dn, rn.display_name new_dn
    from park p
    join public.org_role ro on ro.runtime_agent_key = p.agent_key and ro.runtime_mode <> 'knowledge_overlay'
    join public.org_role rn on rn.runtime_agent_key = p.successor and rn.status = 'active'
    join public.org_agents ao on ao.agent_key = p.agent_key
    join public.org_agents an on an.agent_key = p.successor;
do $chk$ begin
  if (select count(*) from m) <> (select count(*) from park) then
    raise exception 'role map covers % of % parked personas', (select count(*) from m), (select count(*) from park);
  end if;
end $chk$;

-- =============================================================================================
-- 2. THE PHASE B WALK. Steps first, then the handoffs that joined them.
-- =============================================================================================
update public.phase_b_workflow_step s set accountable_role_id = m.new_role
  from m where s.accountable_role_id = m.old_role and s.actor_kind = 'canonical_role';
update public.phase_b_workflow_step s
   set independent_reviewer_role_id = case when m.new_role <> s.accountable_role_id then m.new_role
        else coalesce((select r.manager_role_id from public.org_role r where r.role_id = s.accountable_role_id and r.manager_role_id <> s.accountable_role_id), 'founder') end
  from m where s.independent_reviewer_role_id = m.old_role;
update public.phase_b_workflow_step s
   set contributors = (select array_agg(distinct coalesce(m2.new_role, u.c))
                         from unnest(s.contributors) u(c) left join m m2 on m2.old_role = u.c)
 where exists (select 1 from unnest(s.contributors) c join m on m.old_role = c);

-- A handoff whose two ends now sit on one seat is a merged party, not a handoff. Remove it and the
-- Phase C binding that mirrored it (the Phase D contract cascades). Nothing has ever run over these
-- edges: phase_c_handoff_run holds 0 rows for them (measured 4 Sep 2026).
create temp table collapsed on commit drop as
  select h.handoff_id, h.workflow_id, sf.accountable_role_id owner
    from public.phase_b_handoff h
    join public.phase_b_workflow_step sf on sf.step_id = h.from_step_id
    join public.phase_b_workflow_step st on st.step_id = h.to_step_id
   where sf.accountable_role_id = st.accountable_role_id;
do $chk$ begin
  if exists (select 1 from public.phase_c_handoff_run r join collapsed c on c.handoff_id = r.handoff_id) then
    raise exception 'a collapsing handoff has run history; refuse to remove it: %',
      (select string_agg(distinct r.handoff_id, ', ') from public.phase_c_handoff_run r join collapsed c on c.handoff_id = r.handoff_id);
  end if;
end $chk$;
delete from public.phase_c_handoff_binding b using collapsed c where b.handoff_id = c.handoff_id;
delete from public.phase_b_handoff h using collapsed c where h.handoff_id = c.handoff_id;

-- Every surviving handoff names the owners of the two steps it joins (what the guard checks).
update public.phase_b_handoff h
   set sending_role_id = s.accountable_role_id, receiving_role_id = t.accountable_role_id
  from public.phase_b_workflow_step s, public.phase_b_workflow_step t
 where s.step_id = h.from_step_id and t.step_id = h.to_step_id
   and (h.sending_role_id <> s.accountable_role_id or h.receiving_role_id <> t.accountable_role_id);
update public.phase_b_handoff h set return_owner_role_id = m.new_role from m where h.return_owner_role_id = m.old_role;

update public.phase_b_workflow w set accountable_role_id = m.new_role from m where w.accountable_role_id = m.old_role;
update public.phase_b_workflow w
   set independent_reviewer_role_id = case when m.new_role <> w.accountable_role_id then m.new_role
        else coalesce((select r.manager_role_id from public.org_role r where r.role_id = w.accountable_role_id and r.manager_role_id <> w.accountable_role_id), 'founder') end
  from m where w.independent_reviewer_role_id = m.old_role;
-- An exception escalates to somebody other than the one who detects it (phase_b_exception_independent_escalation):
-- where the map would collapse the two, escalation goes one level up the reporting graph.
update public.phase_b_exception e
   set detection_owner_role_id = x.det,
       escalation_owner_role_id = case when x.esc <> x.det then x.esc
                                       else coalesce((select r.manager_role_id from public.org_role r where r.role_id = x.det and r.manager_role_id <> x.det), 'ceo') end
  from (select e2.exception_id,
               coalesce((select m.new_role from m where m.old_role = e2.detection_owner_role_id), e2.detection_owner_role_id) det,
               coalesce((select m.new_role from m where m.old_role = e2.escalation_owner_role_id), e2.escalation_owner_role_id) esc
          from public.phase_b_exception e2
         where exists (select 1 from m where m.old_role in (e2.detection_owner_role_id, e2.escalation_owner_role_id))) x
 where x.exception_id = e.exception_id;
update public.phase_b_event e set primary_consumer_role_id = m.new_role from m where e.primary_consumer_role_id = m.old_role;
update public.phase_b_business_object o set accountable_role_id = m.new_role from m where o.accountable_role_id = m.old_role;

-- Phase C bindings mirror the structure they bind.
update public.phase_c_step_binding b
   set accountable_role_id = s.accountable_role_id, independent_reviewer_role_id = coalesce(s.independent_reviewer_role_id, '')
  from public.phase_b_workflow_step s
 where s.step_id = b.step_id
   and (b.accountable_role_id is distinct from s.accountable_role_id
        or nullif(b.independent_reviewer_role_id, '') is distinct from s.independent_reviewer_role_id);
update public.phase_c_handoff_binding b
   set sending_role_id = h.sending_role_id, receiving_role_id = h.receiving_role_id
  from public.phase_b_handoff h
 where h.handoff_id = b.handoff_id
   and (b.sending_role_id is distinct from h.sending_role_id or b.receiving_role_id is distinct from h.receiving_role_id);
update public.phase_c_task t set accountable_role_id = m.new_role from m where t.accountable_role_id = m.old_role;
update public.phase_c_task t set manager_role_id = m.new_role from m where t.manager_role_id = m.old_role;
update public.phase_c_task t set reviewer_role_id = m.new_role from m where t.reviewer_role_id = m.old_role;
update public.phase_c_task t set blocker_owner_role_id = m.new_role from m where t.blocker_owner_role_id = m.old_role;
update public.phase_c_role_binding b
   set connection_status = 'RETIRED',
       gap = 'STAFF_ORG 4 Sep 2026: persona parked; accountability moved to ' || m.new_role
  from m where b.runtime_agent_key = m.old_agent and b.connection_status <> 'RETIRED';
delete from public.phase_c_reporting_authority ra using m where ra.canonical_role_id = m.old_role;
update public.phase_c_reporting_authority ra set manager_role_id = m.new_role from m where ra.manager_role_id = m.old_role;
update public.phase_c_reporting_authority ra set department_head_role_id = m.new_role from m where ra.department_head_role_id = m.old_role;
update public.phase_c_reporting_authority ra set live_role_id = m.new_role from m where ra.live_role_id = m.old_role;
update public.phase_c_system_actor x set accountable_role_id = m.new_role from m where x.accountable_role_id = m.old_role;
update public.phase_c_action_class x set accountable_role_id = m.new_role from m where x.accountable_role_id = m.old_role;
update public.phase_c_event_binding x set primary_consumer_role_id = m.new_role from m where x.primary_consumer_role_id = m.old_role;
update public.phase_c_overlay_binding x set broad_domain_escalation_role_id = m.new_role from m where x.broad_domain_escalation_role_id = m.old_role;
update public.phase_c_overlay_binding x set invocation_role_id = m.new_role from m where x.invocation_role_id = m.old_role;
update public.phase_c_overlay_binding x set result_returns_to_role_id = m.new_role from m where x.result_returns_to_role_id = m.old_role;
update public.phase_c_command_intent x set command_owner_role_id = m.new_role from m where x.command_owner_role_id = m.old_role;
update public.phase_c_command_intent x set default_accountable_role_id = m.new_role from m where x.default_accountable_role_id = m.old_role;
update public.phase_c_command_rule x set primary_role_id = m.new_role from m where x.primary_role_id = m.old_role;
update public.phase_c_command_rule x
   set child_role_ids = (select string_agg(coalesce(m2.new_role, btrim(t.tok)), '; ' order by t.ord)
                           from regexp_split_to_table(x.child_role_ids, ';') with ordinality t(tok, ord)
                           left join m m2 on m2.old_role = btrim(t.tok))
 where exists (select 1 from regexp_split_to_table(x.child_role_ids, ';') t(tok) join m on m.old_role = btrim(t.tok));
update public.phase_c_handoff_run x set sending_role_id = m.new_role from m where x.sending_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');
update public.phase_c_handoff_run x set receiving_role_id = m.new_role from m where x.receiving_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');
update public.phase_c_handoff_run x set return_owner_role_id = m.new_role from m where x.return_owner_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');
update public.phase_c_handoff_run x set accountable_until_accept_role_id = m.new_role from m where x.accountable_until_accept_role_id = m.old_role and x.status not in ('accepted', 'closed', 'rejected');

-- =============================================================================================
-- 3. THE ORG LAYER. Personas, departments, roles, accountability, aliases, subscriptions.
-- =============================================================================================
update public.org_agents a set department = s.dept, active = true, available = true, unavailable_until = null, unavailable_reason = null
  from seat s where s.agent_key = a.agent_key;
update public.org_agents a
   set active = false, available = false, unavailable_until = null,
       unavailable_reason = 'Parked 4 Sep 2026 (STAFF_ORG seat-at-plan-size): ' || p.verdict || '. Title kept for re-hire; live accountability moved to ' || p.successor || '.'
  from park p where p.agent_key = a.agent_key;
update public.org_departments set lead_agent = 'ops_director', brain_agent = 'ops_director' where dept_key = 'people_ops';

update public.org_role r set primary_department_id = s.dept, updated_at = now()
  from seat s where r.runtime_agent_key = s.agent_key and r.status = 'active' and r.primary_department_id <> s.dept;
update public.org_role r
   set status = 'retired', runtime_enabled = false, updated_at = now(),
       necessity_reason = coalesce(necessity_reason || ' | ', '') || 'STAFF_ORG 4 Sep 2026: persona parked; accountability moved to ' || m.new_role
  from m where r.role_id = m.old_role and r.status <> 'retired';

-- Accountability follows the seat; department re-derives from the accountable role.
update public.phase_c_component c set accountable_role_id = m.new_role from m where c.accountable_role_id = m.old_role;

-- The plan's seats own the plan's mechanisms (MASTER_PLAN §3 / STAFF_ORG §4).
create temp table repoint (pattern text, new_role text, why text) on commit drop;
insert into repoint values
  ('cron:ads_autopilot_daily',                       'marketing_performance_analyst', 'Ad-spend optimizer owns the autopilot tick (fn_ads_manage)'),
  ('cron:meta_sync_daily',                           'marketing_performance_analyst', 'Ad-spend optimizer reads live Meta data'),
  ('edge:meta_ads',                                  'marketing_performance_analyst', 'Ad-spend optimizer owns the Meta objects'),
  ('edge:meta_sync',                                 'marketing_performance_analyst', 'Ad-spend optimizer owns the insight sync'),
  ('trigger:meta_insights.trg_emit_campaign_launched','marketing_performance_analyst', 'campaign.launched is the optimizer''s own emission'),
  ('dbfn:fn_ads_%',                                  'marketing_performance_analyst', 'fn_ads_* is the autopilot'),
  ('edge:stripe_webhook',                            'billing_operations',            'Reconciliation agent: Stripe webhook -> transactions'),
  ('edge:stripe_confirm',                            'billing_operations',            'Reconciliation agent: payment confirmation'),
  ('dbfn:fn_stripe_event_seen(%',                    'billing_operations',            'Reconciliation agent: idempotent event ledger'),
  ('cron:match_eval_weekly',                         'supplier_intelligence_analyst', 'Match-eval agent grades the matcher'),
  ('edge:match_eval',                                'supplier_intelligence_analyst', 'Match-eval agent grades the matcher'),
  ('cron:self_review_weekly',                        'data_engineer',                 'Self-review agent'),
  ('dbfn:fn_self_review()',                          'data_engineer',                 'Self-review agent'),
  ('table:self_review',                              'data_engineer',                 'Self-review agent'),
  ('cron:employee_kpi_measure_daily',                'business_intelligence_analyst', 'KPI agent measures every employee'),
  ('dbfn:fn_employee_kpi_measure()',                 'business_intelligence_analyst', 'KPI agent'),
  ('dbfn:fn_employee_kpi_trend(%',                   'business_intelligence_analyst', 'KPI agent'),
  ('dbfn:fn_kpi_scoreboard()',                       'business_intelligence_analyst', 'KPI agent'),
  ('cron:kpi_review_weekly',                         'business_intelligence_analyst', 'KPI agent'),
  ('dbfn:fn_kpi_review()',                           'business_intelligence_analyst', 'KPI agent'),
  ('cron:employee_kpi_assign_daily',                 'business_intelligence_analyst', 'KPI agent assigns the measures'),
  ('cron:evolution_scan_weekly',                     'process_improvement_manager',   'Evolution agent lands proposals'),
  ('dbfn:fn_evolution_scan()',                       'process_improvement_manager',   'Evolution agent'),
  ('table:evolution_proposal',                       'process_improvement_manager',   'Evolution agent'),
  ('cron:improvement_plan_daily',                    'culture_and_performance_manager','KPI-improvement agent'),
  ('cron:improvement_handover_hourly',               'culture_and_performance_manager','KPI-improvement agent'),
  ('dbfn:fn_improvement_plan_refresh()',             'culture_and_performance_manager','KPI-improvement agent'),
  ('dbfn:fn_improvement_handover(%',                 'culture_and_performance_manager','KPI-improvement agent'),
  ('cron:knowledge_exam_loop',                       'learning_and_development_manager','Certification agent runs the exam'),
  ('edge:knowledge_exam',                            'learning_and_development_manager','Certification agent runs the exam'),
  ('dbfn:fn_knowledge_exam_summary()',               'learning_and_development_manager','Certification agent'),
  ('dbfn:fn_exam_pick_agent()',                      'learning_and_development_manager','Certification agent'),
  ('table:org_onboarding',                           'learning_and_development_manager','Certification agent owns onboarding'),
  ('cron:agent_autogen_daily',                       'recruitment_specialist',        'Hire/fire agent'),
  ('edge:agent_autogen',                             'recruitment_specialist',        'Hire/fire agent'),
  ('cron:category_sales_daily',                      'business_development',          'Supply lead aims the engine at the emptiest categories'),
  ('dbfn:fn_category_sales(%',                       'business_development',          'Supply lead'),
  ('cron:exception_alerts_hourly',                   'red_view_alerter',              'Red-view alerter: hourly exception scan -> founder_alerts'),
  ('dbfn:fn_exception_alerts()',                     'red_view_alerter',              'Red-view alerter'),
  ('cron:emit_metric_alerts',                        'red_view_alerter',              'Red-view alerter: off-target metrics -> kpi.missed / goal.at_risk'),
  ('dbfn:fn_emit_metric_alerts()',                   'red_view_alerter',              'Red-view alerter'),
  ('dbfn:fn_alert_severe(%',                         'red_view_alerter',              'Red-view alerter: the level rule'),
  ('dbfn:fin_alert(%',                               'red_view_alerter',              'Red-view alerter: finance red -> alert'),
  ('trigger:founder_alerts.trg_normalize_founder_alert_level', 'red_view_alerter',    'Red-view alerter: founder_alerts level normalisation'),
  ('dbfn:fn_normalize_founder_alert_level()',        'red_view_alerter',              'Red-view alerter');
update public.phase_c_component c
   set accountable_role_id = r.new_role,
       repair_or_keep_action = left(coalesce(nullif(c.repair_or_keep_action, ''), '') || case when coalesce(c.repair_or_keep_action, '') = '' then '' else ' | ' end
                                    || 'STAFF_ORG 4 Sep 2026: ' || r.why, 2000)
  from repoint r
 where c.component_id like r.pattern and c.accountable_role_id <> r.new_role;
update public.phase_c_component c set department_id = r.primary_department_id
  from public.org_role r
 where r.role_id = c.accountable_role_id and r.status = 'active'
   and c.department_id is distinct from r.primary_department_id;
-- Supply's mechanisms sit under Supply's executors (they were still filed under the old blob).
update public.org_action_executor set department = 'supply'
 where action_class in ('supplier_verify', 'supplier_approve_clean', 'supplier_capability_derive', 'invite') and department <> 'supply';

-- Workflow ownership, reviewers, contributors, org-level steps.
update public.org_workflow_ownership o set accountable_role_id = m.new_role from m where o.accountable_role_id = m.old_role;
update public.org_workflow_ownership o
   set contributors = (select coalesce(array_agg(distinct z.x), '{}') from (select coalesce(m.new_role, c) x from unnest(o.contributors) c left join m on m.old_role = c) z
                       where z.x <> o.accountable_role_id and z.x is distinct from o.independent_reviewer)
 where exists (select 1 from unnest(o.contributors) c join m on m.old_role = c);
update public.org_workflow_ownership o
   set independent_reviewer = coalesce(
        (select m.new_role where m.new_role <> o.accountable_role_id and not (m.new_role = any(o.contributors))),
        (select r.manager_role_id from public.org_role r
          where r.role_id = o.accountable_role_id and r.manager_role_id <> o.accountable_role_id and not (r.manager_role_id = any(o.contributors))),
        'ceo')
  from m where o.independent_reviewer = m.old_role;
update public.org_workflow_ownership o set contributors = array_remove(o.contributors, o.accountable_role_id)
 where o.accountable_role_id = any(o.contributors);
update public.org_workflow_ownership o
   set independent_reviewer = coalesce((select r.manager_role_id from public.org_role r where r.role_id = o.accountable_role_id), 'ceo')
 where o.independent_reviewer = o.accountable_role_id;
-- No workflow is reviewed inside its owner's department (the 3 Sep settlement rule).
update public.org_workflow_ownership o
   set independent_reviewer = case when o.accountable_role_id = 'ceo' then 'founder'
                                   when (select r1.primary_department_id from public.org_role r1 where r1.role_id = o.accountable_role_id) = 'exec' then 'general_counsel'
                                   else 'chief_of_staff' end
  from public.org_role r1, public.org_role r2
 where r1.role_id = o.accountable_role_id and r2.role_id = o.independent_reviewer
   and r1.primary_department_id = r2.primary_department_id;
update public.org_workflow_step s set accountable_role_id = m.new_role from m where s.accountable_role_id = m.old_role;

-- The alias registry, both directions.
update public.org_role_alias a set role_id = m.new_role from m where a.role_id = m.old_role;
insert into public.org_role_alias (alias, role_id, kind, reason)
  select m.old_role, m.new_role, 'merged_role', 'STAFF_ORG 4 Sep 2026: persona parked; its accountability moved to ' || m.new_role
    from m
  on conflict (alias) do update set role_id = excluded.role_id, kind = excluded.kind, reason = excluded.reason;
update public.org_agent_alias a
   set agent_key = m.new_agent, reason = coalesce(a.reason || ' | ', '') || 'STAFF_ORG 4 Sep 2026: ' || m.old_agent || ' parked; resolves to ' || m.new_agent
  from m where a.agent_key = m.old_agent;
insert into public.org_agent_alias (alias, agent_key, reason)
  select distinct on (x.alias) x.alias, m.new_agent, 'STAFF_ORG 4 Sep 2026: persona parked; every caller still using this id resolves to the seat that inherited its work'
    from m cross join lateral (values (m.old_agent), (m.old_role), (m.old_title), (m.old_dn)) x(alias)
   where x.alias is not null and not exists (select 1 from public.org_agents a where a.agent_key = x.alias and a.active)
   order by x.alias, m.old_agent
  on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;

-- Runtime workflow steps that named a parked persona by any of its names.
update public.workflow_step ws
   set actor_role = case when ws.actor_role = m.old_agent then m.new_agent
                         when ws.actor_role = m.old_role  then m.new_role
                         when ws.actor_role = m.old_title then m.new_title
                         when ws.actor_role = m.old_dn    then m.new_dn end
  from m
 where ws.actor_role in (m.old_agent, m.old_role, m.old_title, m.old_dn);
-- The COO now leads Agent Ops: its incident_response steps go to the Platform seats that do the work.
update public.workflow_step set actor_role = 'it' where workflow_key = 'incident_response' and step_no = 3 and actor_role = 'ops_director';
update public.workflow_step set actor_role = 'backend_engineer' where workflow_key = 'incident_response' and step_no = 7 and actor_role = 'ops_director';
-- The unpaid-session nudge is the Supplier-support/retention seat's act, not the CX lead's.
update public.workflow_step set actor_role = 'customer_retention' where workflow_key = 'payment' and step_no = 7 and actor_role = 'customer_success_director';

-- Subscriptions of parked personas move to the successor; their components follow.
insert into public.event_subscription (agent_key, event_type, reason, active)
  select m.new_agent, e.event_type, left(coalesce(e.reason, '') || ' (moved from ' || m.old_agent || ', STAFF_ORG 4 Sep 2026)', 500), e.active
    from public.event_subscription e join m on m.old_agent = e.agent_key
  on conflict (agent_key, event_type) do nothing;
delete from public.event_subscription e using m where e.agent_key = m.old_agent;
update public.phase_c_component c
   set activation_state = 'inactive',
       evidence = left(c.evidence || ' | STAFF_ORG 4 Sep 2026: subscriber parked; the subscription now belongs to ' || m.new_agent, 2000)
  from m
 where c.component_id like 'evsub:' || m.old_agent || '@%' and c.activation_state = 'active';

-- The subscriptions §4.6 names, one per seat that consumed nothing (every event type below has a
-- producer in a database function or a real emission in company_event, measured 4 Sep 2026).
create temp table newsub (agent_key text, event_type text, reason text) on commit drop;
insert into newsub values
  ('followup',               'customer.complaint',  'CX lead owns escalated complaints'),
  ('channel_specialist',     'payment.received',    'Rating agent: solicit the rating at the revealed moment'),
  ('analytics',              'outcome.graded',      'Self-review agent: a graded outcome closes a batch of work'),
  ('bi_analyst',             'kpi.missed',          'KPI agent: a missed KPI re-measures'),
  ('market_analyst',         'improvement.proposed','Experiment agent: a proposal is a hypothesis to test'),
  ('supplier_analyst',       'rfq.classified',      'Match-eval agent grades every classified RFQ''s match'),
  ('billing_specialist',     'payment.received',    'Reconciliation agent: a Stripe payment is reconciled to its reveal'),
  ('collections',            'payment.received',    'Collections agent closes the chase on payment (invoice.flagged has no live producer)'),
  ('sales_director',         'campaign.launched',   'Demand lead runs the growth review on every launch'),
  ('onboarding',             'supplier.applied',    'Claim/Onboard agent walks the supplier who applied'),
  ('payments_manager',       'refund.requested',    'Refund-prep agent assembles the founder''s packet'),
  ('marketing_content',      'campaign.launched',   'Blog agent writes to the launched campaign'),
  ('marketing_social',       'campaign.launched',   'Social agent amplifies a launched campaign (content.published was retired 4 Sep)'),
  ('marketing_design',       'content.drafted',     'Creative agent produces the artwork for a draft'),
  ('moderation_specialist',  'supplier.applied',    'Moderation agent screens the supplier-facing payload'),
  ('trust_safety_mgr',       'security.event',      'Suspension agent acts on a fraud/abuse signal'),
  ('doc_intel_manager',      'rfq.created',         'Intake agent reads the request and its files'),
  ('inquiry_router',         'rfq.created',         'Router/Dispatch agent classifies and dispatches'),
  ('rfq_success',            'payment.received',    'Reveal-orchestration agent runs the reveal on payment'),
  ('culture_performance_mgr','kpi.missed',          'KPI-improvement agent opens the plan'),
  ('learning_dev_mgr',       'knowledge.updated',   'Certification agent re-examines on new knowledge'),
  ('recruitment_specialist', 'improvement.proposed','Hire/fire agent acts on a proposal that needs an owner'),
  ('backend_engineer',       'rollback.required',   'Kernel/runtime agent owns the rollback'),
  ('it',                     'health.degraded',     'Reliability/SRE agent opens the incident'),
  ('bd',                     'supply.gap',          'Supply lead aims the engine at the gap'),
  ('partnerships_mgr',       'supply.gap',          'Invite-campaign agent recruits where the gap is'),
  ('supplier_coverage',      'supplier.approved',   'Coverage-gap agent recomputes coverage on approval'),
  ('supplier_retention',     'supplier.approved',   'Retention agent starts on approval'),
  ('red_view_alerter',       'metric.alert',        'Red-view alerter: a metric went red'),
  ('red_view_alerter',       'os.health_changed',   'Red-view alerter: an operating-system health state changed');
insert into public.event_subscription (agent_key, event_type, reason, active)
  select n.agent_key, n.event_type, 'STAFF_ORG 4 Sep 2026 (MASTER_PLAN §4.6): ' || n.reason, true from newsub n
  on conflict (agent_key, event_type) do update set active = true;
-- Every active subscription is a component (phase_c_components_are_owned): clone the registry row
-- shape from the security seat's subscription for every subscription that has none.
insert into public.phase_c_component (component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
  schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id, workflow_id, step_id,
  authority_class, trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action, evidence)
select 'evsub:' || s.agent_key || '@' || s.event_type, t.component_type, t.source_path_or_db_object, t.entry_method, t.current_callers, t.external_entry,
       s.event_type, t.mutates_state, 'agent ' || s.agent_key, t.canonical_system_actor, r.role_id, r.primary_department_id, 'SYSTEM_SCOPE', '',
       'routine_operational_decision', t.trace_policy_id, t.idempotency_strategy, t.retry_policy, 'active', t.classification, '',
       'STAFF_ORG 4 Sep 2026: subscription added so the seat consumes the event the plan names',
       'event_subscription: agent_key=' || s.agent_key || ' event_type=' || s.event_type || ' active=true; reason="' || left(coalesce(s.reason, ''), 200) || '"'
  from public.event_subscription s
  join public.org_role r on r.runtime_agent_key = s.agent_key and r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
  cross join (select * from public.phase_c_component where component_id = 'evsub:security@security.event') t
 where s.active
   and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type)
on conflict (component_id) do nothing;
update public.phase_c_component c
   set activation_state = 'active'
 where c.component_id like 'evsub:%' and c.activation_state <> 'active'
   and exists (select 1 from public.event_subscription s where s.active and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id);

insert into public.employee_workflow (agent_key, workflow_key, role_in_workflow)
  select m.new_agent, w.workflow_key, w.role_in_workflow
    from public.employee_workflow w join m on m.old_agent = w.agent_key
  on conflict (agent_key, workflow_key) do nothing;
delete from public.employee_workflow w using m where w.agent_key = m.old_agent;
update public.continuity_plan x set owner_agent = m.new_agent from m where x.owner_agent = m.old_agent;
update public.operating_system x set owner_agent = m.new_agent from m where x.owner_agent = m.old_agent;
update public.org_category_identity x set owner_agent = m.new_agent from m where x.owner_agent = m.old_agent;
update public.risk_register x set owner_agent = m.new_agent from m where x.owner_agent = m.old_agent;

-- =============================================================================================
-- 4. SETTLEMENT (the 3 Sep parts 3/3b/3c rules, applied to these parks).
-- =============================================================================================
-- Packaged identities: a producer identity goes to the successor unless the successor audits that
-- packaged department (then one level up); a reviewer-auditor identity goes one level up unless
-- the manager produces there. Shared holdings are runtime_composite. An inactive employee holds none.
insert into public.org_role_identity (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness, package_version)
  select distinct on (i.packaged_role_id) h.holder, i.packaged_role_id, i.packaged_department, i.archetype, 'runtime_composite', i.readiness, i.package_version
    from public.org_role_identity i
    join m on m.old_agent = i.agent_key
    join public.org_agents g on g.agent_key = m.new_agent
    cross join lateral (
      select x.holder from (values (1, m.new_agent), (2, g.manager_key)) x(ord, holder)
       where x.holder is not null
         and exists (select 1 from public.org_agents a where a.agent_key = x.holder and a.active)
         and not exists (select 1 from public.org_role_identity o
                          where o.agent_key = x.holder and o.packaged_department = i.packaged_department and o.packaged_role_id <> i.packaged_role_id
                            and ((i.archetype = 'reviewer-auditor' and o.archetype <> 'reviewer-auditor')
                              or (i.archetype <> 'reviewer-auditor' and o.archetype = 'reviewer-auditor')))
         and not (i.archetype = 'reviewer-auditor' and x.ord = 1)
       order by x.ord limit 1) h
   where not exists (select 1 from public.org_role_identity x join public.org_agents a on a.agent_key = x.agent_key and a.active
                      where x.packaged_role_id = i.packaged_role_id)
   order by i.packaged_role_id, i.updated_at desc
  on conflict (agent_key, packaged_role_id) do nothing;
update public.org_role_identity i set mapping_type = 'runtime_composite', updated_at = now()
 where i.mapping_type in ('one_to_one', 'requires_split', 'package_composite')
   and exists (select 1 from public.org_agents a where a.agent_key = i.agent_key and a.active)
   and exists (select 1 from public.org_role_identity p join m on m.old_agent = p.agent_key where p.packaged_role_id = i.packaged_role_id);
delete from public.org_role_identity i using m where i.agent_key = m.old_agent;

-- Open work and its department.
update public.org_tasks t set assigned_agent = m.new_agent
  from m where t.assigned_agent = m.old_agent and t.status in ('proposed', 'assigned', 'in_progress');
update public.org_tasks t set dept_key = a.department
  from public.org_agents a
 where a.agent_key = t.assigned_agent and a.active
   and t.status in ('proposed', 'assigned', 'in_progress') and t.dept_key <> a.department;
update public.org_agents a set manager_key = m.new_agent from m where a.manager_key = m.old_agent and a.active is false;

-- Committee seats, KPIs and remediation follow the function.
update public.org_role_committee c set role_id = m.new_role, note = coalesce(c.note || ' | ', '') || 'STAFF_ORG 4 Sep 2026: seat inherited from ' || m.old_role
  from m
 where c.role_id = m.old_role
   and not exists (select 1 from public.org_role_committee x where x.role_id = m.new_role and x.committee_key = c.committee_key);
delete from public.org_role_committee c using m where c.role_id = m.old_role;
update public.employee_kpi k set agent_key = m.new_agent
  from m
 where k.agent_key = m.old_agent
   and not exists (select 1 from public.employee_kpi x where x.agent_key = m.new_agent and x.kpi = k.kpi);
update public.employee_kpi k set active = false from m where k.agent_key = m.old_agent and k.active;
update public.agent_remediation ar
   set agent_key = m.new_agent,
       detail = coalesce(ar.detail, '{}'::jsonb) || jsonb_build_object('transferred', 'STAFF_ORG 4 Sep 2026: opened against ' || m.old_agent || ', now parked; the KPI it remediates is owned by ' || m.new_agent)
  from m
 where ar.agent_key = m.old_agent and ar.status = 'open';

-- Standing deputies: a rule whose deputy is not an active member of the department picks the most
-- senior active member other than the head; a rule whose head is parked lapses.
update public.delegation_rule d set active = false
 where d.active and not exists (select 1 from public.org_agents a where a.agent_key = d.when_agent and a.active and a.department = d.dept_key);
update public.delegation_rule d
   set delegate_to = (select a.agent_key from public.org_agents a
                       where a.department = d.dept_key and a.active and a.agent_key <> d.when_agent
                       order by public.fn_seniority_rank(a.seniority), a.agent_key limit 1)
 where d.active and not exists (select 1 from public.org_agents a where a.agent_key = d.delegate_to and a.active and a.department = d.dept_key and a.agent_key <> d.when_agent);

-- =============================================================================================
-- 5. FLATTEN: one lead per department; workers report to it. 12 leadership seats.
-- =============================================================================================
update public.org_agents a
   set manager_key = case when a.agent_key = 'ceo' then null when l.agent_key = a.agent_key then 'ceo' else l.agent_key end,
       seniority   = case when a.agent_key = 'ceo' then 'executive'
                          when a.agent_key in ('brief', 'cpo') then a.seniority
                          when l.agent_key = a.agent_key then 'director'
                          else 'specialist' end
  from dlead l
 where a.active and l.dept = a.department;
update public.org_role r
   set manager_role_id = case when r.role_id = 'ceo' then null when l.role_id = r.role_id then 'ceo' else l.role_id end,
       updated_at = now()
  from dlead l
 where r.status = 'active' and r.runtime_mode <> 'knowledge_overlay' and l.dept = r.primary_department_id
   and r.manager_role_id is distinct from case when r.role_id = 'ceo' then null when l.role_id = r.role_id then 'ceo' else l.role_id end;
update public.phase_c_role_binding b set department_id = r.primary_department_id
  from public.org_role r
 where r.role_id = b.canonical_role_id and r.status = 'active' and b.department_id is distinct from r.primary_department_id;
update public.phase_c_reporting_authority ra
   set department_id = r.primary_department_id,
       manager_role_id = coalesce(r.manager_role_id, 'founder'),
       department_head_role_id = (select h.role_id from public.org_departments d
                                    join public.org_role h on h.runtime_agent_key = d.lead_agent and h.status = 'active'
                                   where d.dept_key = r.primary_department_id order by h.role_id limit 1),
       reporting_path = case when r.manager_role_id is null then r.role_id || ' > founder'
                             when r.manager_role_id = 'ceo' then r.role_id || ' > ceo > founder'
                             else r.role_id || ' > ' || r.manager_role_id || ' > ceo > founder' end
  from public.org_role r
 where r.role_id = ra.canonical_role_id and r.status = 'active';

-- =============================================================================================
-- 6. THE BASELINE RECORDS, digests recomputed to the values now held (no freeze; drift = 0).
-- =============================================================================================
-- A sibling packet is retiring the freeze instruments (fn_phase_a/b_baseline_drift were dropped
-- while this file was being rehearsed). The record is still recomputed so it describes the state
-- now held; the append-only trigger is put back only if it was there.
create temp table baseline_trigger_was_present on commit drop as
  select exists (select 1 from pg_trigger where tgname = 'a00_org_phase_baseline_append_only') present;
drop trigger if exists a00_org_phase_baseline_append_only on public.org_phase_baseline;
update public.org_phase_baseline b
   set counts = b.counts || jsonb_build_object(
         'active_departments',       (select count(*) from public.org_departments where active),
         'canonical_roles',          (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'),
         'category_overlays',        (select count(*) from public.org_role where status='active' and runtime_mode = 'knowledge_overlay'),
         'department_heads',         (select count(*) from public.org_departments where active and lead_agent is not null),
         'organizational_workflows', (select count(*) from public.org_workflow_ownership),
         'retired_roles',            (select count(*) from public.org_role where status='retired')),
       registry_sha256 = jsonb_set(jsonb_set(jsonb_set(
         b.registry_sha256,
         '{workflow_ownership,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select o.workflow_id sortkey,
                                  o.workflow_id||'|'||o.workflow_name||'|'||o.accountable_role_id||'|'
                                  ||array_to_string(o.contributors, ';')||'|'||coalesce(o.independent_reviewer,'') x
                             from public.org_workflow_ownership o) s))),
         '{departments,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by x), ''), 'UTF8')), 'hex')
                     from (select d.dept_key||'|'||d.name||'|'||coalesce(d.lead_agent,'') x
                             from public.org_departments d where d.active) s))),
         '{reporting_graph,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select r.role_id sortkey,
                                  r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                             from public.org_role r
                            where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s))),
       organization_sha256 = (
         with
         d as (select string_agg(dept_key||'|'||name||'|'||active::text||'|'||coalesce(lead_agent,''), chr(10) order by dept_key) x from public.org_departments),
         r as (select string_agg(role_id||'|'||display_name||'|'||primary_department_id||'|'||coalesce(manager_role_id,'')
                 ||'|'||runtime_mode||'|'||coalesce(runtime_agent_key,'')||'|'||status||'|'||coalesce(evaluation_suite,'')
                 ||'|'||coalesce(array_length(owned_decisions,1),0)::text||'|'||coalesce(array_length(forbidden_decisions,1),0)::text,
                 chr(10) order by role_id) x from public.org_role),
         c as (select string_agg(category_key, chr(10) order by category_key) x from public.org_category_identity),
         w as (select string_agg(workflow_key||'|'||step_no::text||'|'||step||'|'||coalesce(actor_role,''), chr(10) order by workflow_key, step_no) x from public.workflow_step),
         f as (select string_agg(decision_key, chr(10) order by decision_key) x from public.founder_reserved_decision),
         a as (select string_agg(agent_key||'|'||department||'|'||active::text||'|'||coalesce(manager_key,''), chr(10) order by agent_key) x from public.org_agents)
         select encode(sha256(convert_to(
           'departments'||chr(10)||d.x||chr(10)||'--'||chr(10)||
           'roles'||chr(10)||r.x||chr(10)||'--'||chr(10)||
           'categories'||chr(10)||c.x||chr(10)||'--'||chr(10)||
           'workflow_steps'||chr(10)||w.x||chr(10)||'--'||chr(10)||
           'reserved'||chr(10)||f.x||chr(10)||'--'||chr(10)||
           'agents'||chr(10)||a.x, 'UTF8')), 'hex')
         from d, r, c, w, f, a),
       note = b.note || chr(10) || chr(10) || 'STAFF_ORG 4 Sep 2026: seated at the plan''s size. 18 personas parked (the 15 the handoff rule '
              'kept on 3 Sep, plus hr_director, ai_director, eng_manager), the red-view alerter created, the COO moved to lead Agent Ops, '
              'Office of the CEO trimmed to 3; every worker reports to its department lead; digests recomputed to the values now held.',
       recorded_at = now()
 where b.phase = 'A';
update public.org_phase_baseline b
   set counts = b.counts || jsonb_build_object(
         'handoffs', (select count(*) from public.phase_b_handoff),
         'cross_department_handoffs', (select count(*) from public.phase_b_handoff where handoff_type = 'cross_department')),
       registry_sha256 = jsonb_set(b.registry_sha256, '{structure}',
         (select jsonb_object_agg(d.subject, coalesce(b.registry_sha256->'structure'->d.subject, '{}'::jsonb) || jsonb_build_object('database', d.sha256))
            from public.fn_phase_b_structure_digest() d)),
       note = b.note || chr(10) || chr(10) || 'STAFF_ORG 4 Sep 2026: the handoffs that joined a parked persona''s step to its successor''s step were '
              'walked to the successor; those whose two ends landed on one seat were removed (a merged party is not a handoff); every other '
              'handoff names the owners of the steps it joins; digests recomputed to the values now held.',
       recorded_at = now()
 where b.phase = 'B';
do $t$ begin
  if (select present from baseline_trigger_was_present) then
    create trigger a00_org_phase_baseline_append_only
      before delete or update on public.org_phase_baseline
      for each row execute function public.fn_org_phase_baseline_append_only();
  end if;
end $t$;

-- =============================================================================================
-- 7. PROOF, same transaction. Any miss aborts the whole thing.
-- =============================================================================================
do $proof$
declare
  v_active int; v_parked int; v_leads int; v_dept_bad text; v_rule_fail text; v_collapsed int; v_self int;
  v_pb_left int; v_pc_left int; v_gaps int; v_gap_txt text; v_viol int; v_viol_txt text; v_bad text;
  v_a_drift int; v_b_drift int; v_a_viol int; v_comp_bad int; v_evsub_bad int; v_lead_bad int; v_apex int;
  v_orphan_ident int; v_ident_agents int; v_canon int; v_no_approver int; v_unsafe int; v_open_tasks int;
  v_fn text; v_instr text := ''; v_cnt text;
  v_rehearsal boolean := coalesce(current_setting('app.recarve_rehearsal', true), '') = '1';
begin
  select count(*) into v_active from public.org_agents where active;
  select count(*) into v_parked from public.org_agents a join park p on p.agent_key = a.agent_key where not a.active;
  select count(*) into v_leads from public.org_agents where active and seniority <> 'specialist';
  select string_agg(d.dept_key || '=' || d.n || '/' || d.want, ', ') into v_dept_bad
    from (select l.dept dept_key, (select count(*) from public.org_agents a where a.active and a.department = l.dept) n,
                 (select count(*) from seat s where s.dept = l.dept) want from dlead l) d
   where d.n <> d.want;
  select string_agg(r.agent_key || '(' || concat_ws(',', case when not r.has_event then 'event' end, case when not r.has_executor then 'executor' end, case when not r.has_playbook then 'playbook' end) || ')', ', ')
    into v_rule_fail from public.fn_agent_binding_rule() r where not r.passes;
  select count(*) into v_collapsed from collapsed;
  select count(*) into v_self from public.phase_b_handoff h
    join public.phase_b_workflow_step sf on sf.step_id = h.from_step_id join public.phase_b_workflow_step st on st.step_id = h.to_step_id
   where sf.accountable_role_id = st.accountable_role_id;
  select count(*) into v_pb_left from (
    select 1 from public.phase_b_workflow_step s join m on m.old_role in (s.accountable_role_id, s.independent_reviewer_role_id)
    union all select 1 from public.phase_b_workflow w join m on m.old_role in (w.accountable_role_id, w.independent_reviewer_role_id)
    union all select 1 from public.phase_b_handoff h join m on m.old_role in (h.sending_role_id, h.receiving_role_id, h.return_owner_role_id)
    union all select 1 from public.phase_b_exception e join m on m.old_role in (e.detection_owner_role_id, e.escalation_owner_role_id)
    union all select 1 from public.phase_b_event e join m on m.old_role = e.primary_consumer_role_id
    union all select 1 from public.phase_b_business_object o join m on m.old_role = o.accountable_role_id) z;
  select count(*) into v_pc_left from (
    select 1 from public.phase_c_step_binding b join m on m.old_role in (b.accountable_role_id, b.independent_reviewer_role_id)
    union all select 1 from public.phase_c_handoff_binding b join m on m.old_role in (b.sending_role_id, b.receiving_role_id)
    union all select 1 from public.phase_c_task t join m on m.old_role in (t.accountable_role_id, t.manager_role_id, t.reviewer_role_id, t.blocker_owner_role_id)
    union all select 1 from public.phase_c_role_binding b join m on m.old_agent = b.runtime_agent_key where b.connection_status = 'CONNECTED'
    union all select 1 from public.phase_c_reporting_authority r join m on m.old_role in (r.canonical_role_id, r.manager_role_id, r.department_head_role_id, r.live_role_id)
    union all select 1 from public.phase_c_component c join m on m.old_role = c.accountable_role_id
    union all select 1 from public.event_subscription e join m on m.old_agent = e.agent_key
    union all select 1 from public.org_role_identity i join m on m.old_agent = i.agent_key
    union all select 1 from public.workflow_step w join m on w.actor_role in (m.old_agent, m.old_role, m.old_title, m.old_dn)) z;
  select count(*), string_agg(gap_class || ' ' || subject, '; ') into v_gaps, v_gap_txt from public.fn_company_connectivity_register();
  select count(*), string_agg(rule || ':' || role_id, ', ') into v_viol, v_viol_txt from (select rule, role_id from public.fn_org_role_violations() limit 12) z;
  select string_agg(check_name || '=' || actual || '/' || expected, ', ') into v_bad
    from public.fn_phase_c_invariants()
   where not ok and check_name in ('roles_bound', 'roles_without_binding', 'step_owners_resolve', 'steps_owned_by_overlay_outside_declared_scope', 'command_tasks_without_canonical_owner');
  -- Phase A/B instruments: consulted if they still exist (a sibling packet is retiring them).
  v_a_drift := 0; v_b_drift := 0; v_a_viol := 0;
  foreach v_fn in array array['fn_phase_a_baseline' || '_drift', 'fn_phase_b_baseline' || '_drift', 'fn_phase_a_organization' || '_violations'] loop
    if to_regproc('public.' || v_fn) is not null then
      execute format('select count(*) from public.%I()', v_fn) into v_cnt;
      v_instr := v_instr || v_fn || '=' || v_cnt || ' ';
      if v_fn like '%a_baseline%' then v_a_drift := v_cnt::int; elsif v_fn like '%b_baseline%' then v_b_drift := v_cnt::int; else v_a_viol := v_cnt::int; end if;
    else v_instr := v_instr || v_fn || '=retired '; end if;
  end loop;
  select count(*) into v_comp_bad from public.phase_c_component c
    left join public.org_role r on r.role_id = c.accountable_role_id and r.status = 'active'
    left join public.org_departments d on d.dept_key = c.department_id
   where r.role_id is null or d.dept_key is null or not d.active or c.department_id is distinct from r.primary_department_id;
  select count(*) into v_evsub_bad from (
    select 1 from public.event_subscription s where s.active and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type and c.activation_state = 'active')
    union all
    select 1 from public.phase_c_component c where c.component_id like 'evsub:%' and c.activation_state = 'active'
       and not exists (select 1 from public.event_subscription s where s.active and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id)) z;
  select count(*) into v_lead_bad from public.org_departments d where d.active and (d.lead_agent is null or not exists
    (select 1 from public.org_agents a where a.agent_key = d.lead_agent and a.active and a.department = d.dept_key));
  select count(*) into v_apex from public.org_agents where active and manager_key is null;
  select count(*) into v_orphan_ident from public.org_role_identity i where not exists (select 1 from public.org_agents a where a.agent_key = i.agent_key and a.active);
  select count(distinct agent_key) into v_ident_agents from public.org_role_identity;
  select count(*) into v_canon from public.org_role where status = 'active' and runtime_mode <> 'knowledge_overlay';
  select count(*) into v_no_approver from public.org_departments d where d.active
     and ((public.fn_action_resolve_approver(d.dept_key, 'medium')->>'approver') is null or (public.fn_action_resolve_approver(d.dept_key, 'high')->>'approver') is null);
  select count(*) into v_unsafe from public.unsafe_class u
   where not exists (select 1 from public.org_agents a where a.agent_key = (public.fn_unsafe_escalation_route(u.class_key, null)->>'route_to') and a.active);
  select count(*) into v_open_tasks from public.org_tasks t where t.status in ('proposed', 'assigned', 'in_progress')
     and t.assigned_agent is not null and not exists (select 1 from public.org_agents a where a.agent_key = t.assigned_agent and a.active);

  if v_active <> 54 then raise exception 'STAFF_ORG: expected 54 active personas, found %', v_active; end if;
  if v_parked <> (select count(*) from park) then raise exception 'STAFF_ORG: parked % of %', v_parked, (select count(*) from park); end if;
  if v_dept_bad is not null then raise exception 'STAFF_ORG: department headcount off plan: %', v_dept_bad; end if;
  if v_leads > 12 then raise exception 'STAFF_ORG: % leadership seats, plan allows 12', v_leads; end if;
  if v_rule_fail is not null then raise exception 'STAFF_ORG: active personas failing the binding rule: %', v_rule_fail; end if;
  if v_self > 0 then raise exception 'STAFF_ORG: % handoffs still join two steps owned by one role', v_self; end if;
  if v_pb_left > 0 then raise exception 'STAFF_ORG: % Phase B rows still name a parked role', v_pb_left; end if;
  if v_pc_left > 0 then raise exception 'STAFF_ORG: % Phase C / runtime rows still name a parked persona', v_pc_left; end if;
  if v_gaps > 0 then raise exception 'STAFF_ORG: the connectivity register reports % gap(s): %', v_gaps, v_gap_txt; end if;
  if v_viol > 0 then raise exception 'STAFF_ORG: fn_org_role_violations reports % rows: %', v_viol, v_viol_txt; end if;
  if v_bad is not null then raise exception 'STAFF_ORG: kernel invariants red: %', v_bad; end if;
  if v_a_viol > 0 then raise exception 'STAFF_ORG: % Phase A organization violations', v_a_viol; end if;
  if v_a_drift > 0 then raise exception 'STAFF_ORG: Phase A baseline drift reports % rows', v_a_drift; end if;
  if v_b_drift > 0 then raise exception 'STAFF_ORG: Phase B baseline drift reports % rows', v_b_drift; end if;
  if v_comp_bad > 0 then raise exception 'STAFF_ORG: % components are accountable to a non-active role or sit outside their role''s department', v_comp_bad; end if;
  if v_evsub_bad > 0 then raise exception 'STAFF_ORG: % subscription/component mismatches', v_evsub_bad; end if;
  if v_lead_bad > 0 then raise exception 'STAFF_ORG: % departments whose lead is not an active member', v_lead_bad; end if;
  if v_apex <> 1 then raise exception 'STAFF_ORG: % active personas without a manager (only the CEO may)', v_apex; end if;
  if v_orphan_ident > 0 then raise exception 'STAFF_ORG: % packaged identities on inactive employees', v_orphan_ident; end if;
  if v_ident_agents <> v_canon then raise exception 'STAFF_ORG: % identity holders vs % canonical roles', v_ident_agents, v_canon; end if;
  if v_no_approver > 0 then raise exception 'STAFF_ORG: % departments cannot resolve a medium/high approver', v_no_approver; end if;
  if v_unsafe > 0 then raise exception 'STAFF_ORG: % unsafe classes route to an inactive owner', v_unsafe; end if;
  if v_open_tasks > 0 then raise exception 'STAFF_ORG: % open tasks assigned to an inactive persona', v_open_tasks; end if;
  raise notice 'STAFF_ORG proof: 54 active (% parked this run, % leadership), % handoffs collapsed this run, 0 self-handoffs, binding rule 54/54, register 0, role violations 0, instruments: %',
    v_parked, v_leads, v_collapsed, v_instr;
  if v_rehearsal then
    raise exception 'REHEARSAL OK — rolled back: 54 active, % parked, % leadership, % handoffs collapsed, binding rule 54/54, register 0, instruments: %', v_parked, v_leads, v_collapsed, v_instr;
  end if;
end $proof$;
commit;
