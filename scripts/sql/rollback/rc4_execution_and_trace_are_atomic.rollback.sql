-- ROLLBACK for scripts/sql/rc4_execution_and_trace_are_atomic.sql.
--
-- Removes the pair guard and the lifecycle, and restores the two kernel doors to the bodies that
-- wrote a trace with no execution row.
--
-- What it does NOT undo, deliberately:
--   * the reconstructed phase_c_system_execution row for trace 3730 — deleting it would recreate
--     the orphan the acceptance found, and phase_c_system_execution is append-only anyway;
--   * its entry in phase_c_historical_repair — that entry is the record that a reconstruction
--     happened, and removing it would leave a reconstruction with nothing saying so;
--   * the two phase_c_component rows for the doors — they describe what those functions are, which
--     is true whether or not the lifecycle is in place.
--
-- Rolling this back reinstates the defect: a sealed TRACE-SYSTEM-EXECUTION trace can again exist
-- with no execution subject, and fn_kernel_signal_submit can again write subject_ref 'signal:<id>'.

drop trigger if exists z90_system_execution_pair_guard on public.phase_c_system_execution;
drop trigger if exists z90_system_execution_pair_guard on public.phase_c_trace;
drop function if exists public.fn_kernel_system_execution_pair_guard();
drop function if exists public.fn_kernel_intake_execution(text, jsonb);
drop function if exists public.fn_kernel_system_execution_fail(bigint, jsonb);
drop function if exists public.fn_kernel_system_execution_finish(bigint, jsonb);
drop function if exists public.fn_kernel_system_execution_close(bigint, jsonb);
drop function if exists public.fn_kernel_system_execution_begin(jsonb);

-- The two doors return to their previous bodies, recovered from git rather than retyped:
--   git show 1fddbbd:scripts/sql/kernel_k10_trigger_inbox.sql   -- fn_kernel_trigger_submit
--   git show 1fddbbd:scripts/sql/kernel_k16_signal_service.sql  -- fn_kernel_signal_submit
-- applied with scripts/apply_sql.mjs. If a file has moved, the authority is the LAST entry in
-- scripts/sql/MANIFEST.txt before rc4 that defines the routine.
