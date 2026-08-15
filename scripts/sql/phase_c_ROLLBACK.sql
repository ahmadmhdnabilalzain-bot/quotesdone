-- Phase C — ROLLBACK.
--
-- NOT PART OF THE FORWARD DEPLOYMENT. This file exists so the reversal is committed alongside the
-- change rather than reconstructed under pressure. Run it only to undo Phase C.
--
-- Every Phase C object is ADDITIVE, which is what makes this short. Nothing pre-existing was
-- dropped, renamed or altered. Two pre-existing tables gained an INSERT guard and one gained four
-- classification rows; those three are the only edits to anything that existed before Phase C, and
-- they are reversed first below.
--
-- WHAT THIS DELIBERATELY DOES NOT DO:
--
--   * It does not touch Phase A or Phase B. No Phase C statement ever wrote to them, the freeze
--     triggers were never challenged, and app.phase_a_change_reason / app.phase_b_change_reason
--     were never set.
--
--   * It does not restore founder_release_approval id=1. That row was never deleted. It is the
--     founder's own approval of 10 Aug 2026 and Phase C only stopped a SECOND one being created.
--
--   * It does not re-enable anything. Phase C changed no activation state, so there is none to
--     restore: cron jobs 205, active 186, provider routes held 8, before and after.
--
-- ORDER MATTERS. Drop the guards before the tables they read, and the binding tables before the
-- registries they reference.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ---------------------------------------------------------------- 1. pre-existing objects
drop trigger if exists z10_phase_c_no_new_release_approval on public.founder_release_approval;
drop trigger if exists z10_phase_c_no_new_procurement_approval on public.procurement_approval_request;
delete from public.control_mode_action where action like 'founder\_command%';

-- The 96 alias rows Phase C added. Every one carries its reason, so this removes exactly those
-- and leaves Phase B's 237 untouched.
delete from public.org_role_alias
 where reason like 'Phase C%'
    or reason = 'Phase C category overlay route key; derived from org_category_identity';
delete from public.org_department_alias where note = 'Phase C package department naming';

-- ---------------------------------------------------------------- 2. the runtime, newest first
drop trigger if exists z10_phase_c_overlay_not_accountable on public.phase_c_task;
drop trigger if exists z20_phase_c_task_state_guard on public.phase_c_task;
drop trigger if exists z30_phase_c_handoff_sender_retains on public.phase_c_handoff_run;
drop trigger if exists z20_phase_c_workflow_state_guard on public.phase_c_workflow_run;
drop trigger if exists z10_phase_c_trace_append_only on public.phase_c_trace;
drop trigger if exists z10_founder_command_message_immutable on public.founder_command_message;
drop trigger if exists z20_founder_command_state_guard on public.founder_command;
drop trigger if exists z10_founder_approval_refund_only on public.founder_approval_request;
drop trigger if exists z10_phase_c_refund_decision_guard on public.phase_c_refund_decision;

drop view if exists public.v_phase_c_what_reaches_the_founder;

drop function if exists public.fn_founder_command_inbox(integer);
drop function if exists public.fn_founder_command_control(bigint, text, text, text);
drop function if exists public.fn_founder_command_status(text);
drop function if exists public.fn_founder_command_submit(text, text, text, jsonb);
drop function if exists public.fn_founder_command_classify(text);
drop function if exists public.fn_founder_command_state_guard();
drop function if exists public.fn_founder_command_message_immutable();
drop function if exists public.fn_phase_c_command_specificity(text);

drop function if exists public.fn_phase_c_baseline_drift();
drop function if exists public.fn_phase_c_invariants();
drop function if exists public.fn_phase_c_non_refund_founder_approvals();
drop function if exists public.fn_phase_c_no_new_founder_approval_path();
drop function if exists public.fn_phase_c_refund_decision_guard();
drop function if exists public.fn_founder_approval_refund_only();
drop function if exists public.fn_phase_c_authority_check(text, text, text);

drop function if exists public.fn_phase_c_knowledge_scope(text, text, text);
drop function if exists public.fn_phase_c_tool_authorized(text, text);
drop function if exists public.fn_phase_c_role_context(text);
drop function if exists public.fn_phase_c_overlay_may_not_dispatch();
drop function if exists public.fn_phase_c_overlay_invoke(text, jsonb);
drop function if exists public.fn_phase_c_handoff_overdue();
drop function if exists public.fn_phase_c_handoff_decide(bigint, text, text, jsonb);
drop function if exists public.fn_phase_c_handoff_open(bigint, text, jsonb);
drop function if exists public.fn_phase_c_handoff_packet_valid(text, jsonb);
drop function if exists public.fn_phase_c_step_advance(bigint, text, text, jsonb);
drop function if exists public.fn_phase_c_gates_for_step(text);
drop function if exists public.fn_phase_c_step_owner_valid(text, text);
drop function if exists public.fn_phase_c_task_transition(bigint, text, text, jsonb);
drop function if exists public.fn_phase_c_task_create(jsonb);

drop function if exists public.fn_phase_c_output_validate(text, jsonb);
drop function if exists public.fn_phase_c_outbox_settle(bigint, boolean, text, text);
drop function if exists public.fn_phase_c_outbox_claim(integer);
drop function if exists public.fn_phase_c_outbox_emit(text, text, jsonb, text);
drop function if exists public.fn_phase_c_workflow_start(text, text, jsonb);
drop function if exists public.fn_phase_c_task_state_guard();
drop function if exists public.fn_phase_c_handoff_sender_retains();
drop function if exists public.fn_phase_c_workflow_state_guard();
drop function if exists public.fn_phase_c_task_transition_allowed(text, text);
drop function if exists public.fn_phase_c_workflow_transition_allowed(text, text);
drop function if exists public.fn_phase_c_reviewer_independent(text, text);
drop function if exists public.fn_phase_c_rule_check(text, jsonb);
drop function if exists public.fn_phase_c_gate_evaluate(text, jsonb);
drop function if exists public.fn_phase_c_trace_write(text, jsonb);
drop function if exists public.fn_phase_c_trace_append_only();
drop function if exists public.fn_phase_c_actor_may_own(text);
drop function if exists public.fn_phase_c_resolve_actor(text);

-- ---------------------------------------------------------------- 3. the tables
drop table if exists public.founder_command_overlay_invocation;
drop table if exists public.founder_command_completion;
drop table if exists public.founder_command_status_history;
drop table if exists public.founder_command_clarification;
drop table if exists public.founder_command_task_link;
drop table if exists public.founder_command_workflow_link;
drop table if exists public.founder_command_plan;
drop table if exists public.founder_command_interpretation;
drop table if exists public.founder_command;
drop table if exists public.founder_command_message;
drop table if exists public.founder_command_session;

drop table if exists public.phase_c_refund_decision;
drop table if exists public.founder_approval_request;
drop table if exists public.phase_c_founder_identity;

drop table if exists public.phase_c_event_delivery_attempt;
drop table if exists public.phase_c_event_outbox;
drop table if exists public.phase_c_handoff_run;
drop table if exists public.phase_c_task;
drop table if exists public.phase_c_workflow_step_run;
drop table if exists public.phase_c_workflow_run;
drop table if exists public.phase_c_trace;

drop table if exists public.phase_c_rule_binding;
drop table if exists public.phase_c_gate_binding;
drop table if exists public.phase_c_event_binding;
drop table if exists public.phase_c_handoff_binding;
drop table if exists public.phase_c_step_binding;
drop table if exists public.phase_c_workflow_binding;
drop table if exists public.phase_c_overlay_binding;
drop table if exists public.phase_c_role_binding;
drop table if exists public.phase_c_component;

drop table if exists public.phase_c_command_rule;
drop table if exists public.phase_c_command_specificity_signal;
drop table if exists public.phase_c_command_intent;
drop table if exists public.phase_c_task_transition;
drop table if exists public.phase_c_task_state;
drop table if exists public.phase_c_command_transition;
drop table if exists public.phase_c_command_state;
drop table if exists public.phase_c_action_class;
drop table if exists public.phase_c_trace_policy;
drop table if exists public.phase_c_system_actor;
drop table if exists public.phase_c_package_erratum;

-- ---------------------------------------------------------------- 4. what must be true after
--
--   select count(*) from public.fn_phase_a_baseline_drift();   -- 0
--   select count(*) from public.fn_phase_b_baseline_drift();   -- 0
--   select count(*) from public.org_role_alias;                -- 237
--   select count(*) from public.org_department_alias;          -- 25
--   select count(*) from cron.job where active;                -- 186
--   select count(*) from public.llm_route_health where open_until > now();  -- 8
--   select count(*) from public.founder_release_approval;      -- 1  (the founder's own record)
--
-- And redeploy os_api v58:
--   node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production os_api
-- after checking out the commit before 03645fe. Until then os_api v59's four command actions
-- return action_classification_required, which is a refusal and not a silent failure.
