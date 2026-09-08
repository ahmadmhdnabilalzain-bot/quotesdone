-- the_phase_programme_and_its_kernel_are_removed.sql
--
-- Agent: ceo.  Measured against production htdblwldjkcgjvmqkbeh on 9 September 2026.
--
-- WHY THIS FILE EXISTS
--   The founder ruled on 7 September 2026: "i dont want a single routine or workflow or
--   decision prior 7 september. literally nothing", "phases A to D are irrelevant",
--   "anything related to OS can be removed".  From before 7 September he keeps only the
--   website content, the FAQ, company knowledge, leads and the API secrets.
--   This file is the removal of the Phase A-D programme and its kernel.
--
-- WHAT WAS MEASURED (catalogue only - pg_class, pg_constraint, pg_depend/pg_rewrite,
-- pg_trigger, pg_event_trigger, pg_policy, pg_attrdef, pg_proc.prosrc, cron.job - plus a
-- grep of supabase/functions).  Read this before changing anything below.
--
--   * The machinery is 96 tables (0 x phase_a, 14 x phase_b, 47 x phase_c, 35 x phase_d,
--     8 x kernel_) and 151 routines named fn_kernel_* / fn_phase_[abcd]_*.
--     There are NO phase_a tables.  154 indexes and 26 sequences hang off the 96 tables and
--     go with them.
--
--   * The removal is NOT one operation.  The machinery is still reachable from live callers
--     that sit OUTSIDE it, and while those callers stand, dropping underneath them would
--     leave broken functions rather than a clean estate.  Measured reachability:
--
--       - 21 public functions that are NOT phase/kernel routines read phase/kernel tables
--         or call phase/kernel routines.  Following those calls transitively reaches
--         116 of the 151 machinery routines, and those 116 routines between them name
--         all 96 tables.  So TODAY the number of tables that can be dropped is ZERO.
--
--       - The callers that do the reaching are, in descending weight:
--           fn_founder_command_{submit,classify,clarify,control,inbox,rollup,status,
--             thread,duplicate_result,trace_guard}   - the OS founder-command layer
--           fn_customer_terms_accept                  - LIVE: website terms acceptance,
--             calls fn_phase_d_dispatch_step and fn_phase_d_object_write
--           fn_page_high_agent_action, qd_notify_refund_request, qd_on_refund_resolved,
--             trg_reveal_receipt                      - LIVE: all call fn_kernel_source_emit
--           fn_workflow_step_claim, fn_workflow_step_sweep - LIVE: fn_kernel_paid_provider_gate
--           fn_red_view_alert, fn_agent_silence_watch, fn_ws_exec_home, fn_event_dispatch,
--             fn_company_org_directory_sync, fn_company_self_knowledge_sync,
--             fn_control_mode_require, fn_refund_decide, fn_refund_founder_decision_only,
--             fn_founder_approval_refund_only
--
--       - Five foreign keys point INTO the machinery from outside it:
--           founder_command_progress_note.task_id  -> phase_c_task
--           founder_command_task_link.task_id      -> phase_c_task
--           founder_command_workflow_link.workflow_id -> phase_b_workflow
--           founder_command_workflow_link.run_id   -> phase_c_workflow_run
--           founder_approval_request.action_class  -> phase_c_action_class
--
--       - One view reads the machinery: public.v_cron_stale joins
--         phase_c_system_execution_wrapper.
--
--       - The 76 edge functions in supabase/functions name exactly five machinery objects:
--           supabase/functions/os_api/index.ts        - fn_kernel_cancel,
--                                                        fn_phase_c_require_founder,
--                                                        phase_c_command_rule,
--                                                        phase_c_founder_identity
--           supabase/functions/_shared/paid_gate.ts   - fn_kernel_paid_provider_gate
--
--       - cron: exactly one job names the machinery - jobid 34 "wa_flush",
--         `select public.fn_kernel_cron_exec(34);`, and it is ACTIVE = false.
--
--       - No RLS policy, no column default and no CHECK constraint outside the machinery
--         references it.  (The one CHECK that greps positive,
--         ad_spend_policy_learning_phase_days_check, matches on the word "phase" only.)
--
-- WHAT IS DELIBERATELY NOT DROPPED, EVER, BY THIS FILE
--   * public.kernel_maintenance_write and public.fn_kernel_record_maintenance_write.
--     fn_kernel_truncate_guard writes that table and is attached as z00_kernel_truncate_guard
--     to 45 tables OUTSIDE the machinery, among them customers, quotes, leads, transactions,
--     refunds, app_secrets, gl_journal and security_audit_log.  It is live estate protection.
--   * public.fn_kernel_paid_provider_gate(text) - called by supabase/functions/_shared/paid_gate.ts.
--   * public.fn_kernel_cancel(jsonb) and public.fn_phase_c_require_founder(text) - called by
--     supabase/functions/os_api/index.ts.
--   * public.fn_kernel_founder_routing_is_refund_only() - trigger
--     a00_org_tasks_founder_routing_refund_only on org_tasks; enforces the current
--     refunds-only boundary.
--   * public.fn_phase_c_no_new_founder_approval_path() - triggers
--     z10_phase_c_no_new_release_approval on founder_release_approval and
--     z10_phase_c_no_new_procurement_approval on procurement_approval_request.  Named for
--     phase C but it enforces the POST-7-September rule that approvals no longer reach the
--     founder.  Dropping it re-opens the path it closes.
--   * EVERY event trigger.  In particular trg_enforce_rls_new_tables ->
--     fn_enforce_rls_on_new_tables, which puts row-level security on every new table.
--     Event triggers do not live in pg_trigger and are invisible to a pg_trigger scan.
--     This file touches none of them.
--   * Every guard function whose trigger sits on a table that SURVIVES this file.  A guard
--     is not dead merely because no other routine calls it by name - its caller is its
--     trigger.  33 such guards were considered and 31 are kept for exactly this reason.
--   * public.fn_phase1_* and public.fn_org_phase_baseline_append_only.  phase1_* is a
--     different, older subject and is out of scope here.
--
-- WHAT THIS FILE DOES DROP
--   The subset that becomes unreachable once the OS founder-command layer is retired:
--   15 tables and 20 routines.  It refuses to run before that, see the precondition block.
--   Row counts at time of measurement (9 Sep 2026):
--     phase_b_exception 0                    phase_c_command_intent 0
--     phase_c_command_rule 0                 phase_c_command_specificity_signal 6
--     phase_c_component_trace_exemption 23   phase_c_event_binding 0
--     phase_c_event_delivery_attempt 0       phase_c_gate_binding 0
--     phase_c_handoff_binding 0              phase_c_kernel_epoch 1
--     phase_c_package_erratum 8              phase_c_role_binding 0
--     phase_c_rule_binding 0                 phase_c_step_binding 0
--     phase_c_workflow_binding 0
--   No table outside these 15 has a foreign key to any of them; no view reads them.
--
-- WHAT REMAINS AFTER THIS FILE - the BLOCKED list, and why
--   81 of the 96 tables and 131 of the 151 routines stay, because live callers still reach
--   them.  They come out in a LATER file, and only after these are gone first:
--     1. the founder-command layer (founder_command*, fn_founder_command_*, os_api edge fn),
--     2. fn_customer_terms_accept re-pointed off fn_phase_d_dispatch_step /
--        fn_phase_d_object_write,
--     3. fn_kernel_source_emit re-pointed off, or retired with, fn_page_high_agent_action /
--        qd_notify_refund_request / qd_on_refund_resolved / trg_reveal_receipt,
--     4. fn_workflow_step_claim / fn_workflow_step_sweep off fn_kernel_paid_provider_gate,
--     5. v_cron_stale rewritten without phase_c_system_execution_wrapper,
--     6. the five inbound foreign keys above removed with their child tables.
--   Until each of those is measured gone, every table it reaches is BLOCKED, not dropped.
--
-- NO CASCADE ANYWHERE.  Every statement names its exact target.  An unexpected dependency
-- must fail the apply, not silently take a neighbour with it.

begin;

-- ---------------------------------------------------------------------------
-- Precondition.  This file is only safe once the OS founder-command layer is gone.
-- ---------------------------------------------------------------------------
do $precondition$
declare
  v_blockers text;
  v_cron     int;
begin
  select string_agg(proname, ', ' order by proname)
    into v_blockers
    from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in (
       'fn_founder_command_submit',   -- reaches phase_c_command_rule, phase_c_command_intent,
                                      -- fn_phase_c_overlay_invoke
       'fn_founder_command_classify', -- reaches phase_c_command_rule, fn_phase_c_command_specificity
       'fn_founder_command_inbox',    -- reaches fn_phase_c_handoff_overdue,
                                      -- fn_phase_c_non_refund_founder_approvals
       'fn_red_view_alert'            -- reaches fn_kernel_all_boards
     );

  if v_blockers is not null then
    raise exception
      'REFUSED: the OS founder-command layer is still present (%). Retire it first; this file drops what it reaches.',
      v_blockers;
  end if;

  select count(*) into v_cron from cron.job where command like '%fn_kernel_cron_exec%';
  if v_cron > 0 then
    raise exception
      'REFUSED: % cron job(s) still call fn_kernel_cron_exec (jobid 34 "wa_flush" at time of writing). Unschedule first.',
      v_cron;
  end if;
end
$precondition$;

-- ---------------------------------------------------------------------------
-- 1. Triggers.  Only the ones on tables this file drops; each is named exactly.
--    z00_kernel_truncate_guard on these two tables goes with the table and is NOT
--    named here, because fn_kernel_truncate_guard itself survives.
-- ---------------------------------------------------------------------------
drop trigger if exists a00_phase_c_event_binding_status_guard on public.phase_c_event_binding;
drop trigger if exists z10_phase_c_kernel_epoch_immutable      on public.phase_c_kernel_epoch;

-- ---------------------------------------------------------------------------
-- 2. Routines.  Exact identity arguments from pg_get_function_identity_arguments.
--    None of these is reached from any surviving routine, edge function, cron job
--    or trigger once the precondition above holds.
-- ---------------------------------------------------------------------------
drop function if exists public.fn_phase_c_event_binding_status_guard();
drop function if exists public.fn_phase_c_kernel_epoch_immutable();

drop function if exists public.fn_kernel_all_boards();
drop function if exists public.fn_kernel_cron_exec(p_jobid bigint);
drop function if exists public.fn_kernel_outbox_deliver(p_limit integer, p_worker text);
drop function if exists public.fn_kernel_system_execution_trace(p_input jsonb);
drop function if exists public.fn_kernel_system_trace_state();

drop function if exists public.fn_phase_b_effective_errata();
drop function if exists public.fn_phase_b_gate_attachment();

drop function if exists public.fn_phase_c_command_specificity(p_text text);
drop function if exists public.fn_phase_c_event_binding_status(p_event_id text);
drop function if exists public.fn_phase_c_event_consume(p_outbox_id bigint);
drop function if exists public.fn_phase_c_event_ingress(p_event_id text, p_business_object_id text, p_ctx jsonb);
drop function if exists public.fn_phase_c_handoff_overdue();
drop function if exists public.fn_phase_c_invariants();
drop function if exists public.fn_phase_c_non_refund_founder_approvals();
drop function if exists public.fn_phase_c_outbox_claim(p_limit integer);
drop function if exists public.fn_phase_c_outbox_deliver(p_limit integer, p_worker text);
drop function if exists public.fn_phase_c_overlay_invoke(p_overlay_id text, p_ctx jsonb);
drop function if exists public.fn_phase_c_step_advance(p_run_id bigint, p_step_id text, p_actor text, p_body jsonb);

-- ---------------------------------------------------------------------------
-- 3. Tables.  None of the 15 is the parent of a foreign key from any surviving
--    table, so no ordering among them is required; they are listed alphabetically.
--    Their indexes and sequences go with them.  No CASCADE: if a dependency has
--    appeared since the measurement, this statement fails and the whole file rolls back.
-- ---------------------------------------------------------------------------
drop table if exists public.phase_b_exception;
drop table if exists public.phase_c_command_intent;
drop table if exists public.phase_c_command_rule;
drop table if exists public.phase_c_command_specificity_signal;
drop table if exists public.phase_c_component_trace_exemption;
drop table if exists public.phase_c_event_binding;
drop table if exists public.phase_c_event_delivery_attempt;
drop table if exists public.phase_c_gate_binding;
drop table if exists public.phase_c_handoff_binding;
drop table if exists public.phase_c_kernel_epoch;
drop table if exists public.phase_c_package_erratum;
drop table if exists public.phase_c_role_binding;
drop table if exists public.phase_c_rule_binding;
drop table if exists public.phase_c_step_binding;
drop table if exists public.phase_c_workflow_binding;

-- ---------------------------------------------------------------------------
-- 4. Proof.  The machinery this file names is gone, and the machinery it
--    deliberately keeps is still there.
-- ---------------------------------------------------------------------------
do $check$
declare
  v_tables int;
  v_fns    int;
  v_keep   int;
  v_left   int;
begin
  select count(*) into v_tables
    from pg_class
   where relnamespace = 'public'::regnamespace and relkind = 'r'
     and relname in ('phase_b_exception','phase_c_command_intent','phase_c_command_rule',
                     'phase_c_command_specificity_signal','phase_c_component_trace_exemption',
                     'phase_c_event_binding','phase_c_event_delivery_attempt',
                     'phase_c_gate_binding','phase_c_handoff_binding','phase_c_kernel_epoch',
                     'phase_c_package_erratum','phase_c_role_binding','phase_c_rule_binding',
                     'phase_c_step_binding','phase_c_workflow_binding');

  select count(*) into v_fns
    from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('fn_phase_c_event_binding_status_guard','fn_phase_c_kernel_epoch_immutable',
                     'fn_kernel_all_boards','fn_kernel_cron_exec','fn_kernel_outbox_deliver',
                     'fn_kernel_system_execution_trace','fn_kernel_system_trace_state',
                     'fn_phase_b_effective_errata','fn_phase_b_gate_attachment',
                     'fn_phase_c_command_specificity','fn_phase_c_event_binding_status',
                     'fn_phase_c_event_consume','fn_phase_c_event_ingress',
                     'fn_phase_c_handoff_overdue','fn_phase_c_invariants',
                     'fn_phase_c_non_refund_founder_approvals','fn_phase_c_outbox_claim',
                     'fn_phase_c_outbox_deliver','fn_phase_c_overlay_invoke',
                     'fn_phase_c_step_advance');

  if v_tables <> 0 or v_fns <> 0 then
    raise exception 'FAILED: % of 15 tables and % of 20 routines survived the drop.', v_tables, v_fns;
  end if;

  -- The estate protection this file must never have touched.
  select count(*) into v_keep
    from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('fn_kernel_truncate_guard','fn_kernel_record_maintenance_write',
                     'fn_kernel_paid_provider_gate','fn_kernel_cancel',
                     'fn_phase_c_require_founder','fn_kernel_founder_routing_is_refund_only',
                     'fn_phase_c_no_new_founder_approval_path','fn_kernel_source_emit',
                     'fn_phase_d_dispatch_step','fn_phase_d_object_write',
                     'fn_enforce_rls_on_new_tables');
  if v_keep <> 11 then
    raise exception 'FAILED: only % of the 11 must-keep routines are present.', v_keep;
  end if;

  if not exists (select 1 from pg_class
                  where relnamespace='public'::regnamespace and relname='kernel_maintenance_write') then
    raise exception 'FAILED: kernel_maintenance_write is gone; fn_kernel_truncate_guard has nowhere to write.';
  end if;

  if not exists (select 1 from pg_event_trigger where evtname='trg_enforce_rls_new_tables') then
    raise exception 'FAILED: the event trigger trg_enforce_rls_new_tables is gone.';
  end if;

  -- What is still standing, for the record.  This is the BLOCKED remainder.
  select count(*) into v_left
    from pg_class
   where relnamespace='public'::regnamespace and relkind='r'
     and (relname like 'phase\_%' or relname like 'kernel\_%');
  raise notice 'phase/kernel tables remaining (BLOCKED, later file): %', v_left;
end
$check$;

commit;
