-- ROLLBACK for scripts/sql/rc3_active_signals_are_executable.sql.
--
-- Returns the five signal types to 'inactive' and removes both enforcement triggers. The
-- activation_reason and activation_changed_at columns are NOT dropped: they hold the record of why
-- each type is in the state it is in, and destroying that record to undo a change is how the next
-- session ends up guessing again.
--
-- Rolling this back reinstates the defect the acceptance found: ten ACTIVE sources pointing at
-- signal types that refuse every submission, while fn_kernel_cutover_measure reports them CUT_OVER.
-- Stated here so nobody rolls back by accident.

drop trigger if exists z10_source_signal_guard on public.phase_c_source_cutover;
drop trigger if exists z10_signal_type_activation_guard on public.kernel_signal_type;

update public.kernel_signal_type set
  activation_state = 'inactive',
  activation_changed_at = now(),
  activation_reason = 'ROLLED BACK from active: scripts/sql/rollback/rc3_active_signals_are_executable.rollback.sql. '
                   || 'Every ACTIVE source naming this type is refused again at submission.'
where signal_type in ('clarification.response','followup.due','provider.callback',
                      'supplier.acknowledgement','supplier.quote_revision');

drop function if exists public.fn_kernel_source_signal_guard();
drop function if exists public.fn_kernel_signal_type_activation_guard();

-- fn_kernel_cutover_measure returns to the body that judged CUT_OVER on caller detection alone:
--   git show 1fddbbd:scripts/sql/kernel_k34_cutover_measure.sql
-- applied with scripts/apply_sql.mjs. The authority for which file that is, if it has moved, is
-- the LAST entry in scripts/sql/MANIFEST.txt before rc3 that defines the routine.
