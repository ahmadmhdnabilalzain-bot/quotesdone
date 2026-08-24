-- O17 — the ownership ledger still named the files O01 replaced
--
-- MEASURED 24 Aug 2026 on htdblwldjkcgjvmqkbeh by
-- scripts/checks/application_source_of_truth.test.mjs, after the O-series:
--
--   6. ledger claims the repository denies                     2 / 1225
--      public.fn_phase_c_overlay_may_not_dispatch()  records source_file
--        scripts/sql/phase_c_10_command_overlay_and_raise_fixes.sql
--      public.fn_phase_c_task_state_guard()          records source_file
--        scripts/sql/phase_c_03_runtime_core.sql
--      manifest order says both are now
--        scripts/sql/phase_d_o01_two_identity_controls_whose_refusals_had_no_machine_name.sql
--
-- THIS IS THE FIFTH TIME. D56, F28, K09 and N11 each carry a title one word from this one, and each
-- fixed the same class of fact: public.kernel_routine_ownership records, per live routine, which
-- file the repository says is its canonical source, and a later file that REPLACES a routine becomes
-- the highest-sequence file defining it without the ledger moving with it.
--
-- N11's header ends with the right conclusion and this file is the evidence for it: *"the fourth
-- occurrence is an argument for a smaller diff at the point of replacement, not for deleting the
-- check."* Five occurrences is an argument for the same thing more loudly. The pattern is
-- mechanical — replace a routine in a new file, move its ledger row in the same file — and it is
-- missed because the ledger is not what the author is thinking about while writing the guard.
--
-- Nothing about either routine's classification changes. Both were QUOTESDONE_APPLICATION under
-- R4_MANIFEST_DEFINES_IT before O01 and both still are; only the FILE moved. The class and rule are
-- not really asserted here either: the AFTER trigger a00_kernel_routine_ownership_guard re-derives
-- them from public.fn_kernel_routine_ownership and refuses the row if the recorded values are not
-- the ones the facts support. They are written because the UPDATE must supply them, and they are
-- CHECKED by the estate's own deriver.
--
-- WHY THE LEDGER IS NOT SIMPLY REGENERATED FROM THE MANIFEST — N11 said it and it is still true. It
-- could be, and then it would agree with the manifest by construction and could never disagree with
-- it, which is exactly what makes it worth keeping as a separate record. A ledger derived from the
-- thing it audits audits nothing. The gate is right to be red until a human moves the row.
--
-- ROLLBACK: scripts/sql/down/phase_d_o17_the_ownership_ledger_still_named_the_files_o01_replaced_down.sql
-- restores both rows. It is only correct while O01 itself is also rolled back; the file says so.

update public.kernel_routine_ownership
   set source_kind        = 'MANIFEST',
       source_file        = 'scripts/sql/phase_d_o01_two_identity_controls_whose_refusals_had_no_machine_name.sql',
       ownership_class    = 'QUOTESDONE_APPLICATION',
       classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence           = 'owner=postgres, no extension, and a scripts/sql/MANIFEST.txt file defines it',
       justification      = null,   -- the CHECK permits one only for INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION
       recorded_at        = now()
 where schema_name = 'public'
   and routine_name in ('fn_phase_c_overlay_may_not_dispatch', 'fn_phase_c_task_state_guard');
