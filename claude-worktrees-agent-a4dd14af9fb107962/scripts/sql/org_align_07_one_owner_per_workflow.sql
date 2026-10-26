-- ORG ALIGNMENT 07 — one accountable owner per workflow, and the registry present on both projects.
--
-- TWO MEASURED DEFECTS.
--
-- 1. employee_workflow holds 157 rows on PRODUCTION and 0 on STAGING. workflow_step matches
--    (184/184) and org_role matches (177/177), so this is one table that never made the trip. The
--    consequence is not cosmetic: the ownership check passes on production and fails on staging
--    for 15 roles, which means staging and production disagree about who owns what. Every row is
--    re-inserted here idempotently, so this is a no-op on production and a repair on staging.
--
-- 2. TEN AGENTS WERE RECORDED AS THE "owner" OF rfq_handling, and ten of supplier_onboarding, and
--    five of invoice_approval, and six of campaign_publishing. "Every workflow has one accountable
--    owner" was not true of any of them. Now that workflow_step carries real step-level ownership,
--    a second registry naming ten owners is not extra detail — it is a contradicting source of
--    truth, and the next reader has to guess which one counts.
--
--    THE ONE EXCEPTION, DELIBERATE: employee_task has 43 owners and keeps them. It is the generic
--    per-employee task loop — every employee owns their OWN instance of it — so "one owner" would
--    be meaningless there. Its steps bind 'owner' per run, and 2,901 step runs prove they do.
--    EXISTING_BETTER_KEEP.

begin;

insert into employee_workflow (agent_key, workflow_key, role_in_workflow) values
  ('account_mgr','employee_task','owner'),
  ('account_mgr','lead_to_customer','step actor'),
  ('ai_architect','employee_task','owner'),
  ('analytics','employee_task','owner'),
  ('ap_specialist','employee_task','owner'),
  ('ap_specialist','invoice_approval','owner'),
  ('backend_engineer','employee_task','owner'),
  ('backend_engineer','incident_response','step actor'),
  ('bd','employee_task','owner'),
  ('bookkeeper','employee_task','owner'),
  ('bookkeeper','invoice_approval','owner'),
  ('brand_mgr','campaign_publishing','owner'),
  ('brand_mgr','employee_task','owner'),
  ('brand_mgr','lead_to_customer','step actor'),
  ('brief','campaign_publishing','approver'),
  ('brief','employee_task','approver'),
  ('brief','strategic_review','step actor'),
  ('ceo','campaign_publishing','approver'),
  ('ceo','employee_task','approver'),
  ('ceo','strategic_review','step actor'),
  ('cfo','budget_cycle','step actor'),
  ('cfo','employee_task','approver'),
  ('cfo','invoice_approval','owner'),
  ('collections','employee_task','owner'),
  ('collections','invoice_approval','owner'),
  ('compliance_mgr','contract_review','step actor'),
  ('compliance_mgr','employee_task','owner'),
  ('compliance_mgr','invoice_approval','reviewer'),
  ('compliance_mgr','supplier_onboarding','reviewer'),
  ('contract_specialist','contract_review','step actor'),
  ('contract_specialist','employee_task','owner'),
  ('contract_specialist','invoice_approval','reviewer'),
  ('contract_specialist','supplier_onboarding','reviewer'),
  ('cpo','change_deployment','step actor'),
  ('cpo','improvement_lifecycle','step actor'),
  ('cpo','metric_lifecycle','step actor'),
  ('cpo','strategic_review','step actor'),
  ('crm_pipeline_mgr','employee_task','owner'),
  ('crm_pipeline_mgr','lead_to_customer','step actor'),
  ('cs_onboarding','employee_task','owner'),
  ('cs_onboarding','lead_to_customer','step actor'),
  ('cs_onboarding','rfq_handling','participant'),
  ('cs_retention','employee_task','owner'),
  ('cs_retention','rfq_handling','participant'),
  ('cs_support','employee_task','owner'),
  ('cs_support','rfq_handling','participant'),
  ('cto','change_deployment','step actor'),
  ('cto','employee_task','approver'),
  ('cto','incident_response','step actor'),
  ('culture_performance_mgr','employee_task','owner'),
  ('docs','employee_task','owner'),
  ('docs','rfq_handling','participant'),
  ('financial_analyst','budget_cycle','step actor'),
  ('financial_analyst','employee_task','owner'),
  ('financial_analyst','invoice_approval','owner'),
  ('followup','employee_task','approver'),
  ('followup','rfq_handling','participant'),
  ('forecast_analyst','metric_lifecycle','step actor'),
  ('frontend_engineer','change_deployment','step actor'),
  ('frontend_engineer','employee_task','owner'),
  ('hr_director','employee_task','approver'),
  ('innovation_mgr','improvement_lifecycle','step actor'),
  ('intel_director','metric_lifecycle','step actor'),
  ('intel_director','strategic_review','step actor'),
  ('it','employee_task','owner'),
  ('it','incident_response','step actor'),
  ('kb_engineer','knowledge_lifecycle','step actor'),
  ('knowledge_director','improvement_lifecycle','step actor'),
  ('knowledge_director','incident_response','step actor'),
  ('knowledge_director','knowledge_lifecycle','step actor'),
  ('knowledge_validator','knowledge_lifecycle','step actor'),
  ('learning_dev_mgr','employee_task','owner'),
  ('legal','contract_review','step actor'),
  ('legal','employee_task','approver'),
  ('legal','invoice_approval','reviewer'),
  ('legal','supplier_onboarding','reviewer'),
  ('market_analyst','knowledge_lifecycle','step actor'),
  ('marketing','campaign_publishing','owner'),
  ('marketing','employee_task','approver'),
  ('marketing_analyst','campaign_publishing','owner'),
  ('marketing_analyst','employee_task','owner'),
  ('marketing_content','campaign_publishing','owner'),
  ('marketing_content','employee_task','owner'),
  ('marketing_design','campaign_publishing','owner'),
  ('marketing_design','employee_task','owner'),
  ('marketing_social','campaign_publishing','owner'),
  ('marketing_social','employee_task','owner'),
  ('onboarding','employee_task','owner'),
  ('onboarding','invoice_approval','reviewer'),
  ('onboarding','rfq_handling','owner'),
  ('onboarding','supplier_onboarding','owner'),
  ('ops_director','employee_task','approver'),
  ('ops_director','incident_response','step actor'),
  ('ops_director','rfq_handling','participant'),
  ('optimisation_eng','budget_cycle','step actor'),
  ('optimisation_eng','change_deployment','step actor'),
  ('optimisation_eng','improvement_lifecycle','step actor'),
  ('partnerships_mgr','employee_task','owner'),
  ('process_improvement_mgr','employee_task','owner'),
  ('process_improvement_mgr','rfq_handling','participant'),
  ('procurement','employee_task','approver'),
  ('procurement','invoice_approval','reviewer'),
  ('procurement','rfq_handling','owner'),
  ('procurement','supplier_onboarding','owner'),
  ('project_coordinator','employee_task','owner'),
  ('project_coordinator','rfq_handling','participant'),
  ('qa_manager','change_deployment','step actor'),
  ('qa_manager','employee_task','owner'),
  ('qa_manager','rfq_handling','participant'),
  ('quote_evaluation','employee_task','owner'),
  ('quote_evaluation','invoice_approval','reviewer'),
  ('quote_evaluation','rfq_handling','owner'),
  ('quote_evaluation','supplier_onboarding','owner'),
  ('recruitment_specialist','employee_task','owner'),
  ('rfq_qualification_mgr','employee_task','owner'),
  ('rfq_qualification_mgr','invoice_approval','reviewer'),
  ('rfq_qualification_mgr','rfq_handling','owner'),
  ('rfq_qualification_mgr','supplier_onboarding','owner'),
  ('rfq_success','employee_task','owner'),
  ('rfq_success','rfq_handling','participant'),
  ('risk_governance_mgr','contract_review','step actor'),
  ('risk_governance_mgr','employee_task','owner'),
  ('risk_governance_mgr','invoice_approval','reviewer'),
  ('risk_governance_mgr','supplier_onboarding','reviewer'),
  ('sales_director','employee_task','approver'),
  ('sales_director','lead_to_customer','step actor'),
  ('security','employee_task','owner'),
  ('security','incident_response','step actor'),
  ('solution_architect','change_deployment','step actor'),
  ('solution_architect','employee_task','owner'),
  ('spec_commercial','employee_task','owner'),
  ('spec_commercial','invoice_approval','reviewer'),
  ('spec_commercial','rfq_handling','owner'),
  ('spec_commercial','supplier_onboarding','owner'),
  ('spec_construction','employee_task','owner'),
  ('spec_construction','invoice_approval','reviewer'),
  ('spec_construction','rfq_handling','owner'),
  ('spec_construction','supplier_onboarding','owner'),
  ('spec_fitout','employee_task','owner'),
  ('spec_fitout','invoice_approval','reviewer'),
  ('spec_fitout','rfq_handling','owner'),
  ('spec_fitout','supplier_onboarding','owner'),
  ('spec_industrial','employee_task','owner'),
  ('spec_industrial','invoice_approval','reviewer'),
  ('spec_industrial','rfq_handling','owner'),
  ('spec_industrial','supplier_onboarding','owner'),
  ('spec_mep','employee_task','owner'),
  ('spec_mep','invoice_approval','reviewer'),
  ('spec_mep','rfq_handling','owner'),
  ('spec_mep','supplier_onboarding','owner'),
  ('strategy_director','campaign_publishing','approver'),
  ('strategy_director','employee_task','approver'),
  ('strategy_director','strategic_review','step actor'),
  ('supplier_verification','employee_task','owner'),
  ('supplier_verification','invoice_approval','reviewer'),
  ('supplier_verification','rfq_handling','owner'),
  ('supplier_verification','supplier_onboarding','owner')
on conflict (agent_key, workflow_key) do nothing;
-- ---------------------------------------------------------------------------------------------
-- Collapse to one accountable owner per workflow. Everyone else keeps their seat as a participant
-- rather than being deleted: they DO take part, and removing them would lose that.
-- ---------------------------------------------------------------------------------------------
update employee_workflow set role_in_workflow = 'participant'
 where role_in_workflow = 'owner'
   and workflow_key <> 'employee_task'
   and (workflow_key, agent_key) not in (
     values ('rfq_handling',        'procurement'),      -- Marketplace Director
            ('supplier_onboarding', 'onboarding'),       -- Supplier Onboarding Specialist
            ('invoice_approval',    'cfo'),              -- Chief Financial Officer
            ('campaign_publishing', 'marketing')         -- Marketing Director
   );

-- The four accountable owners must actually hold the row. If an owner above was never recorded as
-- a participant either, this inserts it rather than leaving the workflow ownerless.
insert into employee_workflow (agent_key, workflow_key, role_in_workflow) values
  ('procurement', 'rfq_handling',        'owner'),
  ('onboarding',  'supplier_onboarding', 'owner'),
  ('cfo',         'invoice_approval',    'owner'),
  ('marketing',   'campaign_publishing', 'owner')
on conflict (agent_key, workflow_key) do update set role_in_workflow = 'owner';

-- ---------------------------------------------------------------------------------------------
-- handoff_stalled exists on staging and not on production: a tool one project's agents can call
-- and the other's cannot. Nothing is left on staging.
-- ---------------------------------------------------------------------------------------------
insert into agent_tool (tool_id,purpose,kind,action_class,impl_kind,impl_target,authorised_roles,
  authorised_departments,min_authority,required_credential,staging_available,production_available,
  input_schema,output_schema,timeout_seconds,max_attempts,backoff,failure_behaviour,audit_behaviour,
  requires_current_data,stub_permitted,active,note)
values ('handoff_stalled',
  'Cross-department handoffs that have stopped moving: past deadline, accepted and never closed, handed back and never corrected, or owned by someone who has left. Each row names one accountable owner.',
  'read',NULL,'rpc','fn_handoff_stalled','{*}'::text[],'{*}'::text[],'advisory',NULL,true,false,
  '{"type": "object", "properties": {"dept": {"type": "string"}, "limit": {"type": "integer", "maximum": 200, "minimum": 1}}, "additionalProperties": false}'::jsonb,
  '{"type": "object"}'::jsonb,15,2,'exponential_2s','fail_closed','trace',true,false,true,
  'Empty is the correct answer most days; an empty result here is ok_empty, never a failure.')
on conflict (tool_id) do nothing;

commit;
