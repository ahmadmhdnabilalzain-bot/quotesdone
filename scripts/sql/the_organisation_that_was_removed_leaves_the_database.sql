-- the_organisation_that_was_removed_leaves_the_database.sql
-- Agent: ceo.  Measured against production htdblwldjkcgjvmqkbeh on 9 September 2026.
--
-- WHY THIS FILE EXISTS
-- --------------------
-- The founder's ruling, verbatim: "i dont want a single routine or workflow or decision prior
-- 7 september. literally nothing". On 7 September the organisation chart was removed: no
-- departments, no roles beyond two, no workflows, no tasks, no handoffs, no exams. The company
-- is two agents (ceo, customer_support) plus the public website. From before 7 September the
-- founder keeps only: website content, FAQ, company knowledge, leads, API secrets.
--
-- WHAT WAS MEASURED, AND WHAT IT SAID
-- -----------------------------------
-- Every claim below came out of the catalogue (pg_class, pg_constraint, pg_depend/pg_rewrite,
-- pg_trigger, pg_policy, pg_attrdef, pg_event_trigger, pg_proc.prosrc, cron.job), not a text
-- scan of the repo, plus a grep of the 79 deployed edge functions and of src/.
--
--   * 94 relations matched the removal scope (org_*, dept*, workflow*, *task*, *handoff*,
--     agent_*, exam*, certif*, employee_*, skills_matrix, qualification_playbooks, board_*,
--     decision_*, outcome_*, objective*, evolution_*, challenge_*, delegation_*,
--     collaboration_*, review_chain, self_review, spec_backlog, institutional_memory, os_*).
--   * 182 routines read at least one of them.  91 of those are reachable from something that is
--     still live: a deployed edge function's RPC, a trigger on a table that survives, or another
--     routine that is itself reachable.  Closing that reachability set over the call graph
--     (4 passes) leaves 162 routines that MUST stay and 20 that are reachable from nothing.
--   * Two of those 20 (fn_dept_library_search, fn_ops_knowledge_search) read company knowledge,
--     which the founder keeps, so they are left alone.  fn_handoff_contract_guard was added: it
--     exists only as the trigger on handoff_contract, which this file drops.
--   * Only 13 relations in scope are reachable from nothing at all.  Three are views, ten are
--     tables.  Those are what this file removes.  Total rows destroyed: 331.
--
-- THE COUNTS, EXACTLY AS MEASURED
--   agent_command_log         0      agent_context_head       21      agent_context_retrieval  0
--   agent_expectations      203      agent_pending_actions     0      handoff_contract         0
--   org_category_identity    86      org_committee             5      org_onboarding          16
--   org_role_committee        0
--   views: v_digital_twin, v_executions_without_decision_trace,
--          v_workflow_side_effects_without_executor  (no rows of their own)
--
-- WHAT IS **NOT** DROPPED, AND WHY - read this before you widen the file
-- ---------------------------------------------------------------------
-- 1. org_role (2 rows: ceo, customer_support), org_agents (2 rows), org_reporting_edge (1 row:
--    customer_support -> ceo).  Verified by SELECT.  That IS the new structure, not the old
--    chart.  fn_support_report_to_ceo refuses to send without them and several RLS policies call
--    fn_role_of, which reads org_agents.
-- 2. agent_runs - written live by 30 deployed edge functions and read by
--    trg_health_check_agent_threshold on health_checks.  That coupling needs no rewrite: the
--    trigger reads a table that survives.
-- 3. agent_knowledge, ops_knowledge, dept_library (1,456 rows), leads (22,264 rows) - company
--    knowledge and leads, explicitly kept.
-- 4. Today's CEO tables (ceo_command*, ceo_task*, ceo_identity, ceo_approval),
--    support_public_override, v_support_corpus - built after 7 September.
-- 5. Read live by a deployed edge function, therefore untouchable until that function is
--    redeployed: agent_actions, agent_tool_call, board_reports, crm_tasks, decision_log,
--    decision_policy, os_audit_log, os_incidents, workflow_run.
-- 6. Held by a foreign key from a table that survives:
--      org_departments  <- company_goals, org_agents, org_role
--      workflow         <- workflow_run          (workflow_run is item 5)
--      workflow_step_run<- action_execution
--      employee_knowledge_standard <- employee_knowledge
--    A CASCADE would take the referring table with it.  This file never uses CASCADE.
-- 7. Held by a routine that is still reachable.  The five couplings named in the brief, as found:
--      fn_os_incident_close_task  reads org_tasks and institutional_memory OUTSIDE its exception
--        block; it is the t30 trigger on os_incidents, which stays (item 5).  62 os_incidents
--        rows exist; 43 carry a non-null org_task_id.  org_tasks therefore cannot go until this
--        function is rewritten AND fn_receipt_hand_to_bookkeeper / fn_report_recommendation_approve
--        / fn_ws_agent_ops (all live RPCs that write or read org_tasks) are rewritten with it.
--      trg_health_check_agent_threshold on health_checks reads agent_runs - agent_runs survives,
--        no rewrite needed.
--      fn_founder_mail_route reads org_role, org_agents, org_departments, org_tasks and WRITES
--        org_tasks.  It is not itself a trigger; it is called by fn_notify_founder,
--        fn_agent_silence_watch and fn_notifications_founder_mail_policy (the a10 trigger on
--        notifications).  Rewriting it is a prerequisite for dropping org_departments/org_tasks.
--      trg_goal_cascade on company_goals reads org_departments, org_tasks and workflow.  Same
--        prerequisite.
--      z_report_pdf_enqueue on exec_reports runs fn_report_pdf_enqueue, which reads board_reports
--        - board_reports stays (item 5), so no rewrite is needed.
--    Because every one of those five lands on an object this file does not drop, this file needs
--    NO trigger-function rewrite.  That is a finding, not an omission.
-- 8. cron.job 34 (wa_flush, inactive) runs fn_kernel_cron_exec, so that routine stays.
--
-- WHAT BREAKS IN THE REPO (not in production) AFTER THIS RUNS
--   scripts/wf/connectivity_audit.js reads v_workflow_side_effects_without_executor.  It is not
--   wired into CI (grep of .github and package.json: no hits).  A handful of scripts/staging/*
--   verifiers of the removed organisation reference the dropped routines by name; they are
--   verifiers of a thing that no longer exists.
--
-- Nothing here uses CASCADE.  Order is: views, then the one trigger, then routines, then tables
-- (child before parent), then an assertion block that fails the transaction if anything survived.

begin;

-- ---------------------------------------------------------------------------
-- 1. VIEWS.  No routine, policy, default or other view reads any of these
--    (pg_rewrite/pg_depend: zero dependants).  v_digital_twin is named only in
--    two source comments; src/ makes no direct table reads at all.
-- ---------------------------------------------------------------------------
drop view if exists public.v_workflow_side_effects_without_executor;
drop view if exists public.v_executions_without_decision_trace;
drop view if exists public.v_digital_twin;

-- ---------------------------------------------------------------------------
-- 2. TRIGGER.  a00_handoff_contract_guard is the only user of
--    fn_handoff_contract_guard.  (z00_kernel_truncate_guard on the same table
--    uses the shared fn_kernel_truncate_guard, which stays; that trigger goes
--    with the table in step 4.)
-- ---------------------------------------------------------------------------
drop trigger if exists a00_handoff_contract_guard on public.handoff_contract;

-- ---------------------------------------------------------------------------
-- 3. ROUTINES.  Signatures are pg_get_function_identity_arguments verbatim.
--    Measured: no view, no policy, no trigger, no column default and no
--    surviving routine references any of them; every caller found is itself in
--    this list.  fn_agent_context has two overloads; both go.
-- ---------------------------------------------------------------------------
drop function if exists public.fn_red_view_alert(p_boards boolean);
drop function if exists public.fn_company_connectivity_register();
drop function if exists public.fn_action_invoke_collect();
drop function if exists public.fn_action_invoke_rpc(p_limit integer);
drop function if exists public.fn_org_task_assign(p_limit integer);

drop function if exists public.fn_agent_action_work_sweep(p_limit integer);
drop function if exists public.fn_agent_action_hand_to_owner(p_action_id bigint, p_owner text, p_basis text);
drop function if exists public.fn_decision_record_route(p_decision_id bigint);
drop function if exists public.fn_decide(p_kind text, p_ctx jsonb, p_actor text);
drop function if exists public.fn_board_review(p_subject text, p_subject_ref text);

drop function if exists public.fn_agent_context(p_agent_key text, p_max_chars integer);
drop function if exists public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text);
drop function if exists public.fn_agent_context_v3(p_agent_key text, p_task_class text, p_task_text text, p_category_key text, p_budget_chars integer);
drop function if exists public.fn_category_key_from_text(p_text text);
drop function if exists public.fn_category_key_for_slug(p_slug text);

drop function if exists public.fn_runner_silence_watch();
drop function if exists public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text);
drop function if exists public.fn_write_decision_trace(p jsonb);
drop function if exists public.fn_handoff_contract_guard();

-- ---------------------------------------------------------------------------
-- 4. TABLES.  Measured for each: no foreign key points at it from outside this
--    list, no view depends on it, no policy names it, no trigger of its own
--    survives it, no edge function and no src/ file reads it.
--    org_role_committee is dropped before org_committee because it holds the
--    org_role_committee_committee_key_fkey pointing at it.
-- ---------------------------------------------------------------------------
drop table if exists public.org_role_committee;       -- 0 rows; FK -> org_committee, org_role
drop table if exists public.org_committee;            -- 5 rows
drop table if exists public.org_category_identity;    -- 86 rows; FK -> org_agents (survives)
drop table if exists public.org_onboarding;           -- 16 rows
drop table if exists public.handoff_contract;         -- 0 rows
drop table if exists public.agent_expectations;       -- 203 rows
drop table if exists public.agent_context_head;       -- 21 rows
drop table if exists public.agent_context_retrieval;  -- 0 rows
drop table if exists public.agent_pending_actions;    -- 0 rows
drop table if exists public.agent_command_log;        -- 0 rows

-- ---------------------------------------------------------------------------
-- 5. PROOF.  Fails the whole transaction if anything above survived, or if the
--    two-agent structure that replaced the chart did not.
-- ---------------------------------------------------------------------------
do $check$
declare
  v_left    int;
  v_names   text;
  v_roles   int;
  v_agents  int;
  v_edges   int;
begin
  select count(*), coalesce(string_agg(relname, ', ' order by relname), '')
    into v_left, v_names
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('org_role_committee','org_committee','org_category_identity',
                      'org_onboarding','handoff_contract','agent_expectations',
                      'agent_context_head','agent_context_retrieval','agent_pending_actions',
                      'agent_command_log','v_digital_twin',
                      'v_executions_without_decision_trace',
                      'v_workflow_side_effects_without_executor');
  if v_left <> 0 then
    raise exception 'the organisation did not leave: % relation(s) still here: %', v_left, v_names;
  end if;

  select count(*), coalesce(string_agg(p.proname, ', ' order by p.proname), '')
    into v_left, v_names
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('fn_red_view_alert','fn_company_connectivity_register',
                      'fn_action_invoke_collect','fn_action_invoke_rpc','fn_org_task_assign',
                      'fn_agent_action_work_sweep','fn_agent_action_hand_to_owner',
                      'fn_decision_record_route','fn_decide','fn_board_review',
                      'fn_agent_context','fn_agent_context_v3','fn_category_key_from_text',
                      'fn_category_key_for_slug','fn_runner_silence_watch',
                      'fn_supplier_sanctions_screen','fn_write_decision_trace',
                      'fn_handoff_contract_guard');
  if v_left <> 0 then
    raise exception 'routines survived the removal: % (%)', v_left, v_names;
  end if;

  -- The two agents and the one reporting edge are the NEW structure. If this
  -- file ever cost them a row, the whole run must come back.
  select count(*) into v_roles  from public.org_role;
  select count(*) into v_agents from public.org_agents;
  select count(*) into v_edges  from public.org_reporting_edge;
  if v_roles <> 2 or v_agents <> 2 or v_edges <> 1 then
    raise exception 'the two-agent structure was damaged: org_role=%, org_agents=%, org_reporting_edge=%',
      v_roles, v_agents, v_edges;
  end if;

  -- The knowledge and the leads the founder keeps must be untouched.
  if (select count(*) from public.leads) < 22000 then
    raise exception 'leads lost rows';
  end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                 where n.nspname='public' and c.relname='dept_library') then
    raise exception 'dept_library (company knowledge) was dropped';
  end if;

  raise notice 'the organisation that was removed has left the database: 13 relations, 19 routines, 331 rows.';
end
$check$;

commit;
