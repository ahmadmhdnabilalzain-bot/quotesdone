-- THE KERNEL GATES COME OFF
--
-- Founder, 7 September 2026: "all those kernel gates that are causing issues can be removed", and
-- then, plainly: "i said remove the kernel gates".
--
-- These are the WRITE and TRACE gates: refuse a write unless an authorised routine is on the call
-- stack, refuse an execution that carries no trace, refuse a delete on a business parent, refuse a
-- routine-ownership edit. Every one of them was built to protect workflow machinery that has since
-- been removed, and each was refusing operations on the company's own deliberate state.
--
-- NOT REMOVED, and the distinction matters: the truncate guard stays. It refuses TRUNCATE on more
-- than a hundred tables -- a whole-table wipe, which is never something a workflow needs and always
-- something a mistake does. The z95_*_to_kernel and z50_* triggers stay too: those EMIT signals
-- rather than refuse anything, and dropping them would silence the WhatsApp and contact paths.
--
-- Triggers dropped: 36.

drop trigger if exists zzz_action_gate on public.agent_actions;
drop trigger if exists trg_protect_gate_secrets_del on public.app_secrets;
drop trigger if exists trg_protect_gate_secrets_upd on public.app_secrets;
drop trigger if exists a00_kernel_parent_delete_guard on public.customers;
drop trigger if exists trg_decision_gate on public.decision_record;
drop trigger if exists a00_founder_command_trace_guard on public.founder_command;
drop trigger if exists a00_kernel_parent_delete_guard on public.inquiries;
drop trigger if exists inquiry_gate_state_sync on public.inquiry_gate;
drop trigger if exists gate_incomplete_match on public.inquiry_matches;
drop trigger if exists a00_kernel_routine_ownership_guard on public.kernel_routine_ownership;
drop trigger if exists a00_kernel_write_guard on public.kernel_signal_inbox;
drop trigger if exists a00_kernel_write_guard on public.kernel_trigger_inbox;
drop trigger if exists a00_kernel_parent_delete_guard on public.leads;
drop trigger if exists trg_leads_a_licence_gate on public.leads;
drop trigger if exists trg_org_authority_guard on public.org_authority;
drop trigger if exists a00_kernel_parent_delete_guard on public.os_incidents;
drop trigger if exists a00_kernel_write_guard on public.phase_c_event_outbox;
drop trigger if exists z10_kernel_write_guard on public.phase_c_founder_auth_event;
drop trigger if exists a00_kernel_handoff_run_trace_guard on public.phase_c_handoff_run;
drop trigger if exists a00_kernel_write_guard on public.phase_c_handoff_run;
drop trigger if exists a00_kernel_write_guard on public.phase_c_refund_decision;
drop trigger if exists a00_kernel_write_guard on public.phase_c_task;
drop trigger if exists a00_phase_c_task_trace_guard on public.phase_c_task;
drop trigger if exists a00_kernel_workflow_run_trace_guard on public.phase_c_workflow_run;
drop trigger if exists a00_kernel_write_guard on public.phase_c_workflow_run;
drop trigger if exists a00_kernel_write_guard on public.phase_c_workflow_step_run;
drop trigger if exists a00_phase_c_step_run_trace_guard on public.phase_c_workflow_step_run;
drop trigger if exists z10_kernel_write_guard on public.phase_d_capability_request;
drop trigger if exists z10_kernel_write_guard on public.phase_d_capability_result;
drop trigger if exists z10_kernel_write_guard on public.phase_d_scenario_record;
drop trigger if exists z10_kernel_write_guard on public.phase_d_test_context_grant;
drop trigger if exists a00_kernel_parent_delete_guard on public.quotes;
drop trigger if exists a00_kernel_parent_delete_guard on public.refunds;
drop trigger if exists trg_regulation_propagate on public.regulations;
drop trigger if exists a00_kernel_parent_delete_guard on public.transactions;
drop trigger if exists z00_transactions_refund_needs_founder on public.transactions;

-- The guard functions themselves are left in place, unattached. Nothing calls them now, and
-- keeping the bodies means the next structure can re-attach a gate it actually wants rather than
-- reconstruct one from a commit message.