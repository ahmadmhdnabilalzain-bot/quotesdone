-- PHASE C — THE FOUNDER-APPROVED REPORTING MAP BECOMES A CHECKABLE SUBJECT, AND THE
-- ORGANISATION IS RECONCILED TO IT.
--
-- On 16 Aug 2026 the founder delivered QuotesDone_PHASE_C_REPORTING_AND_CHAIN_OF_COMMAND_MAP
-- v2026.08.16 and instructed: treat it as the founder-approved primary reporting structure,
-- reconcile the repository and production database against the exact map, correct only confirmed
-- mismatches, and do not redesign the 10 departments, 90 standing roles or 86 category overlays.
--
-- WHAT THE MEASUREMENT FOUND, AND WHY NOTHING HAD CAUGHT IT.
-- fn_phase_a_organization_violations() returned 0 rows and fn_phase_c_invariants() returned 58
-- checks all true while 26 of the 90 standing roles reported to the wrong manager or carried the
-- wrong class. Neither instrument was wrong about what it measured; both measure PROPERTIES of the
-- graph — every role has a manager, the manager is active, there is no cycle, no self-management,
-- no duplicate identity — and neither had the founder's map as a subject to compare against. A
-- graph can satisfy every structural property and still be the wrong graph. That is the defect this
-- file closes: phase_c_reporting_authority gives the map a home in the database, and
-- fn_phase_c_reporting_map_drift() compares the live organisation against it, field by field.
--
-- THIS IS A CHANGE, NOT A DRIFT REPAIR — SAID PLAINLY.
-- docs/phase-a/PHASE_A_REPORTING_GRAPH.csv, approved 15 Aug, agrees with the live database on all
-- 23 manager edges this file moves. The database did not wander; it faithfully implemented the
-- 15 Aug baseline. The 16 Aug package supersedes it. So this is a Phase A change request carrying
-- the founder's own map as its evidence, stated as PACR-001 in the same transaction rather than
-- slipped past a guard that only counts rows.
--
-- The three substantive corrections:
--   1. Eight department heads reported to chief_of_staff. The map puts all nine heads under the AI
--      CEO, with the Chief of Staff a peer who carries founder commands rather than a link in the
--      normal management chain. org_role.manager_role_id is not decoration: fn_phase_c_task_create
--      stamps it onto every task it creates, and fn_founder_command_submit routes through it.
--   2. Two independent reviewers reported to the manager whose work they review — knowledge_validator
--      under knowledge_director, whose curator and taxonomy manager it validates, and
--      marketplace_content_privacy_reviewer under trust_and_safety_manager. Reviewer independence is
--      not a property you can assert while the reviewer's own appraisal sits with the reviewed.
--   3. Three roles that each manage a standing team — ai_director (2 reports), engineering_manager
--      (3), agent_workforce_capability_director (4) — were classed on_demand_specialist. A specialist
--      summoned on demand cannot hold a standing team; the map classes all three event-driven
--      operators, and the class is what fn_phase_c_resolve_actor and fn_pick_reviewer read.
--
-- AND THE OVERLAYS. All 86 carried the identical escalation pair {inquiry_router, marketplace_director}
-- and not one named the broad-domain specialist its registry entry assigns. The four domain
-- specialists exist as standing roles and no overlay pointed at any of them, so for 51 of the 86 the
-- broad-domain escalation could never be reached. The escalation is ADDED rather than swapped:
-- fn_agent_context_v3 and fn_role_handoff read this column, and removing a live path to fix a
-- missing one trades one defect for another.
--
-- Overlay AUTHORITY was already correct and is left alone — fn_phase_c_authority_check refuses an
-- overlay for every action class ("resolves to overlay and may not act"), and the phase_c_task
-- trigger refuses an overlay owner; both were proved by execution before this file was written.
-- What was missing was the overlay SAYING it cannot move money, while its own necessity_reason
-- listed six other things it cannot decide. The declaration is brought level with the enforcement.

begin;

set local app.phase_a_change_reason =
  'PACR-001: reporting map reconciliation. Finding: 26 of 90 standing roles carried a manager or '
  'class contradicting the founder-approved QuotesDone Reporting and Chain-of-Command Map '
  'v2026.08.16, and 86 of 86 category overlays carried no broad-domain escalation. Evidence: the '
  'package ROLE_REPORTING_MAP.csv, ROLE_REPORTING_TREE.json and CATEGORY_OVERLAY_REPORTING_MAP.csv, '
  'verified internally consistent across all five files, both source registries, the department '
  'summary and the nested tree before any change was made. Approver: founder, 16 Aug 2026 — '
  '"Treat these files as the founder-approved primary reporting structure for QuotesDone."';

-- ================================================================================================
-- 1. THE MAP GETS A HOME. Without a recorded authority there is nothing for a check to compare the
--    organisation against, which is exactly how 26 wrong edges sat under a green invariant board.
-- ================================================================================================
create table if not exists public.phase_c_reporting_authority (
  canonical_role_id       text primary key,
  live_role_id            text not null references public.org_role(role_id),
  department_id           text not null references public.org_departments(dept_key),
  manager_role_id         text not null,
  role_class              text not null check (role_class in ('H','O','S','R')),
  runtime_mode            text not null,
  department_head_role_id text not null,
  reporting_path          text not null,
  source_package          text not null default 'QuotesDone_PHASE_C_REPORTING_AND_CHAIN_OF_COMMAND_MAP_v2026.08.16',
  recorded_at             timestamptz not null default now()
);
comment on table public.phase_c_reporting_authority is
  'The founder-approved primary reporting structure: 90 standing roles, package v2026.08.16. '
  'canonical_role_id is the name the package uses; live_role_id is the org_role it resolves to '
  'through org_role_alias. This table is the SUBJECT that fn_phase_c_reporting_map_drift() compares '
  'the live organisation against. It is not a second source of truth for runtime — org_role remains '
  'that — it is the authority the runtime is measured against.';

delete from public.phase_c_reporting_authority;
insert into public.phase_c_reporting_authority
  (canonical_role_id, live_role_id, department_id, manager_role_id, role_class, runtime_mode,
   department_head_role_id, reporting_path)
values
  ('ceo','ceo','exec','founder','H','scheduled_manager','ceo','ceo > founder'),
  ('chief_of_staff','chief_of_staff','exec','ceo','H','scheduled_manager','ceo','chief_of_staff > ceo > founder'),
  ('corporate_performance_director','corporate_performance_director','exec','ceo','H','scheduled_manager','ceo','corporate_performance_director > ceo > founder'),
  ('strategy_director','strategy_director','exec','ceo','S','on_demand_specialist','ceo','strategy_director > ceo > founder'),
  ('marketplace_director','marketplace_director','marketplace','ceo','H','scheduled_manager','marketplace_director','marketplace_director > ceo > founder'),
  ('supplier_verification_reviewer','supplier_verification','marketplace','marketplace_director','R','independent_reviewer','marketplace_director','supplier_verification > marketplace_director > ceo > founder'),
  ('rfq_qualification_manager','rfq_qualification_manager','marketplace','marketplace_director','O','event_driven_operator','marketplace_director','rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('inquiry_router','inquiry_router','marketplace','rfq_qualification_manager','O','event_driven_operator','marketplace_director','inquiry_router > rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('inquiry_quality_scoring_analyst','inquiry_quality_analyst','marketplace','rfq_qualification_manager','O','event_driven_operator','marketplace_director','inquiry_quality_analyst > rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('quote_evaluation_specialist','quote_evaluation','marketplace','marketplace_director','O','event_driven_operator','marketplace_director','quote_evaluation > marketplace_director > ceo > founder'),
  ('supplier_onboarding_specialist','supplier_onboarding_specialist','marketplace','marketplace_director','O','event_driven_operator','marketplace_director','supplier_onboarding_specialist > marketplace_director > ceo > founder'),
  ('document_intelligence_manager','document_intelligence_manager','marketplace','marketplace_director','O','event_driven_operator','marketplace_director','document_intelligence_manager > marketplace_director > ceo > founder'),
  ('boq_specification_analyst','boq_analyst','marketplace','document_intelligence_manager','S','on_demand_specialist','marketplace_director','boq_analyst > document_intelligence_manager > marketplace_director > ceo > founder'),
  ('drawing_cad_analyst','drawing_analyst','marketplace','document_intelligence_manager','S','on_demand_specialist','marketplace_director','drawing_analyst > document_intelligence_manager > marketplace_director > ceo > founder'),
  ('mep_domain_specialist','spec_mep','marketplace','rfq_qualification_manager','S','on_demand_specialist','marketplace_director','spec_mep > rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('construction_civil_domain_specialist','spec_construction','marketplace','rfq_qualification_manager','S','on_demand_specialist','marketplace_director','spec_construction > rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('interior_fitout_domain_specialist','spec_fitout','marketplace','rfq_qualification_manager','S','on_demand_specialist','marketplace_director','spec_fitout > rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('industrial_energy_domain_specialist','spec_industrial','marketplace','rfq_qualification_manager','S','on_demand_specialist','marketplace_director','spec_industrial > rfq_qualification_manager > marketplace_director > ceo > founder'),
  ('supplier_matching_dispatch_operator','supplier_matching_dispatch_operator','marketplace','marketplace_director','O','event_driven_operator','marketplace_director','supplier_matching_dispatch_operator > marketplace_director > ceo > founder'),
  ('supplier_coverage_liquidity_specialist','supplier_coverage','marketplace','marketplace_director','S','on_demand_specialist','marketplace_director','supplier_coverage > marketplace_director > ceo > founder'),
  ('supplier_retention_specialist','supplier_retention','marketplace','marketplace_director','S','on_demand_specialist','marketplace_director','supplier_retention > marketplace_director > ceo > founder'),
  ('chief_revenue_officer','chief_revenue_officer','growth','ceo','H','scheduled_manager','chief_revenue_officer','chief_revenue_officer > ceo > founder'),
  ('marketing_director','marketing_director','growth','chief_revenue_officer','O','event_driven_operator','chief_revenue_officer','marketing_director > chief_revenue_officer > ceo > founder'),
  ('brand_creative_manager','brand_and_creative','growth','marketing_director','O','event_driven_operator','chief_revenue_officer','brand_and_creative > marketing_director > chief_revenue_officer > ceo > founder'),
  ('business_development_manager','business_development','growth','chief_revenue_officer','O','event_driven_operator','chief_revenue_officer','business_development > chief_revenue_officer > ceo > founder'),
  ('crm_revenue_operations_manager','crm_and_revenue_operations','growth','chief_revenue_officer','O','event_driven_operator','chief_revenue_officer','crm_and_revenue_operations > chief_revenue_officer > ceo > founder'),
  ('marketing_performance_analyst','marketing_performance_analyst','growth','marketing_director','O','event_driven_operator','chief_revenue_officer','marketing_performance_analyst > marketing_director > chief_revenue_officer > ceo > founder'),
  ('social_media_community_manager','social_media_and_community','growth','marketing_director','O','event_driven_operator','chief_revenue_officer','social_media_and_community > marketing_director > chief_revenue_officer > ceo > founder'),
  ('account_manager','account_management','growth','chief_revenue_officer','S','on_demand_specialist','chief_revenue_officer','account_management > chief_revenue_officer > ceo > founder'),
  ('content_strategy_copy_specialist','content_strategy_and_copy','growth','marketing_director','S','on_demand_specialist','chief_revenue_officer','content_strategy_and_copy > marketing_director > chief_revenue_officer > ceo > founder'),
  ('visual_design_specialist','visual_design','growth','brand_and_creative','S','on_demand_specialist','chief_revenue_officer','visual_design > brand_and_creative > marketing_director > chief_revenue_officer > ceo > founder'),
  ('strategic_partnerships_government_relations_manager','strategic_partnerships_government_relations_manager','growth','chief_revenue_officer','S','on_demand_specialist','chief_revenue_officer','strategic_partnerships_government_relations_manager > chief_revenue_officer > ceo > founder'),
  ('data_intelligence_director','data_intelligence_director','data_intel','ceo','H','scheduled_manager','data_intelligence_director','data_intelligence_director > ceo > founder'),
  ('knowledge_validator','knowledge_validator','data_intel','data_intelligence_director','R','independent_reviewer','data_intelligence_director','knowledge_validator > data_intelligence_director > ceo > founder'),
  ('knowledge_director','knowledge_director','data_intel','data_intelligence_director','O','event_driven_operator','data_intelligence_director','knowledge_director > data_intelligence_director > ceo > founder'),
  ('knowledge_engineer','knowledge_engineer','data_intel','knowledge_director','O','event_driven_operator','data_intelligence_director','knowledge_engineer > knowledge_director > data_intelligence_director > ceo > founder'),
  ('category_knowledge_curator','category_curator','data_intel','knowledge_director','O','event_driven_operator','data_intelligence_director','category_curator > knowledge_director > data_intelligence_director > ceo > founder'),
  ('business_intelligence_analyst','business_intelligence_analyst','data_intel','data_intelligence_director','S','on_demand_specialist','data_intelligence_director','business_intelligence_analyst > data_intelligence_director > ceo > founder'),
  ('data_engineer','data_engineer','data_intel','data_intelligence_director','S','on_demand_specialist','data_intelligence_director','data_engineer > data_intelligence_director > ceo > founder'),
  ('forecasting_analyst','forecasting_analyst','data_intel','data_intelligence_director','S','on_demand_specialist','data_intelligence_director','forecasting_analyst > data_intelligence_director > ceo > founder'),
  ('market_intelligence_analyst','market_intelligence_analyst','data_intel','data_intelligence_director','S','on_demand_specialist','data_intelligence_director','market_intelligence_analyst > data_intelligence_director > ceo > founder'),
  ('supplier_intelligence_analyst','supplier_intelligence_analyst','data_intel','data_intelligence_director','S','on_demand_specialist','data_intelligence_director','supplier_intelligence_analyst > data_intelligence_director > ceo > founder'),
  ('taxonomy_governance_manager','taxonomy_manager','data_intel','knowledge_director','S','on_demand_specialist','data_intelligence_director','taxonomy_manager > knowledge_director > data_intelligence_director > ceo > founder'),
  ('chief_product_technology_officer','cto','product_eng','ceo','H','scheduled_manager','cto','cto > ceo > founder'),
  ('product_manager','product_manager','product_eng','cto','O','event_driven_operator','cto','product_manager > cto > ceo > founder'),
  ('product_ux_designer','product_ux_designer','product_eng','product_manager','S','on_demand_specialist','cto','product_ux_designer > product_manager > cto > ceo > founder'),
  ('product_optimisation_engineer','product_optimization_engineer','product_eng','cto','O','event_driven_operator','cto','product_optimization_engineer > cto > ceo > founder'),
  ('ai_director','ai_director','product_eng','cto','O','event_driven_operator','cto','ai_director > cto > ceo > founder'),
  ('ai_architect','ai_architect','product_eng','ai_director','S','on_demand_specialist','cto','ai_architect > ai_director > cto > ceo > founder'),
  ('agent_prompt_engineer','prompt_engineer','product_eng','ai_director','S','on_demand_specialist','cto','prompt_engineer > ai_director > cto > ceo > founder'),
  ('solution_architect','solution_architect','product_eng','cto','S','on_demand_specialist','cto','solution_architect > cto > ceo > founder'),
  ('engineering_manager','engineering_manager','product_eng','cto','O','event_driven_operator','cto','engineering_manager > cto > ceo > founder'),
  ('backend_engineer','backend_engineer','product_eng','engineering_manager','S','on_demand_specialist','cto','backend_engineer > engineering_manager > cto > ceo > founder'),
  ('frontend_engineer','frontend_engineer','product_eng','engineering_manager','S','on_demand_specialist','cto','frontend_engineer > engineering_manager > cto > ceo > founder'),
  ('cfo','cfo','finance','ceo','H','scheduled_manager','cfo','cfo > ceo > founder'),
  ('financial_controller','financial_controller','finance','cfo','O','event_driven_operator','cfo','financial_controller > cfo > ceo > founder'),
  ('payments_billing_manager','payments_and_billing_manager','finance','cfo','O','event_driven_operator','cfo','payments_and_billing_manager > cfo > ceo > founder'),
  ('billing_reconciliation_specialist','billing_operations','finance','financial_controller','O','event_driven_operator','cfo','billing_operations > financial_controller > cfo > ceo > founder'),
  ('accounts_payable_specialist','accounts_payable','finance','financial_controller','O','event_driven_operator','cfo','accounts_payable > financial_controller > cfo > ceo > founder'),
  ('collections_revenue_assurance_specialist','collections_and_revenue_assurance','finance','financial_controller','O','event_driven_operator','cfo','collections_and_revenue_assurance > financial_controller > cfo > ceo > founder'),
  ('fp_a_analyst','fpna_analyst','finance','cfo','S','on_demand_specialist','cfo','fpna_analyst > cfo > ceo > founder'),
  ('general_counsel','general_counsel','legal','ceo','H','scheduled_manager','general_counsel','general_counsel > ceo > founder'),
  ('compliance_privacy_officer','compliance_and_privacy_officer','legal','general_counsel','R','independent_reviewer','general_counsel','compliance_and_privacy_officer > general_counsel > ceo > founder'),
  ('risk_governance_manager','risk_and_governance_manager','legal','general_counsel','R','independent_reviewer','general_counsel','risk_and_governance_manager > general_counsel > ceo > founder'),
  ('fraud_reviewer','fraud_analyst','legal','trust_and_safety_manager','R','independent_reviewer','general_counsel','fraud_analyst > trust_and_safety_manager > general_counsel > ceo > founder'),
  ('marketplace_content_privacy_reviewer','marketplace_content_privacy_reviewer','legal','compliance_and_privacy_officer','R','independent_reviewer','general_counsel','marketplace_content_privacy_reviewer > compliance_and_privacy_officer > general_counsel > ceo > founder'),
  ('trust_safety_manager','trust_and_safety_manager','legal','general_counsel','O','event_driven_operator','general_counsel','trust_and_safety_manager > general_counsel > ceo > founder'),
  ('contract_manager','contract_manager','legal','general_counsel','S','on_demand_specialist','general_counsel','contract_manager > general_counsel > ceo > founder'),
  ('customer_success_director','customer_success_director','customer_experience','ceo','H','scheduled_manager','customer_success_director','customer_success_director > ceo > founder'),
  ('communications_manager','communications_manager','customer_experience','customer_success_director','O','event_driven_operator','customer_success_director','communications_manager > customer_success_director > ceo > founder'),
  ('customer_onboarding_specialist','customer_onboarding','customer_experience','customer_success_director','O','event_driven_operator','customer_success_director','customer_onboarding > customer_success_director > ceo > founder'),
  ('customer_support_specialist','customer_support','customer_experience','customer_success_director','O','event_driven_operator','customer_success_director','customer_support > customer_success_director > ceo > founder'),
  ('customer_retention_specialist','customer_retention','customer_experience','customer_success_director','O','event_driven_operator','customer_success_director','customer_retention > customer_success_director > ceo > founder'),
  ('rfq_success_specialist','rfq_success','customer_experience','customer_success_director','O','event_driven_operator','customer_success_director','rfq_success > customer_success_director > ceo > founder'),
  ('lifecycle_channel_operations_specialist','lifecycle_channel_operations','customer_experience','communications_manager','O','event_driven_operator','customer_success_director','lifecycle_channel_operations > communications_manager > customer_success_director > ceo > founder'),
  ('coo','chief_operating_officer','people_ops','ceo','H','scheduled_manager','chief_operating_officer','chief_operating_officer > ceo > founder'),
  ('process_improvement_manager','process_improvement_manager','people_ops','chief_operating_officer','O','event_driven_operator','chief_operating_officer','process_improvement_manager > chief_operating_officer > ceo > founder'),
  ('project_coordinator_pmo','project_coordinator','people_ops','chief_operating_officer','O','event_driven_operator','chief_operating_officer','project_coordinator > chief_operating_officer > ceo > founder'),
  ('document_operations_specialist','document_operations_specialist','people_ops','chief_operating_officer','O','event_driven_operator','chief_operating_officer','document_operations_specialist > chief_operating_officer > ceo > founder'),
  ('agent_workforce_capability_director','agent_workforce_capability_director','people_ops','chief_operating_officer','O','event_driven_operator','chief_operating_officer','agent_workforce_capability_director > chief_operating_officer > ceo > founder'),
  ('culture_performance_manager','culture_and_performance_manager','people_ops','agent_workforce_capability_director','S','on_demand_specialist','chief_operating_officer','culture_and_performance_manager > agent_workforce_capability_director > chief_operating_officer > ceo > founder'),
  ('learning_development_manager','learning_and_development_manager','people_ops','agent_workforce_capability_director','S','on_demand_specialist','chief_operating_officer','learning_and_development_manager > agent_workforce_capability_director > chief_operating_officer > ceo > founder'),
  ('recruitment_specialist','recruitment_specialist','people_ops','agent_workforce_capability_director','S','on_demand_specialist','chief_operating_officer','recruitment_specialist > agent_workforce_capability_director > chief_operating_officer > ceo > founder'),
  ('organisation_design_lead','organization_designer','people_ops','agent_workforce_capability_director','S','on_demand_specialist','chief_operating_officer','organization_designer > agent_workforce_capability_director > chief_operating_officer > ceo > founder'),
  ('qa_release_management_director','quality_and_release_director','assurance','ceo','H','scheduled_manager','quality_and_release_director','quality_and_release_director > ceo > founder'),
  ('cybersecurity_engineer','cybersecurity_engineer','assurance','quality_and_release_director','R','independent_reviewer','quality_and_release_director','cybersecurity_engineer > quality_and_release_director > ceo > founder'),
  ('ai_quality_assurance_reviewer','ai_quality_reviewer','assurance','quality_and_release_director','R','independent_reviewer','quality_and_release_director','ai_quality_reviewer > quality_and_release_director > ceo > founder'),
  ('model_evaluation_reviewer','model_evaluator','assurance','quality_and_release_director','R','independent_reviewer','quality_and_release_director','model_evaluator > quality_and_release_director > ceo > founder'),
  ('test_automation_engineer','test_automation_engineer','assurance','quality_and_release_director','O','event_driven_operator','quality_and_release_director','test_automation_engineer > quality_and_release_director > ceo > founder'),
  ('it_operations_site_reliability_engineer','it_operations_engineer','assurance','quality_and_release_director','O','event_driven_operator','quality_and_release_director','it_operations_engineer > quality_and_release_director > ceo > founder');

-- the overlay half of the authority: the one governance field no live column carried
alter table public.phase_c_overlay_binding
  add column if not exists broad_domain_escalation_role_id text;

update public.phase_c_overlay_binding b
   set broad_domain_escalation_role_id = v.esc
  from (values
  ('opcat-001','spec_construction'),
  ('opcat-002','spec_construction'),
  ('opcat-003','spec_construction'),
  ('opcat-004','spec_construction'),
  ('opcat-005','spec_construction'),
  ('opcat-006','spec_construction'),
  ('opcat-007','spec_construction'),
  ('opcat-008','spec_mep'),
  ('opcat-009','spec_mep'),
  ('opcat-010','spec_mep'),
  ('opcat-011','spec_mep'),
  ('opcat-012','spec_mep'),
  ('opcat-013','spec_mep'),
  ('opcat-014','spec_mep'),
  ('opcat-015','spec_mep'),
  ('opcat-016','spec_fitout'),
  ('opcat-017','spec_fitout'),
  ('opcat-018','spec_fitout'),
  ('opcat-019','spec_fitout'),
  ('opcat-020','spec_fitout'),
  ('opcat-021','spec_fitout'),
  ('opcat-022','spec_fitout'),
  ('opcat-023','spec_fitout'),
  ('opcat-024','spec_fitout'),
  ('opcat-025','spec_mep'),
  ('opcat-026','spec_mep'),
  ('opcat-027','rfq_qualification_manager'),
  ('opcat-028','rfq_qualification_manager'),
  ('opcat-029','spec_industrial'),
  ('opcat-030','spec_industrial'),
  ('opcat-031','rfq_qualification_manager'),
  ('opcat-032','rfq_qualification_manager'),
  ('opcat-033','rfq_qualification_manager'),
  ('opcat-034','rfq_qualification_manager'),
  ('opcat-035','rfq_qualification_manager'),
  ('opcat-036','spec_industrial'),
  ('opcat-037','rfq_qualification_manager'),
  ('opcat-038','rfq_qualification_manager'),
  ('opcat-039','rfq_qualification_manager'),
  ('opcat-040','rfq_qualification_manager'),
  ('opcat-041','rfq_qualification_manager'),
  ('opcat-042','rfq_qualification_manager'),
  ('opcat-043','rfq_qualification_manager'),
  ('opcat-044','rfq_qualification_manager'),
  ('opcat-045','rfq_qualification_manager'),
  ('opcat-046','rfq_qualification_manager'),
  ('opcat-047','rfq_qualification_manager'),
  ('opcat-048','rfq_qualification_manager'),
  ('opcat-049','rfq_qualification_manager'),
  ('opcat-050','rfq_qualification_manager'),
  ('opcat-051','spec_industrial'),
  ('opcat-052','spec_industrial'),
  ('opcat-053','spec_industrial'),
  ('opcat-054','spec_industrial'),
  ('opcat-055','spec_industrial'),
  ('opcat-056','spec_industrial'),
  ('opcat-057','spec_industrial'),
  ('opcat-058','spec_industrial'),
  ('opcat-059','spec_industrial'),
  ('opcat-060','spec_mep'),
  ('opcat-061','spec_industrial'),
  ('opcat-062','spec_industrial'),
  ('opcat-063','spec_industrial'),
  ('opcat-064','spec_industrial'),
  ('opcat-065','spec_industrial'),
  ('opcat-066','spec_industrial'),
  ('opcat-067','spec_industrial'),
  ('opcat-068','rfq_qualification_manager'),
  ('opcat-069','rfq_qualification_manager'),
  ('opcat-070','rfq_qualification_manager'),
  ('opcat-071','rfq_qualification_manager'),
  ('opcat-072','rfq_qualification_manager'),
  ('opcat-073','rfq_qualification_manager'),
  ('opcat-074','rfq_qualification_manager'),
  ('opcat-075','rfq_qualification_manager'),
  ('opcat-076','rfq_qualification_manager'),
  ('opcat-077','rfq_qualification_manager'),
  ('opcat-078','rfq_qualification_manager'),
  ('opcat-079','rfq_qualification_manager'),
  ('opcat-080','rfq_qualification_manager'),
  ('opcat-081','spec_construction'),
  ('opcat-082','spec_mep'),
  ('opcat-083','spec_construction'),
  ('opcat-084','spec_construction'),
  ('opcat-085','rfq_qualification_manager'),
  ('opcat-086','spec_mep')
  ) as v(overlay_id, esc)
 where b.overlay_id = v.overlay_id;

-- ================================================================================================
-- 2. RECONCILE THE ORGANISATION TO THE AUTHORITY.
--    Driven off the table above rather than a second hand-written list, so the correction and the
--    check can never disagree about what the map says.
-- ================================================================================================
update public.org_role r
   set manager_role_id = a.manager_role_id
  from public.phase_c_reporting_authority a
 where a.live_role_id = r.role_id
   and a.manager_role_id <> 'founder'
   and r.manager_role_id is distinct from a.manager_role_id;

update public.org_role r
   set runtime_mode = a.runtime_mode
  from public.phase_c_reporting_authority a
 where a.live_role_id = r.role_id
   and r.runtime_mode is distinct from a.runtime_mode;

-- the overlays: ADD the broad-domain specialist, keep every path that already existed
update public.org_role r
   set escalation_targets = array[b.broad_domain_escalation_role_id]
                            || array(select unnest(r.escalation_targets)
                                      except select b.broad_domain_escalation_role_id)
  from public.phase_c_overlay_binding b
 where b.live_role_id = r.role_id
   and r.runtime_mode = 'knowledge_overlay'
   and r.status = 'active'
   and b.broad_domain_escalation_role_id is not null
   and not (b.broad_domain_escalation_role_id = any(r.escalation_targets));

-- the overlay now says it cannot move money, which is what its authority already enforced
update public.org_role
   set forbidden_decisions = forbidden_decisions
         || array['moving money, issuing or approving a payment, or deciding a refund'],
       necessity_reason = necessity_reason || '; payment, refund or any movement of money'
 where runtime_mode = 'knowledge_overlay' and status = 'active'
   and not exists (select 1 from unnest(forbidden_decisions) f where f ilike '%money%');

-- ================================================================================================
-- 3. THE CHECK THAT WOULD HAVE CAUGHT THIS.
--    Every field the founder's instruction names, compared against the recorded authority. It
--    returns rows; zero rows is the only passing result.
-- ================================================================================================
create or replace function public.fn_phase_c_reporting_map_drift()
returns table(subject text, role_id text, approved text, live text)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- FIRST, THE SUBJECT ITSELF. Every other branch below reads phase_c_reporting_authority, so an
  -- empty table would make all of them return nothing and the check would report perfect agreement
  -- with an authority that is no longer there. Absent input must not score as satisfied: the row
  -- count is asserted against the founder-approved shape before anything is compared to it.
  select 'authority_not_recorded', 'phase_c_reporting_authority',
         '90 standing roles', count(*)::text
    from public.phase_c_reporting_authority having count(*) <> 90
  union all
  select 'overlay_authority_not_recorded', 'phase_c_overlay_binding',
         '86 category overlays', count(*)::text
    from public.phase_c_overlay_binding having count(*) <> 86
  union all
  -- a standing role the map names that the organisation cannot resolve
  select 'unresolved_role', a.canonical_role_id, a.live_role_id, '(no active org_role)'
    from public.phase_c_reporting_authority a
   where not exists (select 1 from public.org_role r
                      where r.role_id = a.live_role_id and r.status = 'active')
  union all
  select 'primary_manager', a.canonical_role_id, a.manager_role_id, coalesce(r.manager_role_id,'founder')
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where coalesce(r.manager_role_id,'founder') is distinct from a.manager_role_id
  union all
  select 'primary_department', a.canonical_role_id, a.department_id, r.primary_department_id
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.primary_department_id is distinct from a.department_id
  union all
  select 'role_class', a.canonical_role_id, a.role_class||'/'||a.runtime_mode, r.runtime_mode
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.runtime_mode is distinct from a.runtime_mode
  union all
  -- the department head the map names must be the head the department records
  select 'department_head', a.canonical_role_id, a.department_head_role_id, coalesce(d.lead_agent,'(none)')
    from public.phase_c_reporting_authority a
    join public.org_departments d on d.dept_key = a.department_id
    left join public.org_role h on h.role_id = a.department_head_role_id
   where d.lead_agent is distinct from h.runtime_agent_key
  union all
  -- the path to the founder, WALKED in the live graph rather than assumed, and compared with the
  -- approved path. This is also the cycle check: a chain that loops never reaches the founder, so
  -- the walk returns null and the row is reported.
  select 'reporting_path', a.canonical_role_id, a.reporting_path, coalesce(w.walked,'(never reaches the founder)')
    from public.phase_c_reporting_authority a
    left join lateral (
      with recursive up(cur, depth, path) as (
        select a.live_role_id, 0, a.live_role_id
        union all
        select coalesce(r.manager_role_id,'founder'), u.depth+1,
               u.path||' > '||coalesce(r.manager_role_id,'founder')
          from up u join public.org_role r on r.role_id = u.cur and r.status='active'
         where u.depth < 20 and u.cur <> 'founder')
      select path as walked from up where cur = 'founder' order by depth limit 1
    ) w on true
   where w.walked is distinct from a.reporting_path
  union all
  -- one live role standing in for two canonical roles
  select 'duplicate_active_identity', x.live_role_id, 'one canonical role', x.n::text
    from (select live_role_id, count(*) n from public.phase_c_reporting_authority
           group by 1 having count(*) > 1) x
  union all
  select 'self_management', a.canonical_role_id, a.manager_role_id, r.manager_role_id
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.manager_role_id = r.role_id
  union all
  -- An identity that cannot act, or one that acts as an employee nobody models.
  --
  -- runtime_enabled=false is treated separately from the rest, and deliberately so. Phase A
  -- deferred product_ux_designer's tools, knowledge, KPI and authority to a later phase with the
  -- founder's approval, and switching the role OFF is the correct consequence of that deferral —
  -- a role left enabled with no tools is the worse state, not the better one. So a disabled role
  -- is reported unless fn_phase_a_deferred_items() is currently carrying it. That exemption is not
  -- a hole: it is checked against the live deferral list on every call, so the moment the deferral
  -- is closed — or the moment any OTHER role is switched off — this fires. A missing agent key, an
  -- agent absent from org_agents, or an inactive agent are never exempt.
  select 'identity_cannot_act', a.canonical_role_id, 'an active runtime identity',
         coalesce(r.runtime_agent_key,'(none)')
           || case when r.runtime_enabled then '' else ' runtime_enabled=false' end
           || case when g.agent_key is null then ' not in org_agents'
                   when g.active is not true then ' agent inactive' else '' end
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    left join public.org_agents g on g.agent_key = r.runtime_agent_key
   where r.runtime_agent_key is null
      or g.agent_key is null
      or g.active is not true
      or (r.runtime_enabled is not true
          and not exists (select 1 from public.fn_phase_a_deferred_items() d
                           where d.role_id = r.role_id))
  union all
  -- OVERLAYS: the governance facts the founder's instruction lists, one row per failing overlay
  select 'overlay_unbound', o.overlay_id, 'a live category overlay', coalesce(o.live_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where not exists (select 1 from public.org_role r
                      where r.role_id = o.live_role_id and r.status='active'
                        and r.runtime_mode='knowledge_overlay')
  union all
  select 'overlay_department', o.overlay_id, 'marketplace', r.primary_department_id
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where r.primary_department_id is distinct from 'marketplace'
  union all
  select 'overlay_accountable_manager', o.overlay_id, 'marketplace_director reachable',
         array_to_string(r.escalation_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not ('marketplace_director' = any(r.escalation_targets))
  union all
  select 'overlay_invocation_role', o.overlay_id, 'inquiry_router', coalesce(o.invocation_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where o.invocation_role_id is distinct from 'inquiry_router'
  union all
  select 'overlay_result_returns_to', o.overlay_id, 'rfq_qualification_manager',
         coalesce(o.result_returns_to_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where o.result_returns_to_role_id is distinct from 'rfq_qualification_manager'
  union all
  select 'overlay_returns_unreachable', o.overlay_id, 'rfq_qualification_manager in handoff_targets',
         array_to_string(r.handoff_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not ('rfq_qualification_manager' = any(r.handoff_targets))
  union all
  select 'overlay_broad_domain_escalation', o.overlay_id,
         coalesce(o.broad_domain_escalation_role_id,'(unrecorded)'), array_to_string(r.escalation_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where o.broad_domain_escalation_role_id is null
      or not (o.broad_domain_escalation_role_id = any(r.escalation_targets))
  union all
  -- the three governance owners the map names must exist and be able to act
  select 'overlay_governance_owner', g.who, g.who, 'missing or not active'
    from (values ('category_curator'),('taxonomy_manager'),('knowledge_validator')) g(who)
   where not exists (select 1 from public.org_role r where r.role_id = g.who and r.status='active')
  union all
  -- an overlay that could decide something the map forbids it
  select 'overlay_authority', o.overlay_id, 'advisory, holding no runtime employee',
         r.authority_level||coalesce(' as '||r.runtime_agent_key,'')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where r.authority_level <> 'advisory' or r.runtime_agent_key is not null
  union all
  select 'overlay_states_no_money_limit', o.overlay_id, 'cannot move money or decide a refund',
         'no such forbidden_decision'
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not exists (select 1 from unnest(r.forbidden_decisions) f where f ilike '%money%')
  union all
  -- THE CHAIN OF COMMAND. Normal autonomous work may not route through the founder or the Chief of
  -- Staff. The two founder-facing workflows are the declared exception — W01 founder mandate to
  -- company objectives, W02 company target miss and corrective management — and they are named
  -- rather than pattern-matched, so a new workflow cannot quietly join them.
  select 'autonomous_work_routes_through_chief_of_staff', s.step_id,
         'an accountable department role', s.accountable_role_id
    from public.phase_c_step_binding s
   where s.accountable_role_id in ('chief_of_staff','founder')
     and s.workflow_id not in ('W01','W02')
  union all
  -- the founder's single routine approval
  select 'non_refund_founder_approval', c.action_class, 'refund_decision is the only one',
         'founder_approval_required'
    from public.phase_c_action_class c
   where c.founder_approval_required and c.action_class <> 'refund_decision';
$fn$;

revoke all on function public.fn_phase_c_reporting_map_drift() from public, anon;
grant execute on function public.fn_phase_c_reporting_map_drift() to authenticated, service_role;

commit;
