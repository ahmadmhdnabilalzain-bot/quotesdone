-- Rollback for K18, the kernel-only write guard.
--
-- This removes the ONLY thing standing between a new Edge Function, a service-role session or a
-- stray migration and a direct insert into phase_c_workflow_run, phase_c_task,
-- phase_c_workflow_step_run, phase_c_handoff_run, kernel_trigger_inbox, kernel_signal_inbox,
-- phase_c_event_outbox or phase_c_refund_decision. After it, "only the kernel writes business
-- work" is a convention again, and §7 of the brief says in as many words not to rely on one.
-- Run it only to restore the pre-2026-08-17 shape, never as a fix.
--
-- If the guard is refusing a legitimate writer, the answer is almost never this file. It is one
-- row in public.kernel_write_authority naming the routine, the table and why — which is a
-- migration somebody reads, instead of removing the guard for everyone.
--
-- kernel_maintenance_write is NOT dropped. It records every hand-made write to a business-work
-- table, with its reason and call stack, and that history outlives the guard that collected it.
-- Deleting it would erase the only evidence of who touched what by hand.

begin;

do $detach$
declare t text;
begin
  foreach t in array array[
    'phase_c_workflow_run','phase_c_workflow_step_run','phase_c_task','phase_c_handoff_run',
    'kernel_trigger_inbox','kernel_signal_inbox','phase_c_event_outbox','phase_c_refund_decision']
  loop
    execute format('drop trigger if exists a00_kernel_write_guard on public.%I', t);
  end loop;
end
$detach$;

drop function if exists public.fn_kernel_write_guard_state();
drop function if exists public.fn_kernel_write_guard();
drop table if exists public.kernel_write_authority;

commit;
