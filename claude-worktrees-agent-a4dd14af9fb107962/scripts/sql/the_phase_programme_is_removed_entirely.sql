-- the_phase_programme_is_removed_entirely.sql
-- Agent: ceo
-- Written 9 September 2026. NOT APPLIED by the session that wrote it.
-- Target: the ONE Supabase project, htdblwldjkcgjvmqkbeh (QuotesDone production).
--
-- THE RULING (the founder, 8 September 2026, verbatim):
--   "even if the website went down for now its fine. remove them totally. i dont want to see
--    their names popping anymore. later when we create the right agents we will turn the
--    website up again correctly."
--
-- He was told the consequences before he said it, and he accepted them. This file is therefore
-- not a cautious partial sweep. It removes the ENTIRE Phase A-D programme and its kernel: every
-- table, every routine, every trigger, wherever it sits. If you are reading this in a year
-- wondering why half the vocabulary of this database disappeared in one commit, that is why.
--
-- WHAT WAS MEASURED (pg catalogue, 9 Sep 2026 - not a text scan, not a guess):
--   tables matching phase_a% / phase_b% / phase_c% / phase_d% / kernel_%   80
--     phase_a% 0  (the Phase A tables were already gone before today)
--     phase_b% 14   phase_c% 23   phase_d% 35   kernel_% 8
--   routines matching fn_phase_[abcd]_% or fn_kernel_%                     125   (124 dropped, 1 kept)
--   triggers running one of those routines                                 112
--     72 sit on machinery tables; 40 sit on tables that SURVIVE this file.
--   sequences in the machinery namespace                                   24
--     13 of them are UNOWNED - no pg_depend auto-dependency on any column - so they do NOT
--     fall with their tables. They are dropped by name in section 6. Miss that and you leave
--     13 orphan sequences behind with the names he asked never to see again.
--   views reading a machinery table                                        1  (v_cron_stale)
--   foreign keys crossing the boundary (surviving table -> machinery)      0
--   foreign keys crossing the boundary (machinery -> surviving table)      0
--     Both measured from pg_constraint contype=f. Because there are none, this file needs no
--     "alter table ... drop constraint" on any surviving table.
--   cron jobs scheduling a machinery routine                               0
--     cron.job holds exactly one job today: jobid 34, wa_flush, and it is inactive.
--   event triggers that are machinery                                      0  (7 exist)
--     trg_enforce_rls_new_tables / fn_enforce_rls_on_new_tables is UNTOUCHED. It puts
--     row-level security on every newly created table and is not part of this programme.
--
-- WHAT SURVIVES, and why:
--   fn_kernel_paid_provider_gate(p_model text) - KEPT. Despite the kernel_ name it is not
--   machinery. Its body was read (pg_get_functiondef, not the name) and it touches app_secrets,
--   llm_route_health and model_registry only - no phase table of any kind. It is the founder's
--   hold on paid inference: supabase/functions/_shared/paid_gate.ts calls it, and so do
--   fn_workflow_step_claim and fn_workflow_step_sweep inside the database. Dropping it would
--   re-open the OpenRouter spend he closed.
--   Nothing else survives. In particular, and against the earlier cautious sweeps:
--     fn_kernel_truncate_guard   goes, with all 39 of its triggers.
--     kernel_maintenance_write   goes (851 rows) - it is that guard's log table.
--     fn_kernel_founder_routing_is_refund_only goes, with its trigger on org_tasks.
--
-- WHAT THIS BREAKS. Named, one by one, because he accepted it:
--
--  1. TRUNCATE protection disappears from 39 LIVE tables. z00_kernel_truncate_guard sat on each
--     of them and refused TRUNCATE, logging the attempt to kernel_maintenance_write. After this
--     file, anyone holding the privilege can truncate them and nothing records it. The guard
--     fired on TRUNCATE ONLY, so ordinary insert/update/delete traffic on these tables is
--     unaffected - the website does not stop writing because of this item. The 39 tables:
--       ad_decision
--       ap_bills
--       app_secrets
--       artifact_review
--       control_mode_session
--       customers
--       decision_log
--       decision_trace
--       gl_journal
--       gl_journal_lines
--       handoff_contract
--       inquiries
--       inquiry_answer
--       inquiry_answer_conflict_value
--       inquiry_answer_corroboration
--       inquiry_answer_document
--       inquiry_scope_disposition
--       inquiry_state_audit
--       inquiry_supplier_brief
--       inquiry_trade_candidate_evidence
--       internal_credential_audit
--       leads
--       llm_attempt
--       org_action_executor
--       org_authority
--       org_departments
--       org_phase_baseline
--       org_role
--       org_role_identity
--       org_tasks
--       os_incidents
--       phase1_rollback_log
--       procurement_approval_request
--       quotes
--       refunds
--       review_chain
--       security_audit_log
--       transactions
--       workflow_step_run
--
--  2. org_tasks stops refusing founder routing. a00_org_tasks_founder_routing_refund_only ran
--     fn_kernel_founder_routing_is_refund_only, which raised SQLSTATE 23514 on any org_tasks row
--     with needs_founder = true - the 8 Sep ruling that nothing goes to the founder and every
--     approval is the CEO's. That enforcement is GONE at the database level after this file. The
--     RULING still stands; only the machine that enforced it is being removed, because the
--     founder's scope is "their names", and this routine carries the fn_kernel_ prefix. It reads
--     no phase table itself. Re-implement the same refusal under a non-kernel name when the
--     right agents exist. Note what is NOT lost with it: refunds keep
--     z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval on the refunds
--     table, neither of which is machinery.
--
--  3. Twelve surviving routines name a machinery object inside their bodies and will raise
--     42P01 (undefined_table) or 42883 (undefined_function) the next time they are called.
--     PL/pgSQL resolves those names at run time, not at CREATE time, so none of them BLOCK this
--     file - they simply stop working:
--       fn_customer_terms_accept         reads phase_d_acceptance_document, phase_d_object_record,
--                                        phase_c_workflow_run, phase_c_workflow_step_run and calls
--                                        fn_phase_d_object_write / fn_phase_d_dispatch_step. This
--                                        is the customer terms-acceptance path on the website.
--       fn_event_dispatch                reads phase_c_action_class - the event to workflow bridge.
--       fn_refund_decide                 reads phase_c_founder_identity.
--       fn_refund_founder_decision_only  reads phase_c_founder_identity.
--       fn_agent_silence_watch           reads phase_c_system_execution_wrapper.
--       fn_ws_exec_home                  reads phase_c_handoff_run (the OS exec-home tile).
--       fn_company_org_directory_sync    reads phase_b_workflow.
--       fn_company_self_knowledge_sync   reads phase_c_founder_identity and phase_b_workflow.
--       fn_page_high_agent_action        calls fn_kernel_source_emit.
--       qd_notify_refund_request         calls fn_kernel_source_emit.
--       qd_on_refund_resolved            calls fn_kernel_source_emit and fn_kernel_run_for.
--       trg_reveal_receipt               calls fn_kernel_source_emit.
--     Measured, and worth knowing before you go hunting: the last four are ALREADY ORPHANED.
--     pg_trigger holds no trigger for any of them today, so nothing invokes them and this file
--     changes nothing about them. stripe_webhook/index.ts still expects trg_reveal_receipt to
--     queue two reveal messages on transactions.revealed_at; it has not been doing so since
--     before this file was written, and that is a separate defect, not a consequence here.
--     Two further routines mention the machinery in COMMENTS ONLY and are unaffected:
--     fn_control_mode_require and fn_refund_amount_is_the_fee_paid.
--     No edge function calls any machinery routine: a scan of supabase/functions finds exactly
--     one machinery name in executable code, fn_kernel_paid_provider_gate, which is kept.
--
--  4. v_cron_stale loses its wrapper source. The view LEFT JOINed
--     phase_c_system_execution_wrapper to take activated_at from w.wrapped_at. It is REWRITTEN
--     here rather than dropped, because the view itself is a live staleness monitor over
--     cron.job and nothing else in it is machinery. After the rewrite, activated_at falls back
--     to the first recorded run (runs.first_any) - which is exactly what the COALESCE already
--     did whenever no wrapper row existed. One wrapper row exists today, so at most one job's
--     activated_at can move. Nothing depends on v_cron_stale (checked in pg_depend/pg_rewrite:
--     no dependent views).
--
--  5. Data is destroyed and there is no restore path in this file. The 29 machinery tables that
--     hold rows, largest first: phase_c_component 1520, kernel_maintenance_write 851,
--     phase_d_fixture_catalogue 157, phase_c_source_cutover 60, kernel_write_authority 47,
--     phase_c_action_class 26, phase_c_command_transition 24, phase_d_context_key_object 19,
--     kernel_retired_path 15, phase_c_command_state 13, phase_c_trace_policy 12,
--     phase_d_personal_identifier_class 11, phase_b_founder_boundary 10, phase_c_system_actor 10,
--     phase_c_change_request 9, phase_d_file_revision 7, phase_d_payment_state 6,
--     phase_c_founder_auth_event 6, phase_d_test_operation 5, phase_d_outbound_door 5,
--     phase_d_legal_source 5, phase_d_metadata_scan 5, phase_c_founder_identity 3,
--     phase_c_governance_decision 3, phase_d_founder_boundary_disposition 3,
--     kernel_signal_inbox 3, phase_d_acceptance_document 2, phase_d_fixture_secret 1,
--     phase_c_system_execution_wrapper 1. (n_live_tup at the time of measurement.)
--
-- METHOD NOTES for whoever applies or amends this:
--   * NOT ONE "cascade" APPEARS BELOW, deliberately. An unexpected dependency must FAIL the
--     apply inside the transaction, not quietly take a surviving object down with it.
--   * Every routine signature in section 4 came from pg_get_function_identity_arguments. A
--     "drop function if exists" with the WRONG argument list matches nothing and reports
--     SUCCESS. That is exactly how five routines survived an earlier sweep that looked green.
--   * Order: rewrite the view -> break one FK cycle -> drop triggers -> drop routines -> drop
--     tables children-before-parents -> drop sequences -> assert. Triggers must precede
--     routines because a trigger depends on its function; tables come after because a trigger
--     on a machinery table also depends on its function.
--   * phase_c_change_request and phase_c_governance_decision reference each other, so the table
--     drop order is not a DAG. The cycle is broken by dropping ONE constraint,
--     phase_c_governance_decision_change_request_ref_fkey, in section 2.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. Rewrite v_cron_stale so it no longer reads phase_c_system_execution_wrapper.
--    Same column names, order and types, so "create or replace view" is legal.
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_cron_stale as
 with j as (
   select job.jobid, job.jobname, job.schedule,
          split_part(job.schedule, ' '::text, 1) as m,
          split_part(job.schedule, ' '::text, 2) as h,
          split_part(job.schedule, ' '::text, 3) as dom,
          split_part(job.schedule, ' '::text, 5) as dow
     from cron.job
    where job.active
 ), iv as (
   select j.jobid, j.jobname, j.schedule, j.m, j.h, j.dom, j.dow,
          case
            when j.m ~~ '*/%'::text and j.m ~ '^\*/[0-9]+$'::text
              then substr(j.m, 3)::integer::double precision * '00:01:00'::interval
            when j.m ~ '^[0-9]+$'::text and j.h = '*'::text then '01:00:00'::interval
            when j.h ~~ '*/%'::text and j.h ~ '^\*/[0-9]+$'::text
              then substr(j.h, 3)::integer::double precision * '01:00:00'::interval
            when j.dom ~ '^[0-9]+$'::text then '31 days'::interval
            when j.dow ~ '^[0-6]$'::text then '7 days'::interval
            else '1 day'::interval
          end as every
     from j
 ), runs as (
   select job_run_details.jobid,
          max(job_run_details.start_time) as last_any,
          min(job_run_details.start_time) as first_any
     from cron.job_run_details
    group by job_run_details.jobid
 ), act as (
   -- WAS: coalesce(w.wrapped_at, runs.first_any), with
   --      left join phase_c_system_execution_wrapper w on w.jobid = iv.jobid.
   -- The wrapper table is dropped in section 5; the COALESCE fallback becomes the whole rule.
   select iv.jobid, iv.jobname, iv.schedule, iv.m, iv.h, iv.dom, iv.dow, iv.every,
          runs.last_any, runs.first_any as activated_at
     from iv
     left join runs on runs.jobid = iv.jobid
 )
 select jobid, jobname, schedule, every, activated_at, last_any,
        case
          when activated_at is null then 'active with no wrapper and no run ever recorded'::text
          else format('no run of any status since %s; schedule %s means one was due every %s'::text,
                      coalesce(last_any::text, 'never'::text), schedule, every)
        end as why
   from act
  where (activated_at is null or activated_at < (now() - 2::double precision * every))
    and (last_any is null or last_any < (now() - 2::double precision * every));

-- ---------------------------------------------------------------------------------------------
-- 2. Break the one FK cycle so the tables can be dropped children-before-parents:
--    phase_c_change_request -> phase_c_governance_decision -> phase_c_change_request.
-- ---------------------------------------------------------------------------------------------
alter table public.phase_c_governance_decision drop constraint phase_c_governance_decision_change_request_ref_fkey;

-- ---------------------------------------------------------------------------------------------
-- 3. Triggers - all 112, every one named from pg_trigger joined to pg_proc and pg_class.
--    The 72 on machinery tables would have fallen with their tables, but they are dropped
--    explicitly so that (a) the routine drops in section 4 cannot fail on a trigger dependency
--    and (b) this file names every trigger it destroys.
-- ---------------------------------------------------------------------------------------------

-- 3a. On tables that SURVIVE this file (40).
drop trigger if exists z00_kernel_truncate_guard on public.ad_decision;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.ap_bills;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.app_secrets;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.artifact_review;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.control_mode_session;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.customers;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.decision_log;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.decision_trace;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.gl_journal;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.gl_journal_lines;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.handoff_contract;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiries;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_answer;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_answer_conflict_value;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_answer_corroboration;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_answer_document;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_scope_disposition;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_state_audit;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_supplier_brief;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.inquiry_trade_candidate_evidence;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.internal_credential_audit;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.leads;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.llm_attempt;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.org_action_executor;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.org_authority;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.org_departments;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.org_phase_baseline;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.org_role;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.org_role_identity;  -- fn_kernel_truncate_guard
drop trigger if exists a00_org_tasks_founder_routing_refund_only on public.org_tasks;  -- fn_kernel_founder_routing_is_refund_only
drop trigger if exists z00_kernel_truncate_guard on public.org_tasks;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.os_incidents;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase1_rollback_log;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.procurement_approval_request;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.quotes;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.refunds;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.review_chain;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.security_audit_log;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.transactions;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.workflow_step_run;  -- fn_kernel_truncate_guard

-- 3b. On machinery tables (72). Includes t_emit_campaign_published on
--     phase_d_object_record, which runs the SURVIVING fn_emit_campaign_published - that routine
--     is kept, it simply loses its firing point along with the table.
drop trigger if exists z00_kernel_truncate_guard on public.kernel_signal_inbox;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.kernel_signal_type;  -- fn_kernel_truncate_guard
drop trigger if exists z10_signal_type_activation_guard on public.kernel_signal_type;  -- fn_kernel_signal_type_activation_guard
drop trigger if exists z00_kernel_truncate_guard on public.kernel_trigger_inbox;  -- fn_kernel_truncate_guard
drop trigger if exists a00_kernel_trigger_type_routing_guard on public.kernel_trigger_type;  -- fn_kernel_trigger_type_routing_guard
drop trigger if exists z00_kernel_truncate_guard on public.kernel_trigger_type;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_business_rule;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_dynamic_actor;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_founder_boundary;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_gate;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_handoff;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_step_state;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_step_transition;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_workflow;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_workflow_state;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_workflow_step;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_b_workflow_transition;  -- fn_kernel_truncate_guard
drop trigger if exists a05_phase_c_change_request_approval_is_derived on public.phase_c_change_request;  -- fn_phase_c_change_request_approval_is_derived
drop trigger if exists a10_change_request_approver_is_the_founder on public.phase_c_change_request;  -- fn_phase_c_founder_approver_guard
drop trigger if exists a15_phase_c_change_request_disposition_follows_approval on public.phase_c_change_request;  -- fn_phase_c_change_request_disposition_follows_approval
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_change_request;  -- fn_kernel_truncate_guard
drop trigger if exists a00_phase_c_readonly_exemption_guard on public.phase_c_component;  -- fn_phase_c_readonly_exemption_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_component;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_event_outbox;  -- fn_kernel_truncate_guard
drop trigger if exists z05_outbox_refuse_cancelled_subject on public.phase_c_event_outbox;  -- fn_kernel_outbox_refuse_cancelled_subject
drop trigger if exists a00_phase_c_founder_auth_event_is_server_minted on public.phase_c_founder_auth_event;  -- fn_phase_c_founder_auth_event_is_server_minted
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_founder_auth_event;  -- fn_kernel_truncate_guard
drop trigger if exists a00_phase_c_founder_identity_human_only on public.phase_c_founder_identity;  -- fn_phase_c_founder_identity_human_only
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_founder_identity;  -- fn_kernel_truncate_guard
drop trigger if exists a00_phase_c_governance_decision_is_session_backed on public.phase_c_governance_decision;  -- fn_phase_c_governance_decision_is_session_backed
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_governance_decision;  -- fn_kernel_truncate_guard
drop trigger if exists z10_phase_c_governance_decision_applies on public.phase_c_governance_decision;  -- fn_phase_c_governance_decision_applies
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_handoff_run;  -- fn_kernel_truncate_guard
drop trigger if exists z30_phase_c_handoff_sender_retains on public.phase_c_handoff_run;  -- fn_phase_c_handoff_sender_retains
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_source_cutover;  -- fn_kernel_truncate_guard
drop trigger if exists z10_source_signal_guard on public.phase_c_source_cutover;  -- fn_kernel_source_signal_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_system_execution;  -- fn_kernel_truncate_guard
drop trigger if exists z10_phase_c_system_execution_append_only on public.phase_c_system_execution;  -- fn_phase_c_system_execution_append_only
drop trigger if exists z90_system_execution_pair_guard on public.phase_c_system_execution;  -- fn_kernel_system_execution_pair_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_task;  -- fn_kernel_truncate_guard
drop trigger if exists z10_phase_c_overlay_not_accountable on public.phase_c_task;  -- fn_phase_c_overlay_may_not_dispatch
drop trigger if exists z90_phase_c_task_trace_subject on public.phase_c_task;  -- fn_phase_c_task_trace_subject
drop trigger if exists z95_phase_c_task_trace_committed on public.phase_c_task;  -- fn_phase_c_task_trace_committed
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_trace;  -- fn_kernel_truncate_guard
drop trigger if exists z10_phase_c_trace_append_only on public.phase_c_trace;  -- fn_phase_c_trace_append_only
drop trigger if exists z90_system_execution_pair_guard on public.phase_c_trace;  -- fn_kernel_system_execution_pair_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_workflow_run;  -- fn_kernel_truncate_guard
drop trigger if exists a01_phase_c_step_run_review_verdict on public.phase_c_workflow_step_run;  -- fn_phase_c_step_run_review_verdict_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_c_workflow_step_run;  -- fn_kernel_truncate_guard
drop trigger if exists z90_phase_c_step_run_trace_subject on public.phase_c_workflow_step_run;  -- fn_phase_c_step_run_trace_subject
drop trigger if exists z95_phase_c_step_run_trace_committed on public.phase_c_workflow_step_run;  -- fn_phase_c_step_run_trace_committed
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_capability_contract;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_capability_request;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_capability_result;  -- fn_kernel_truncate_guard
drop trigger if exists a10_phase_d_file_revision_reviewer on public.phase_d_file_revision;  -- fn_phase_d_file_revision_reviewer_independent
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_file_revision;  -- fn_kernel_truncate_guard
drop trigger if exists a11_phase_d_catalogue_payment_state_declared on public.phase_d_fixture_catalogue;  -- fn_phase_d_catalogue_payment_state_declared
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_fixture_catalogue;  -- fn_kernel_truncate_guard
drop trigger if exists a00_phase_d_stage_payment_state on public.phase_d_fixture_stage;  -- fn_phase_d_stage_payment_state_declared
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_fixture_stage;  -- fn_kernel_truncate_guard
drop trigger if exists a10_phase_d_legal_assertion_source on public.phase_d_legal_assertion;  -- fn_phase_d_legal_assertion_source_is_current
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_legal_assertion;  -- fn_kernel_truncate_guard
drop trigger if exists a00_phase_d_object_policy_guard on public.phase_d_object_record;  -- fn_phase_d_object_policy_guard
drop trigger if exists a30_phase_d_object_owner_is_stable on public.phase_d_object_record;  -- fn_phase_d_object_owner_is_stable
drop trigger if exists t_emit_campaign_published on public.phase_d_object_record;  -- fn_emit_campaign_published
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_object_record;  -- fn_kernel_truncate_guard
drop trigger if exists z40_phase_d_object_record_contract on public.phase_d_object_record;  -- fn_phase_d_object_record_contract
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_output_domain_registry;  -- fn_kernel_truncate_guard
drop trigger if exists a10_phase_d_normalisation_shape on public.phase_d_quote_normalisation;  -- fn_phase_d_normalisation_does_not_restate_the_original
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_quote_normalisation;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_scenario_record;  -- fn_kernel_truncate_guard
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_test_context_grant;  -- fn_kernel_truncate_guard

-- ---------------------------------------------------------------------------------------------
-- 4. Routines - 124 of the 125 that match. Signatures come from
--    pg_get_function_identity_arguments; do not retype them from memory or from a header.
--    fn_kernel_paid_provider_gate(p_model text) is deliberately absent from this list.
-- ---------------------------------------------------------------------------------------------
drop function if exists public.fn_kernel_assert_not_in_delivery(p_writer text);
drop function if exists public.fn_kernel_cancel(p_input jsonb);
drop function if exists public.fn_kernel_event_consume(p_outbox_id bigint);
drop function if exists public.fn_kernel_founder_routing_is_refund_only();
drop function if exists public.fn_kernel_handoff_accept(p_input jsonb);
drop function if exists public.fn_kernel_in_delivery();
drop function if exists public.fn_kernel_intake_execution(p_component text, p_trace_input jsonb);
drop function if exists public.fn_kernel_open_step(p_input jsonb);
drop function if exists public.fn_kernel_outbox_emit(p_input jsonb);
drop function if exists public.fn_kernel_outbox_refuse_cancelled_subject();
drop function if exists public.fn_kernel_record_maintenance_write(p_db_user text, p_session_role text, p_table text, p_op text, p_reason text, p_stack text);
drop function if exists public.fn_kernel_refund_ledger_state();
drop function if exists public.fn_kernel_review_decide(p_input jsonb);
drop function if exists public.fn_kernel_reviewer_independent(p_creator text, p_reviewer text);
drop function if exists public.fn_kernel_signal_submit(p_input jsonb);
drop function if exists public.fn_kernel_signal_type_activation_guard();
drop function if exists public.fn_kernel_sla_due(p_sla_policy_id text, p_from timestamp with time zone);
drop function if exists public.fn_kernel_source_emit(p_source_key text, p_input jsonb);
drop function if exists public.fn_kernel_source_emit_state();
drop function if exists public.fn_kernel_source_signal_guard();
drop function if exists public.fn_kernel_step_complete(p_input jsonb);
drop function if exists public.fn_kernel_step_successor(p_step_id text);
drop function if exists public.fn_kernel_system_execution_begin(p_input jsonb);
drop function if exists public.fn_kernel_system_execution_close(p_trace bigint, p_input jsonb);
drop function if exists public.fn_kernel_system_execution_pair_guard();
drop function if exists public.fn_kernel_trigger_submit(p_input jsonb);
drop function if exists public.fn_kernel_trigger_type_routing_guard();
drop function if exists public.fn_kernel_truncate_guard();
drop function if exists public.fn_kernel_workflow_start(p_input jsonb);
drop function if exists public.fn_kernel_write_guard();
drop function if exists public.fn_phase_a_organization_violations();
drop function if exists public.fn_phase_b_structure_digest();
drop function if exists public.fn_phase_c_actor_may_own(p_token text);
drop function if exists public.fn_phase_c_change_request_approval_is_derived();
drop function if exists public.fn_phase_c_change_request_disposition_follows_approval();
drop function if exists public.fn_phase_c_founder_approver_guard();
drop function if exists public.fn_phase_c_founder_auth_event_is_server_minted();
drop function if exists public.fn_phase_c_founder_identity_human_only();
drop function if exists public.fn_phase_c_founder_subject_bind(p_subject uuid);
drop function if exists public.fn_phase_c_gate_evaluate(p_gate_id text, p_evidence jsonb);
drop function if exists public.fn_phase_c_gates_for_step(p_step_id text);
drop function if exists public.fn_phase_c_governance_decide(p_input jsonb);
drop function if exists public.fn_phase_c_governance_decision_applies();
drop function if exists public.fn_phase_c_governance_decision_is_session_backed();
drop function if exists public.fn_phase_c_handoff_decide(p_handoff_run_id bigint, p_decision text, p_actor text, p_ctx jsonb);
drop function if exists public.fn_phase_c_handoff_packet_valid(p_handoff_id text, p_packet jsonb);
drop function if exists public.fn_phase_c_handoff_sender_retains();
drop function if exists public.fn_phase_c_lifecycle_event(p_workflow_id text, p_lifecycle text);
drop function if exists public.fn_phase_c_output_validate(p_contract text, p_output jsonb);
drop function if exists public.fn_phase_c_overlay_may_not_dispatch();
drop function if exists public.fn_phase_c_readonly_exemption_guard();
drop function if exists public.fn_phase_c_refund_execution_requires_decision();
drop function if exists public.fn_phase_c_require_founder(p_actor text);
drop function if exists public.fn_phase_c_resolve_actor(p_token text);
drop function if exists public.fn_phase_c_reviewer_independent(p_creator text, p_reviewer text);
drop function if exists public.fn_phase_c_step_event(p_step_id text, p_lifecycle text);
drop function if exists public.fn_phase_c_step_run_review_verdict_guard();
drop function if exists public.fn_phase_c_step_run_trace_committed();
drop function if exists public.fn_phase_c_step_run_trace_subject();
drop function if exists public.fn_phase_c_system_execution_append_only();
drop function if exists public.fn_phase_c_task_create(p_body jsonb);
drop function if exists public.fn_phase_c_task_trace_committed();
drop function if exists public.fn_phase_c_task_trace_subject();
drop function if exists public.fn_phase_c_task_transition(p_task_id bigint, p_to_state text, p_actor text, p_ctx jsonb);
drop function if exists public.fn_phase_c_task_transition_allowed(p_from text, p_to text);
drop function if exists public.fn_phase_c_trace_advance(p_trace_id bigint, p_state_after text, p_seal boolean, p_body jsonb);
drop function if exists public.fn_phase_c_trace_append_only();
drop function if exists public.fn_phase_c_trace_write(p_policy text, p_body jsonb);
drop function if exists public.fn_phase_c_workflow_start(p_workflow_id text, p_business_object_id text, p_ctx jsonb);
drop function if exists public.fn_phase_d_capability_answer(p_step_run_id bigint);
drop function if exists public.fn_phase_d_capability_request_open(p_input jsonb);
drop function if exists public.fn_phase_d_capability_result_accept(p_input jsonb);
drop function if exists public.fn_phase_d_catalogue_payment_state_declared();
drop function if exists public.fn_phase_d_comparison_visible(p_comparison_id text, p_caller_customer_id text, p_caller_kind text);
drop function if exists public.fn_phase_d_dispatch_step(p_input jsonb);
drop function if exists public.fn_phase_d_drive_workflow(p_input jsonb);
drop function if exists public.fn_phase_d_effect_produce(p_input jsonb);
drop function if exists public.fn_phase_d_effect_reachability();
drop function if exists public.fn_phase_d_effect_state();
drop function if exists public.fn_phase_d_file_revision_dispatchable(p_revision_ref text, p_dispatch_sha256 text);
drop function if exists public.fn_phase_d_file_revision_reviewer_independent();
drop function if exists public.fn_phase_d_fixture_context();
drop function if exists public.fn_phase_d_fixture_effect_payload(p_step_run_id bigint);
drop function if exists public.fn_phase_d_fixture_file_revision(p_package_ref text);
drop function if exists public.fn_phase_d_fixture_input(p_step_run_id bigint, p_scope text, p_key text);
drop function if exists public.fn_phase_d_fixture_inquiry_payload(p_label text);
drop function if exists public.fn_phase_d_fixture_output(p_step_id text, p_field_key text);
drop function if exists public.fn_phase_d_fixture_residue();
drop function if exists public.fn_phase_d_fixture_scenario(p_input jsonb);
drop function if exists public.fn_phase_d_founder_authority(p_run_id bigint, p_step_id text);
drop function if exists public.fn_phase_d_founder_authority_fixture(p_input jsonb);
drop function if exists public.fn_phase_d_gate_applies(p_gate_id text, p_step_id text);
drop function if exists public.fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb);
drop function if exists public.fn_phase_d_handler_execute(p_input jsonb);
drop function if exists public.fn_phase_d_handler_state();
drop function if exists public.fn_phase_d_handoff_accept(p_input jsonb);
drop function if exists public.fn_phase_d_handoff_packet_valid(p_handoff_id text, p_packet jsonb);
drop function if exists public.fn_phase_d_kernel_object_fixture(p_input jsonb);
drop function if exists public.fn_phase_d_legal_assertion_source_is_current();
drop function if exists public.fn_phase_d_legal_source_current(p_source_id text, p_require_authoritative boolean, p_as_of date);
drop function if exists public.fn_phase_d_normalisation_does_not_restate_the_original();
drop function if exists public.fn_phase_d_object_identity_state();
drop function if exists public.fn_phase_d_object_owner_is_stable();
drop function if exists public.fn_phase_d_object_policy_guard();
drop function if exists public.fn_phase_d_object_record_contract();
drop function if exists public.fn_phase_d_object_write(p_input jsonb);
drop function if exists public.fn_phase_d_outbound_requests_by_this_transaction(p_after bigint);
drop function if exists public.fn_phase_d_package_revisions_dispatchable(p_package_ref text);
drop function if exists public.fn_phase_d_quote_original_intact(p_revision_ref text);
drop function if exists public.fn_phase_d_recorded_review(p_step_run_id bigint);
drop function if exists public.fn_phase_d_ref(p_input jsonb);
drop function if exists public.fn_phase_d_ref_resolve(p_ref jsonb);
drop function if exists public.fn_phase_d_reveal_permitted(p_transaction_id text);
drop function if exists public.fn_phase_d_rule_applies(p_rule_id text, p_step_id text);
drop function if exists public.fn_phase_d_rule_can_refuse();
drop function if exists public.fn_phase_d_rule_check(p_rule_id text, p_context jsonb);
drop function if exists public.fn_phase_d_rule_state();
drop function if exists public.fn_phase_d_scenario_record_write(p_input jsonb);
drop function if exists public.fn_phase_d_schema_validate(p_schema_id text, p_payload jsonb);
drop function if exists public.fn_phase_d_stage_content(p_object_id text, p_scope text, p_key text);
drop function if exists public.fn_phase_d_stage_payment_state_declared();
drop function if exists public.fn_phase_d_step_context(p_step_run_id bigint);
drop function if exists public.fn_phase_d_step_inputs(p_step_run_id bigint);
drop function if exists public.fn_phase_d_test_context_open(p_input jsonb);

-- ---------------------------------------------------------------------------------------------
-- 5. Tables - all 80, children before parents, ordered from the pg_constraint FK graph.
-- ---------------------------------------------------------------------------------------------
drop table if exists public.kernel_adapter_failure;
drop table if exists public.kernel_maintenance_write;
drop table if exists public.kernel_retired_path;
drop table if exists public.kernel_signal_inbox;
drop table if exists public.kernel_signal_type;
drop table if exists public.kernel_trigger_inbox;
drop table if exists public.kernel_trigger_type;
drop table if exists public.kernel_write_authority;
drop table if exists public.phase_b_dynamic_actor;
drop table if exists public.phase_b_step_transition;
drop table if exists public.phase_b_workflow_transition;
drop table if exists public.phase_c_command_transition;
drop table if exists public.phase_c_command_state;
drop table if exists public.phase_c_event_outbox;
drop table if exists public.phase_b_event;
drop table if exists public.phase_c_handoff_run;
drop table if exists public.phase_c_overlay_binding;
drop table if exists public.phase_c_source_cutover;
drop table if exists public.phase_c_step_completion;
drop table if exists public.phase_c_system_execution;
drop table if exists public.phase_c_system_execution_wrapper;
drop table if exists public.phase_c_component;
drop table if exists public.phase_c_system_actor;
drop table if exists public.phase_c_task;
drop table if exists public.phase_c_action_class;
drop table if exists public.phase_c_task_transition;
drop table if exists public.phase_c_task_state;
drop table if exists public.phase_c_trace;
drop table if exists public.phase_c_trace_policy;
drop table if exists public.phase_c_workflow_step_run;
drop table if exists public.phase_b_step_state;
drop table if exists public.phase_c_workflow_run;
drop table if exists public.phase_d_acceptance_document;
drop table if exists public.phase_d_capability_contract;
drop table if exists public.phase_d_capability_result;
drop table if exists public.phase_d_capability_request;
drop table if exists public.phase_d_context_key_object;
drop table if exists public.phase_d_dispatch;
drop table if exists public.phase_d_effect_ledger;
drop table if exists public.phase_d_fixture_catalogue;
drop table if exists public.phase_d_fixture_secret;
drop table if exists public.phase_d_fixture_stage;
drop table if exists public.phase_d_business_object_binding;
drop table if exists public.phase_d_founder_boundary_disposition;
drop table if exists public.phase_b_founder_boundary;
drop table if exists public.phase_d_gate_contract;
drop table if exists public.phase_b_gate;
drop table if exists public.phase_d_handler_binding;
drop table if exists public.phase_d_handoff_acceptance;
drop table if exists public.phase_d_handoff_contract;
drop table if exists public.phase_b_handoff;
drop table if exists public.phase_b_sla_policy;
drop table if exists public.phase_d_legal_assertion;
drop table if exists public.phase_d_legal_source;
drop table if exists public.phase_d_metadata_scan;
drop table if exists public.phase_d_file_revision;
drop table if exists public.phase_d_object_record;
drop table if exists public.phase_d_object_reference_strategy;
drop table if exists public.phase_d_object_state_contract;
drop table if exists public.phase_d_object_write_map;
drop table if exists public.phase_d_outbound_door;
drop table if exists public.phase_d_output_domain_registry;
drop table if exists public.phase_d_handler_schema;
drop table if exists public.phase_b_workflow_step;
drop table if exists public.phase_b_workflow;
drop table if exists public.phase_b_business_object;
drop table if exists public.phase_b_workflow_state;
drop table if exists public.phase_d_payment_state;
drop table if exists public.phase_d_personal_identifier_class;
drop table if exists public.phase_d_quote_normalisation;
drop table if exists public.phase_d_rule_enforcement;
drop table if exists public.phase_b_business_rule;
drop table if exists public.phase_d_scenario_record;
drop table if exists public.phase_d_step_effect;
drop table if exists public.phase_d_test_context_grant;
drop table if exists public.phase_d_test_operation;
drop table if exists public.phase_c_change_request;
drop table if exists public.phase_c_governance_decision;
drop table if exists public.phase_c_founder_auth_event;
drop table if exists public.phase_c_founder_identity;

-- ---------------------------------------------------------------------------------------------
-- 6. Sequences - 24. Eleven of these are owned by a table above and are already gone by
--    now; the other thirteen are UNOWNED and would otherwise survive the table drop. "if
--    exists" covers both cases without needing to know which is which.
-- ---------------------------------------------------------------------------------------------
drop sequence if exists public.kernel_adapter_failure_failure_id_seq;
drop sequence if exists public.kernel_maintenance_write_maintenance_id_seq;
drop sequence if exists public.kernel_signal_inbox_signal_id_seq;
drop sequence if exists public.kernel_trigger_inbox_inbox_id_seq;
drop sequence if exists public.phase_c_event_outbox_outbox_id_seq;
drop sequence if exists public.phase_c_founder_auth_event_event_id_seq;
drop sequence if exists public.phase_c_governance_decision_decision_id_seq;
drop sequence if exists public.phase_c_handoff_run_handoff_run_id_seq;
drop sequence if exists public.phase_c_step_completion_completion_id_seq;
drop sequence if exists public.phase_c_task_task_id_seq;
drop sequence if exists public.phase_c_trace_trace_id_seq;
drop sequence if exists public.phase_c_workflow_run_run_id_seq;
drop sequence if exists public.phase_c_workflow_step_run_step_run_id_seq;
drop sequence if exists public.phase_d_capability_request_request_id_seq;
drop sequence if exists public.phase_d_capability_result_result_id_seq;
drop sequence if exists public.phase_d_dispatch_dispatch_id_seq;
drop sequence if exists public.phase_d_effect_ledger_effect_id_seq;
drop sequence if exists public.phase_d_handoff_acceptance_acceptance_id_seq;
drop sequence if exists public.phase_d_legal_assertion_assertion_id_seq;
drop sequence if exists public.phase_d_metadata_scan_scan_id_seq;
drop sequence if exists public.phase_d_object_record_record_id_seq;
drop sequence if exists public.phase_d_quote_normalisation_normalisation_id_seq;
drop sequence if exists public.phase_d_scenario_record_scenario_record_id_seq;
drop sequence if exists public.phase_d_test_context_grant_fixture_run_id_seq;

-- ---------------------------------------------------------------------------------------------
-- 7. The assertion. Counts AND names: a count alone does not tell you what was left behind.
-- ---------------------------------------------------------------------------------------------
do $check$
declare
  v_relations text;
  v_routines  text;
  v_nrel      integer;
  v_nfn       integer;
  v_gate      integer;
begin
  -- Every relation kind, not just tables: a leftover sequence or view still "pops the name".
  select count(*), coalesce(string_agg(c.relname || ' [' || c.relkind::text || ']', ', ' order by c.relname), '')
    into v_nrel, v_relations
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind in ('r','p','v','m','S')
     and (c.relname like 'phase\_a%' or c.relname like 'phase\_b%'
       or c.relname like 'phase\_c%' or c.relname like 'phase\_d%'
       or c.relname like 'kernel\_%');

  select count(*), coalesce(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                                       ', ' order by p.proname), '')
    into v_nfn, v_routines
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'fn\_phase\_a\_%' or p.proname like 'fn\_phase\_b\_%'
       or p.proname like 'fn\_phase\_c\_%' or p.proname like 'fn\_phase\_d\_%'
       or p.proname like 'fn\_kernel\_%')
     and p.proname <> 'fn_kernel_paid_provider_gate';

  if v_nrel <> 0 or v_nfn <> 0 then
    raise exception
      'the phase programme is NOT gone: % relation(s) [%] and % routine(s) [%] still match',
      v_nrel, v_relations, v_nfn, v_routines;
  end if;

  -- The other half of the assertion. The one thing that must SURVIVE is still here, with the
  -- right signature. A sweep that also took the paid-provider gate would satisfy both counts
  -- above and still be wrong.
  select count(*) into v_gate
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_kernel_paid_provider_gate'
     and pg_get_function_identity_arguments(p.oid) = 'p_model text';
  if v_gate <> 1 then
    raise exception 'fn_kernel_paid_provider_gate(p_model text) must survive; found % of it', v_gate;
  end if;

  raise notice 'phase programme removed entirely: 0 relations, 0 routines, paid-provider gate intact';
end
$check$;

commit;
