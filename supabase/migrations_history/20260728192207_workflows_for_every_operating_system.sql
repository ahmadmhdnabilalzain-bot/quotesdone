-- Component 9: only 5 workflows existed for 10 systems, and two were filed under the wrong
-- one. Every OS now owns at least one end-to-end workflow with actors, action classes and gates.

update workflow set os_key='finance'    where workflow_key='invoice_approval';
update workflow set os_key='commercial' where workflow_key='campaign_publishing';

insert into workflow (workflow_key, name, trigger_event, description, active, os_key) values
 ('strategic_review','Strategic review and re-prioritisation','goal.at_risk',
  'How the company changes what it is working on: evidence, options, decision, cascade to departments, measurement.',true,'leadership'),
 ('lead_to_customer','Lead to customer','lead.qualified',
  'Lead, qualification, proposal, negotiation, close, handover to Customer Success.',true,'commercial'),
 ('incident_response','Incident response','health.degraded',
  'Detect, triage severity, assign, contain, fix, verify, write the lesson, update the runbook.',true,'technology'),
 ('change_deployment','Change to production','deploy.completed',
  'Change proposed, reviewed, deployed to preview, verified, promoted, monitored, reversible.',true,'technology'),
 ('budget_cycle','Budget setting and enforcement','budget.exceeded',
  'Set department budgets, meter spend, degrade at threshold, halt at ceiling, review and reset monthly.',true,'finance'),
 ('contract_review','Contract review and approval','contract.submitted',
  'Intake, risk classification, clause review, escalation if outside authority, approval, signature, archive.',true,'legal_gov'),
 ('knowledge_lifecycle','Knowledge lifecycle','knowledge.updated',
  'Acquire from a cited source, validate, publish, serve, decay, re-validate or quarantine, retire.',true,'knowledge'),
 ('metric_lifecycle','Metric lifecycle','kpi.missed',
  'Define the metric, instrument it, measure, detect variance, find root cause, revise the metric or the target.',true,'intelligence'),
 ('improvement_lifecycle','Improvement lifecycle','improvement.proposed',
  'Detect weakness, root cause, propose with a named metric and baseline, approve, execute, grade, promote or roll back, record the lesson.',true,'evolution')
on conflict (workflow_key) do nothing;

insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('strategic_review',1,'Evidence: KPI scoreboard, OS health, goal periods','intel_director','health_report',null),
 ('strategic_review',2,'Generate options with cost and risk for each','strategy_director','recommend',null),
 ('strategic_review',3,'Test options against the priority hierarchy','brief','coordinate','constitution'),
 ('strategic_review',4,'Decide and record rationale','ceo','exec_review','authority'),
 ('strategic_review',5,'Cascade: supersede objectives, open re-plan work','brief','coordinate',null),
 ('strategic_review',6,'Open an outcome record with a baseline','cpo','recommend',null),

 ('lead_to_customer',1,'Lead captured and attributed to a channel','crm_pipeline_mgr','recommend',null),
 ('lead_to_customer',2,'Qualify against budget, authority, need, timing','account_mgr','qualify_inquiry',null),
 ('lead_to_customer',3,'Proposal drafted','sales_director','outreach_draft',null),
 ('lead_to_customer',4,'Brand and legal review before it leaves','brand_mgr','qa_gate','review'),
 ('lead_to_customer',5,'Negotiate within pricing authority','sales_director','recommend','authority'),
 ('lead_to_customer',6,'Close and record the terms','account_mgr','recommend',null),
 ('lead_to_customer',7,'Handover to Customer Success with full context','cs_onboarding','coordinate',null),

 ('incident_response',1,'Detect from health, drift or a failed gate','it','uptime_verify',null),
 ('incident_response',2,'Classify severity and blast radius','security','security_review',null),
 ('incident_response',3,'Assign an owner and open the incident','ops_director','incident_fix',null),
 ('incident_response',4,'Contain: degrade or fail over per the continuity plan','cto','code_selfheal','authority'),
 ('incident_response',5,'Fix and verify the metric recovers','backend_engineer','incident_fix','review'),
 ('incident_response',6,'Write the lesson to institutional memory','knowledge_director','knowledge_fill',null),
 ('incident_response',7,'Update the runbook so it cannot recur silently','ops_director','knowledge_fill',null),

 ('change_deployment',1,'Change proposed with the metric it should move','optimisation_eng','recommend',null),
 ('change_deployment',2,'Reviewed for correctness and blast radius','solution_architect','qa_gate','review'),
 ('change_deployment',3,'Deploy to preview','frontend_engineer','code_selfheal','authority'),
 ('change_deployment',4,'Verify against the quality gate','qa_manager','qa_gate','review'),
 ('change_deployment',5,'Promote to production','cto','code_selfheal','authority'),
 ('change_deployment',6,'Monitor and grade the outcome; reverse if worse','cpo','recommend',null),

 ('budget_cycle',1,'Set monthly budget per department','cfo','forecast','authority'),
 ('budget_cycle',2,'Meter every AI call to a department','optimisation_eng','recommend',null),
 ('budget_cycle',3,'Degrade to cheaper tiers at the threshold','optimisation_eng','recommend','authority'),
 ('budget_cycle',4,'Halt non-critical spend at the ceiling','cfo','money_verify','authority'),
 ('budget_cycle',5,'Review variance and reset next month','financial_analyst','forecast',null),

 ('contract_review',1,'Intake and classify the document','contract_specialist','legal_review',null),
 ('contract_review',2,'Risk classification against the register','risk_governance_mgr','security_review',null),
 ('contract_review',3,'Clause review against policy','legal','legal_review','review'),
 ('contract_review',4,'Escalate anything outside authority','legal','escalate_founder','authority'),
 ('contract_review',5,'Approve and record the decision','legal','legal_review','authority'),
 ('contract_review',6,'Archive with retention applied','compliance_mgr','pdpl_action',null),

 ('knowledge_lifecycle',1,'Acquire from a cited external source','market_analyst','knowledge_acquire',null),
 ('knowledge_lifecycle',2,'Chunk, embed and index for retrieval','kb_engineer','knowledge_fill',null),
 ('knowledge_lifecycle',3,'Validate against an independent source','knowledge_validator','capability_exam','review'),
 ('knowledge_lifecycle',4,'Publish with confidence and a review date','knowledge_director','knowledge_fill','authority'),
 ('knowledge_lifecycle',5,'Serve through retrieval to every employee','kb_engineer','knowledge_fill',null),
 ('knowledge_lifecycle',6,'Decay confidence past the review date','knowledge_validator','knowledge_fill_gap',null),
 ('knowledge_lifecycle',7,'Re-validate or quarantine below the floor','knowledge_director','knowledge_fill','review'),

 ('metric_lifecycle',1,'Define the metric and why it matters','intel_director','recommend',null),
 ('metric_lifecycle',2,'Instrument it with a measure that runs','intel_director','health_report',null),
 ('metric_lifecycle',3,'Measure on cadence and record the actual','forecast_analyst','forecast',null),
 ('metric_lifecycle',4,'Detect variance against target','cpo','recommend',null),
 ('metric_lifecycle',5,'Root cause: is it the work or the target?','cpo','recommend','review'),
 ('metric_lifecycle',6,'Revise the metric or retire it','intel_director','recommend','authority'),

 ('improvement_lifecycle',1,'Detect a weakness from data, not opinion','cpo','recommend',null),
 ('improvement_lifecycle',2,'Root cause before proposing anything','innovation_mgr','recommend',null),
 ('improvement_lifecycle',3,'Propose with a named metric and a captured baseline','innovation_mgr','recommend',null),
 ('improvement_lifecycle',4,'Approve within authority or escalate','cpo','exec_review','authority'),
 ('improvement_lifecycle',5,'Execute the change','optimisation_eng','recommend',null),
 ('improvement_lifecycle',6,'Grade against the baseline after the window','cpo','recommend','review'),
 ('improvement_lifecycle',7,'Promote if better, roll back if worse','cpo','recommend','authority'),
 ('improvement_lifecycle',8,'Write the lesson either way','knowledge_director','knowledge_fill',null)
on conflict do nothing;

-- bind every named actor to the workflow they appear in
insert into employee_workflow (agent_key, workflow_key, role_in_workflow)
select distinct s.actor_role, s.workflow_key, 'step actor'
from workflow_step s
join org_agents a on a.agent_key = s.actor_role and a.active
where not exists (select 1 from employee_workflow e where e.agent_key=s.actor_role and e.workflow_key=s.workflow_key);