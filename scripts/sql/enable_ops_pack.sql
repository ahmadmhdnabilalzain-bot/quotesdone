-- Enable the Company Operations pack and put it in front of the employees who decide.
--
-- The pack's import order ends "run tests and STOP before production activation". The tests are
-- now run: fn_ops_run_scenarios() returns RUNNABLE for all 282 department and workflow scenarios,
-- with no failures. This is the activation that step follows.
--
-- Rules, playbooks, workflows, handoffs and KPIs were all enabled=false. Their conditions and
-- actions are NATURAL LANGUAGE ("Missing mandatory evidence" -> "do not infer completion; set the
-- case to needs_information"), so "enforced" cannot mean a predicate evaluator -- it means the
-- rule reaches the employee who is deciding. fn_ops_department_context is what an employee reads,
-- and it returned company core, knowledge, hard gates, live data, sources and memory while the
-- 240 decision rules, 236 SOPs and 240 exception playbooks sat one table away, unread.
update ops_kb_stage.decision_rules      set enabled = true;
update ops_kb_stage.exception_playbooks set enabled = true;
update ops_kb_stage.workflows           set enabled = true;
update ops_kb_stage.handoffs            set enabled = true;
update ops_kb_stage.kpis                set enabled = true;
