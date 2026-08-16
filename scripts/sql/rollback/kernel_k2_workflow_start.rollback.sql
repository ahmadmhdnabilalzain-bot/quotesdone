-- ============================================================================================
-- ROLLBACK — KERNEL K2 (fn_kernel_workflow_start)
--
-- Apply BEFORE kernel_k5_factual_outbox.rollback.sql: K2 calls fn_kernel_outbox_emit,
-- fn_kernel_assert_not_in_delivery and fn_kernel_sla_due, all of which K5's rollback removes.
--
-- WHAT THIS DOES: removes the new creator. Nothing else changes. fn_phase_c_workflow_start,
-- fn_phase_c_event_ingress and fn_phase_c_event_consume were never modified by K2, so the old
-- path — including its double emission — is exactly where it was.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: it does not delete the workflow runs, step runs, tasks,
-- handoff runs, traces or outbox rows that fn_kernel_workflow_start created. Those are records of
-- work that really was dispatched to a real accountable role. Removing them would destroy the
-- evidence and orphan whatever the owner has already done against them. If a specific run must be
-- stopped, that is fn_kernel_cancel's job (K4), which closes it WITH a sealed trace and a stated
-- reason, and asserts that no queued derived work survives.
--
-- If K2b was applied, roll it back FIRST — fn_founder_command_submit calls this function, and
-- dropping it under a live caller turns every founder command into a 42883.
-- ============================================================================================

do $guard$
begin
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname = 'fn_founder_command_submit'
                and p.prosrc like '%fn_kernel_workflow_start%') then
    raise exception 'fn_founder_command_submit still calls fn_kernel_workflow_start — roll back K2b first'
      using errcode = '2BP01',
            hint = 'Restore the pre-K2b definition of fn_founder_command_submit, then re-run this file.';
  end if;
end $guard$;

drop function if exists public.fn_kernel_workflow_start(jsonb);

-- What the kernel created, and is being left in place on purpose:
--   select count(*) from public.phase_c_event_outbox where producer = 'kernel:workflow_start';
--   select count(*) from public.phase_c_workflow_run r
--    where exists (select 1 from public.phase_c_event_outbox o
--                   where o.workflow_run_id = r.run_id and o.producer = 'kernel:workflow_start');
