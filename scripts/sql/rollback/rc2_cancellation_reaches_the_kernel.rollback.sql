-- ROLLBACK for scripts/sql/rc2_cancellation_reaches_the_kernel.sql.
--
-- Restores the three routines to the bodies that were live on 17 Aug 2026 before root cause 2, and
-- removes the delivery guard. It does NOT drop phase_c_event_outbox.task_id: dropping a populated
-- column to undo a fix would destroy the relationships the fix recorded, and a nullable extra
-- column harms nothing if the rest is reverted.
--
-- Rolling this back reinstates two known defects, stated here so nobody rolls back by accident:
--   * fn_founder_command_control stops calling fn_kernel_cancel and leaves runs, step runs and
--     traces live beneath a cancelled command;
--   * fn_kernel_cancel goes back to matching payload->>'run_id', so workflow-start events survive
--     cancellation and its own leftover check cannot see them.
--
-- The three prior bodies are recovered from git rather than retyped here — retyping a body from
-- memory is how a rollback introduces a third version:
--
--   git show 1fddbbd:scripts/sql/kernel_k5_outbox.sql          # fn_kernel_outbox_emit
--   git show 1fddbbd:scripts/sql/kernel_k4_cancellation.sql    # fn_kernel_cancel
--   git show 1fddbbd:scripts/sql/phase_c_16_command_control.sql -- fn_founder_command_control
--
-- and applied with scripts/apply_sql.mjs. If a file name above has moved, the authority is
-- scripts/sql/MANIFEST.txt: the LAST file listed before rc2 that defines the routine.

drop trigger if exists z05_outbox_refuse_cancelled_subject on public.phase_c_event_outbox;
drop function if exists public.fn_kernel_outbox_refuse_cancelled_subject();
drop index if exists public.phase_c_event_outbox_task_id_idx;
