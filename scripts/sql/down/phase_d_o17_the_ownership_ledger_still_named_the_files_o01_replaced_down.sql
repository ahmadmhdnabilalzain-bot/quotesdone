-- DOWN for O17. Classification: DATA_ONLY — two rows of public.kernel_routine_ownership.
--
-- ONLY CORRECT WHILE O01 IS ALSO ROLLED BACK. These two rows say which file the repository claims
-- is each routine's canonical source; with O01 still applied, restoring them re-creates exactly the
-- red `application_source_of_truth` reported (2 of 1225, "ledger claims the repository denies").
UPDATE public.kernel_routine_ownership
   SET source_kind = 'MANIFEST',
       source_file = 'scripts/sql/phase_c_10_command_overlay_and_raise_fixes.sql',
       recorded_at = now()
 WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_overlay_may_not_dispatch';

UPDATE public.kernel_routine_ownership
   SET source_kind = 'MANIFEST',
       source_file = 'scripts/sql/phase_c_03_runtime_core.sql',
       recorded_at = now()
 WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_task_state_guard';
