-- THREE MODEL-BACKED ACTION CLASSES NOW RUN AS SQL (MASTER_PLAN §5.3, 5 Sep 2026).
--
-- MEASURED 4-5 Sep 2026 on the one project: of 88 active org_action_executor rows, 43 are kind edge
-- and 22 of those import _shared/llm.ts or POST to ai_gateway. Ranked by workflow steps the loop
-- actually reached while the model is held (workflow_step_run since 1 Sep, closed advisory with
-- 'executor runs on the held paid model; not queued' or a held/cancelled execution):
--   recommend           analytics_recommend  138 step runs (109 + 14 held + 3 cancelled + 12 failed)
--   exec_review         exec_agents            9
--   knowledge_fill_gap  kb_fill_gap            5
--   knowledge_acquire   kb_deepen              3  (NOT substituted: "acquire from a cited external
--                                                  source" is the doctrine's external-edge case)
-- The three are re-pointed at the deterministic routines shipped beside this file. The previous edge
-- target is kept in params.model_escalation_target: it stays deployed and callable by hand, and it
-- is the executor to restore for the one sub-case the doctrine reserves to a model - generating
-- knowledge text for a category with 0 chunks (kb_fill_gap). Nothing here reaches a paid provider.
--
-- fn_org_action_executor_guard refuses an rpc target that is not in org_action_executor_rpc_allowed,
-- so the allow-list is extended first, deliberately, one line per routine.

insert into public.org_action_executor_rpc_allowed(target, note) values
  ('fn_recommend_deterministic',    'recommend: KPI/scorecard/ad-insight arithmetic for the step''s department; replaces analytics_recommend (model) 5 Sep 2026'),
  ('fn_exec_review_deterministic',  'exec_review: approval-tier resolution from org_role, fn_dept_authority, fn_should_escalate and the run''s prior steps; replaces exec_agents (model) 5 Sep 2026'),
  ('fn_knowledge_gap_deterministic','knowledge_fill_gap: review-date decay over ops_knowledge and per-category kb_chunks coverage; replaces kb_fill_gap (model) 5 Sep 2026')
on conflict (target) do nothing;

update public.org_action_executor set
  kind = 'rpc', target = 'fn_recommend_deterministic',
  params = coalesce(params, '{}'::jsonb) || jsonb_build_object('model_escalation_target', 'analytics_recommend', 'previous_kind', 'edge', 'substituted_at', '2026-09-05',
             'model_escalation_when', 'none by doctrine: a recommendation over stored metrics is arithmetic; meta_sync (not this class) is the online read'),
  note = 'Deterministic recommendation from employee_kpi, employee_kpi_history, v_bi_scorecard/metric_snapshot and meta_insights for the step''s department; framing follows the step text. Distinct no_data / no_scope shapes. Records an org_memory insight. Replaced analytics_recommend (model) 5 Sep 2026.'
where action_class = 'recommend';

update public.org_action_executor set
  kind = 'rpc', target = 'fn_exec_review_deterministic',
  params = coalesce(params, '{}'::jsonb) || jsonb_build_object('model_escalation_target', 'exec_agents', 'previous_kind', 'edge', 'substituted_at', '2026-09-05',
             'model_escalation_when', 'none by doctrine: approvals are deterministic; exec_agents remains a hand-run officer report'),
  note = 'Approval-tier resolution: reads the run''s prior step deliverables, the officer''s org_role.authority_level, fn_dept_authority for the department and fn_should_escalate over decision_policy; approves within authority or escalates with named reasons and addressee. Replaced exec_agents (model) 5 Sep 2026.'
where action_class = 'exec_review';

update public.org_action_executor set
  kind = 'rpc', target = 'fn_knowledge_gap_deterministic',
  params = coalesce(params, '{}'::jsonb) || jsonb_build_object('model_escalation_target', 'kb_fill_gap', 'previous_kind', 'edge', 'substituted_at', '2026-09-05',
             'model_escalation_when', 'a category_agents row with 0 kb_chunks needs text written (content creation); 0 such rows on 5 Sep 2026'),
  note = 'Coverage determination: decays ops_knowledge past review_after to review_required (reversible, count stated) and classifies every active category as missing/thin/stale/ok from kb_chunks counts and dates. Replaced kb_fill_gap (model) 5 Sep 2026.'
where action_class = 'knowledge_fill_gap';

-- Read back what the guard let through.
do $$
declare v int;
begin
  select count(*) into v from public.org_action_executor
   where (action_class, kind, target) in (('recommend','rpc','fn_recommend_deterministic'),
                                          ('exec_review','rpc','fn_exec_review_deterministic'),
                                          ('knowledge_fill_gap','rpc','fn_knowledge_gap_deterministic'))
     and active;
  if v <> 3 then raise exception 'deterministic substitutes: expected 3 rpc registrations, found %', v; end if;
end $$;
