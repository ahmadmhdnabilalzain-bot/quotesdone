-- PHASE 1 DELIVERABLE: one explicit decision per concept, with live evidence, as the mapping guide
-- requires. The rule that shaped all of them: every one of the 33 objects the guide names ALREADY
-- EXISTS and is populated. This corpus is not describing a system to be built - it is describing a
-- larger version of one that is running. So the default is 'reuse', 'extend' is for a real missing
-- field, and 'create_staging' is reserved for concepts production genuinely has no owner for.
insert into ops_kb_stage.mapping_decisions (concept_type, concept_key, existing_object, decision, rationale, decided_by, evidence) values

('organisation','department','public.org_departments','reuse',
 'Production has 15 departments with charter, north_star, health_fn, lead_agent and brain_agent. The corpus describes 24 target departments. Writing the 24 into org_departments would create 9 departments with no agents, no authority rows and no health function, which the Command Center would immediately report as broken. The corpus set stays in ops_kb_stage.departments and is bridged by department_crosswalk.',
 'import_2026_08_02', jsonb_build_object('production_rows',(select count(*) from public.org_departments),'target_rows',24)),

('organisation','role_agent','public.org_agents','reuse',
 'Production has 67 agents keyed on agent_key with department, manager_key, seniority and responsibilities - the same shape as the corpus role records. The 96 target roles are a superset. Creating them now would produce 29 agents with no tasks and no authority, and org_tasks assignment would start routing to agents that cannot act.',
 'import_2026_08_02', jsonb_build_object('production_agents',(select count(*) from public.org_agents),'target_roles',96)),

('governance','authority_tier','public.org_authority','extend',
 'org_authority already carries (dept_key, action_class, max_tier, threshold_aed) and was re-tiered on 29 Jul. The corpus adds a per-RECORD authority_tier and risk_level, which org_authority has no place for because it is keyed on action class, not on knowledge. Extension needed at promotion time, not now: a record-level tier must never widen a department-level one.',
 'import_2026_08_02', jsonb_build_object('authority_rows',(select count(*) from public.org_authority),'corpus_gated',(select count(*) from ops_kb_stage.records where authority_tier='gated'))),

('governance','hard_gate','public.governance_policy + public.governance_rule','extend',
 'Production has 16 governance policies and 11 rules. The corpus supplies 10 explicit hard gates (money movement, legal commitment, identity change, production deployment, secret change). These are the same concept at a higher level of abstraction and must end up in ONE place - but merging them before the wording is reviewed risks weakening an existing rule by restating it more loosely.',
 'import_2026_08_02', jsonb_build_object('governance_policy',(select count(*) from public.governance_policy),'governance_rule',(select count(*) from public.governance_rule),'corpus_hard_gates',10)),

('governance','decision_rule','public.decision_policy + public.delegation_rule','extend',
 'Production has 26 decision policies and 10 delegation rules as key/value and simple conditions. The corpus supplies 240 department decision rules with structured condition/action jsonb and requires_human_review. Materially richer, and worth adopting - but every one lands enabled=false. An imported rule that can fire is an activated rule.',
 'import_2026_08_02', jsonb_build_object('decision_policy',26,'delegation_rule',10,'corpus_rules',240)),

('knowledge','department_knowledge','public.dept_library + public.agent_knowledge','reuse',
 'dept_library holds 1,456 rows and agent_knowledge 1,845 - both live and read by agent_brain today. The 1,920 corpus knowledge records are a parallel, better-structured description of the same thing. Promotion is per department, after scenarios pass, so the two never disagree at runtime.',
 'import_2026_08_02', jsonb_build_object('dept_library',(select count(*) from public.dept_library),'agent_knowledge',(select count(*) from public.agent_knowledge),'corpus_knowledge',1920)),

('knowledge','employee_knowledge','public.employee_knowledge + public.employee_knowledge_standard','reuse',
 'Production already models what an employee must know (900 rows) against a standard (12). The corpus role records carry knowledge_scope, which maps onto that standard rather than replacing it.',
 'import_2026_08_02', jsonb_build_object('employee_knowledge',900,'employee_knowledge_standard',12)),

('process','sop','public.employee_workflow','extend',
 'employee_workflow has 157 rows but only 3 columns - it records THAT a workflow exists, not its steps, inputs, outputs, service level, definition of done or rollback. The 236 corpus SOPs carry all six. This is the clearest case in the whole import where the corpus is strictly better than what is running.',
 'import_2026_08_02', jsonb_build_object('employee_workflow_rows',157,'employee_workflow_cols',3,'corpus_sops',236)),

('process','cross_department_workflow','(none)','create_staging',
 'Production has no object that models a workflow SPANNING departments with typed handoffs and acceptance criteria. company_event (98 rows) and event_subscription (48) carry the messaging, but nothing owns the workflow itself, its hard gates or its definition of done. 18 workflows and 132 handoffs land in staging; this is the largest genuinely new capability in the corpus.',
 'import_2026_08_02', jsonb_build_object('corpus_workflows',18,'corpus_handoffs',132,'company_event',98)),

('process','exception_playbook','public.risk_register','extend',
 'risk_register (19 rows) records risks; it does not record what to DO when one fires. The 240 exception playbooks supply trigger, immediate actions, recovery and closure. Complementary, not duplicative.',
 'import_2026_08_02', jsonb_build_object('risk_register',19,'corpus_playbooks',240)),

('measurement','kpi','public.employee_kpi','extend',
 'employee_kpi has 95 rows keyed to individuals. The 216 corpus KPIs are DEPARTMENT metrics with a formula description, direction and candidate source objects - a different grain. Neither replaces the other; the corpus KPIs need query_sql written before any of them can be computed, which is why every one is enabled=false.',
 'import_2026_08_02', jsonb_build_object('employee_kpi',95,'corpus_kpis',216,'kpis_with_sql',0)),

('testing','scenario','public.scenario_library','extend',
 'scenario_library holds 12 scenarios against the corpus''s 282 (192 department + 90 cross-department). Same concept, twenty-three times the coverage. Needs a harness that can drive a scenario before the count means anything.',
 'import_2026_08_02', jsonb_build_object('scenario_library',12,'corpus_scenarios',282)),

('runtime','event_subscription','public.event_subscription + public.company_event','reuse',
 'Production has 48 subscriptions and 98 events with a working emitter (fn_emit_event fires on inquiry insert today). The 100 corpus subscriptions are a superset naming event types that do not all exist yet. Imported active=false so a subscription for an event nobody emits cannot look live.',
 'import_2026_08_02', jsonb_build_object('production_subscriptions',48,'corpus_subscriptions',100)),

('runtime','live_data_binding','public.implementation_map + public.integration_matrix','extend',
 'implementation_map (18) and integration_matrix (13) map features to code. The 268 live-data bindings map DEPARTMENTS to database objects, which neither does. 262 resolve to real tables; the 6 that do not are naming drift except refunds, which is a real data-model gap.',
 'import_2026_08_02', jsonb_build_object('implementation_map',18,'integration_matrix',13,'bindings',268,'resolved',262)),

('audit','audit_record','public.os_audit_log + public.agent_action_log + public.security_audit_log','reuse',
 'Three live audit streams totalling ~4,600 rows. The corpus audit policy describes requirements those streams mostly already meet. No new audit table; the policy records become the checklist the existing streams are measured against.',
 'import_2026_08_02', jsonb_build_object('os_audit_log',2925,'security_audit_log',1664,'agent_action_log',28)),

('memory','institutional_memory','public.institutional_memory + public.org_memory + public.agent_memory','reuse',
 'Three memory tables already exist (30 / 153 / 194 rows). The corpus supplies 6 memory POLICY records - retention, promotion, forgetting - which is exactly what is missing, and none of it needs a fourth table.',
 'import_2026_08_02', jsonb_build_object('institutional_memory',30,'org_memory',153,'agent_memory',194,'corpus_memory_policies',6)),

('ai','model_routing_policy','public.model_policy + public.llm_policy + ai_gateway','reuse',
 'Model routing is already implemented in ai_gateway with fn_ai_route, capability-aware selection and per-department budgets, and is measured in ai_cost_log. The 5 corpus routing policy records are a written statement of intent for a mechanism that is already running. Reuse and reconcile; do not build a second router.',
 'import_2026_08_02', jsonb_build_object('corpus_routing_policies',5,'ai_cost_log_rows',(select count(*) from public.ai_cost_log))),

('data','data_classification','(none)','create_staging',
 'No production object classifies data by sensitivity. The 5 corpus classification records are new capability and are directly relevant to the anonymity model and PDPL - this is the second-most valuable new thing in the corpus after cross-department workflows.',
 'import_2026_08_02', jsonb_build_object('corpus_classifications',5)),

('incident','incident_priority','public.incidents','extend',
 'Incidents exist operationally. The corpus supplies 4 priority definitions with response expectations, which give the existing incident records a severity scale they currently lack.',
 'import_2026_08_02', jsonb_build_object('corpus_incident_priorities',4)),

('organisation','department_crosswalk','(none)','create_staging',
 'NEEDS A DECISION, not just a table. Validation against live org_departments found three conflicts the supplied crosswalk does not contain: production departments hr and sales exist and are unmapped, and target department ai_model_ops has no production owner. Promotion cannot proceed until these three are resolved.',
 'import_2026_08_02', jsonb_build_object('unmapped_production',array['hr','sales'],'target_without_owner',array['ai_model_ops'])),

('marketplace','supplier_category_expertise','kb_stage.records + public.kb_operational_route','reuse',
 'The 86-route supplier corpus imported earlier today is the technical source for category and quote-comparison expertise, exactly as this pack requires. RFQ Intelligence, Marketplace Operations, Supplier Knowledge and Document Intelligence link to it by catalog_num / subcategory slug rather than copying any of it.',
 'import_2026_08_02', jsonb_build_object('supplier_records',(select count(*) from kb_stage.records),'routes',86))

on conflict (concept_type, concept_key) do update
  set existing_object=excluded.existing_object, decision=excluded.decision,
      rationale=excluded.rationale, evidence=excluded.evidence, decided_at=now();
