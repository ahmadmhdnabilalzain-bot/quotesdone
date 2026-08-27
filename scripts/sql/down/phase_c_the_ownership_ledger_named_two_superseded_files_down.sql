-- DOWN for phase_c_the_ownership_ledger_named_two_superseded_files.sql.
--
-- It restores the two public.kernel_routine_ownership rows to the superseded files they named
-- before 27 Aug 2026. Applying it puts scripts/checks/application_source_of_truth.test.mjs back to
-- "ledger claims the repository denies 2 / 1225" — the ledger pointing at files that no longer
-- define those routines. It changes no routine body and no behaviour; only what the estate says
-- about where two routines come from.

update public.kernel_routine_ownership set
       source_file = 'scripts/sql/kernel_k4_cancellation.sql',
       evidence = 'restored by the down script of phase_c_the_ownership_ledger_named_two_superseded_files.sql'
 where schema_name = 'public' and routine_name = 'fn_kernel_orphaned_work';

update public.kernel_routine_ownership set
       source_file = 'scripts/sql/seventy_five_employees_were_rated_one_point_above_probation_for_doing_nothing.sql',
       evidence = 'restored by the down script of phase_c_the_ownership_ledger_named_two_superseded_files.sql'
 where schema_name = 'public' and routine_name = 'fn_reputation_recompute';
