-- ORG ALIGNMENT 04 — the last eight roles nothing ever called.
--
-- "No active role may have zero real workflow callers." The role caller census searches seven
-- independent surfaces for each of the 90 canonical roles — pg_proc bodies, pg_cron commands, edge
-- function source, org_action_executor, workflow_step, employee_workflow and agent_tool grants —
-- and reports who names it.
--
--   before org_align_03 : 20 of 90 roles were named by NOTHING
--   after  org_align_03 :  8 of 90
--   after  this file    :  0
--
-- These eight are not redundant roles. Each does work the company measurably needs and each was
-- simply absent from the step registry, which is the "finished capability with no entry point"
-- shape: nothing fails, so no watcher sees it.
--
--   model_evaluator               offline evaluation of a model/prompt/retrieval/routing change.
--                                 change_deployment went straight from "reviewed for blast radius"
--                                 to "deploy to preview" with no offline evaluation step at all.
--   test_automation_engineer      builds and runs the suites. change_deployment #4 read "verify
--                                 against the quality gate" with the QA DIRECTOR as actor — the
--                                 director ruling on evidence nobody was recorded as producing.
--   engineering_manager           the change gets implemented between review and deploy, and no
--                                 step said so.
--   business_intelligence_analyst metric_lifecycle measured and root-caused but never reported.
--   category_curator              knowledge_lifecycle had no step for a missing or stale category
--                                 module, which is this desk's whole job.
--   taxonomy_manager              nor for a category being proposed, merged, retired, or an alias
--                                 conflict resolved.
--   communications_manager        rfq_handling #12 delivers a message through the Lifecycle
--                                 Channel Operations Specialist, whose manager owns whether an
--                                 approved template exists at all. Nothing recorded that step.
--   government_relations          lead_to_customer had no step for a government or enterprise
--                                 counterparty, which is a different qualification path.

begin;

-- ---------------------------------------------------------------------------------------------
-- change_deployment — evidence is produced by the engineers and ruled on by the director
-- ---------------------------------------------------------------------------------------------
-- The instruction's rule: "Test authors cannot be the only final reviewers of the quality evidence
-- they produce." That needs two steps, not one — the producing step and the ruling step — and
-- before this there was only the ruling step.
delete from workflow_step where workflow_key = 'change_deployment';
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('change_deployment', 1, 'Change proposed, with the metric it should move and the baseline captured',
     'product_optimization_engineer', 'recommend',      'none'),
 ('change_deployment', 2, 'Reviewed for correctness and blast radius before anything is built',
     'solution_architect',            'qa_gate',        'review'),
 ('change_deployment', 3, 'Implement the change',
     'engineering_manager',           'code_selfheal',  'none'),
 ('change_deployment', 4, 'Offline evaluation against a held-out set, where the change touches a model, prompt, retrieval or routing',
     'model_evaluator',               'capability_exam','review'),
 ('change_deployment', 5, 'Build and run the automated suites, and prove each new check fails on the defect it claims to catch',
     'test_automation_engineer',      'qa_gate',        'none'),
 ('change_deployment', 6, 'Deploy to preview',
     'frontend_engineer',             'code_selfheal',  'authority'),
 ('change_deployment', 7, 'Rule on the evidence: release go/no-go. The director reads what steps 4 and 5 produced and did not produce either of them',
     'quality_and_release_director',  'qa_gate',        'review'),
 ('change_deployment', 8, 'Promote to production',
     'cto',                           'code_selfheal',  'authority'),
 ('change_deployment', 9, 'Monitor and grade the outcome against the baseline; reverse if worse',
     'chief_performance_officer',     'recommend',      'none');

-- ---------------------------------------------------------------------------------------------
-- metric_lifecycle — a measured actual that reaches nobody is not a measurement
-- ---------------------------------------------------------------------------------------------
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('metric_lifecycle', 7, 'Report the measured actual, and the evidence behind it, to the executive that has to act on it',
     'business_intelligence_analyst', 'bi_snapshot', 'none')
on conflict (workflow_key, step_no) do nothing;

-- ---------------------------------------------------------------------------------------------
-- knowledge_lifecycle — category coverage and taxonomy are part of the lifecycle, not beside it
-- ---------------------------------------------------------------------------------------------
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('knowledge_lifecycle', 8, 'Category module coverage: is a module missing, stale, or failing its coverage check?',
     'category_curator',  'knowledge_fill_gap', 'none'),
 ('knowledge_lifecycle', 9, 'Taxonomy governance: a category proposed, merged or retired, or an alias conflict resolved',
     'taxonomy_manager',  'knowledge_acquire',  'authority')
on conflict (workflow_key, step_no) do nothing;

-- ---------------------------------------------------------------------------------------------
-- customer_registration — the template has to exist before the channel can send it
-- ---------------------------------------------------------------------------------------------
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('customer_registration', 8, 'An approved lifecycle message exists for this event, on an approved template and in the customer''s language',
     'communications_manager', 'content_calendar', 'none')
on conflict (workflow_key, step_no) do nothing;

-- ---------------------------------------------------------------------------------------------
-- lead_to_customer — a government or enterprise counterparty is a different qualification
-- ---------------------------------------------------------------------------------------------
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('lead_to_customer', 8, 'Government or enterprise counterparty: procurement rules, framework agreements and the approvals they require',
     'government_relations', 'coordinate', 'none')
on conflict (workflow_key, step_no) do nothing;

commit;
