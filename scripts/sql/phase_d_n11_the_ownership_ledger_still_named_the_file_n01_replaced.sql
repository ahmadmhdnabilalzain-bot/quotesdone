-- N11 — the ownership ledger still named the file N01 replaced
--
-- MEASURED 24 Aug 2026 on htdblwldjkcgjvmqkbeh by
-- scripts/checks/application_source_of_truth.test.mjs, immediately after N01:
--
--   6. ledger claims the repository denies                     1 / 1225
--      public.fn_unsafe_match_eligibility_guard()  records source_file
--        scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql,
--        manifest order says
--        scripts/sql/phase_d_n01_the_writers_own_gate_never_asked_whether_the_supplier_was_approved.sql
--
-- THIS IS THE FOURTH TIME. D56, F28 and K09 each carry a title one word from this one, and each
-- fixed the same class of fact: public.kernel_routine_ownership records, per live routine, which
-- file the repository says is its canonical source, and a later file that REPLACES a routine
-- becomes the highest-sequence file defining it without the ledger moving with it.
--
-- Nothing about the routine's classification changes. It was QUOTESDONE_APPLICATION under
-- R4_MANIFEST_DEFINES_IT when K05 owned it and it still is; only the FILE moved, K05 -> N01. The
-- class and rule are not asserted by this file in any meaningful sense either: the AFTER trigger
-- a00_kernel_routine_ownership_guard re-derives them from public.fn_kernel_routine_ownership and
-- refuses the row if the recorded values are not the ones the facts support. They are written here
-- because the UPDATE must supply them, and they are CHECKED by the estate's own deriver.
--
-- WHY THE LEDGER IS NOT SIMPLY REGENERATED FROM THE MANIFEST. It could be, and then it would agree
-- with the manifest by construction and could never disagree with it — which is exactly what makes
-- it worth keeping as a separate record. A ledger derived from the thing it audits audits nothing.
-- The gate is right to be red until a human moves the row, and the fourth occurrence is an argument
-- for a smaller diff at the point of replacement, not for deleting the check.
--
-- ROLLBACK: scripts/sql/down/phase_d_n11_the_ownership_ledger_still_named_the_file_n01_replaced_down.sql
-- restores the row to K05. It is only correct while N01 itself is also rolled back; the file says so.

update public.kernel_routine_ownership
   set source_kind        = 'MANIFEST',
       source_file        = 'scripts/sql/phase_d_n01_the_writers_own_gate_never_asked_whether_the_supplier_was_approved.sql',
       ownership_class    = 'QUOTESDONE_APPLICATION',
       classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence           = 'owner=postgres, no extension, and a scripts/sql/MANIFEST.txt file defines it',
       justification      = null,   -- the CHECK permits one only for INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION
       recorded_at        = now()
 where schema_name = 'public'
   and routine_name = 'fn_unsafe_match_eligibility_guard';
