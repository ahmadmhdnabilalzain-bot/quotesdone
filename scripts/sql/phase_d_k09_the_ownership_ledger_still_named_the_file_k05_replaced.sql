-- K09 — the ownership ledger still named the file K05 replaced
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh, by
-- scripts/checks/application_source_of_truth.test.mjs, immediately after K05:
--
--   6. ledger claims the repository denies                     2 / 1225
--      public.fn_unsafe_match_eligibility_guard()  records source_file
--        scripts/sql/v3_repair_09_unsafe_safeguards.sql, manifest order says
--        scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql
--      public.trg_gate_incomplete_match()  recorded HISTORICAL_APPLICATION,
--        repository derives QUOTESDONE_APPLICATION
--
-- public.kernel_routine_ownership records, for every live routine, which file the repository says
-- is its canonical source and what that makes it. K05 replaced two product trigger functions on
-- public.inquiry_matches and became the highest-sequence file defining them, and the ledger was not
-- moved with them. The gate is right and the ledger was stale.
--
--   fn_unsafe_match_eligibility_guard  was already QUOTESDONE_APPLICATION under R4; only the file
--                                      moved, from v3_repair_09_unsafe_safeguards.sql to K05.
--   trg_gate_incomplete_match          was HISTORICAL_APPLICATION under R5 — "no MANIFEST file
--                                      defines it, tracked SQL elsewhere does", which was true while
--                                      its only definition lived in
--                                      supabase/migrations_history/20260708131431_rfq_qualification_gate_and_clarify.sql.
--                                      A MANIFEST file defines it now, so R4 fires and the class is
--                                      QUOTESDONE_APPLICATION. The class is not asserted here: the
--                                      AFTER trigger a00_kernel_routine_ownership_guard re-derives
--                                      it from public.fn_kernel_routine_ownership and refuses the
--                                      row if the recorded class and rule are not the ones the facts
--                                      support, so these values are checked at write time by the
--                                      estate's own deriver and not by this file.
--
-- AND IT SETTLES THE QUESTION K05'S DOWN SCRIPT HAD TO ANSWER BY HAND. The rollback generator
-- classifies a routine as INTRODUCED when exactly one Phase D file defines it, which cannot tell a
-- routine a Phase D file CREATED from a pre-existing product routine a Phase D file REPLACED. The
-- canonical engine can: it resolves trg_gate_incomplete_match's predecessor to the 8 July 2026
-- migration above. That is recorded in the justification below so the next reader does not have to
-- re-derive it. It is recorded HERE and not in the row: public.kernel_routine_ownership carries a
-- CHECK that permits a justification only on an INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION row, and
-- neither of these is one. The column stays null and this header is the record.
--
-- ROLLBACK: scripts/sql/down/phase_d_k09_the_ownership_ledger_still_named_the_file_k05_replaced_down.sql
-- restores both rows to the values above. It is only correct while K05 itself is also rolled back;
-- the file says so.

update public.kernel_routine_ownership
   set source_kind        = 'MANIFEST',
       source_file        = 'scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql',
       ownership_class    = 'QUOTESDONE_APPLICATION',
       classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence           = 'owner=postgres, no extension, and a scripts/sql/MANIFEST.txt file defines it',
       justification      = null,   -- the CHECK permits one only for INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION
       recorded_at        = now()
 where schema_name = 'public'
   and routine_name = 'trg_gate_incomplete_match';

update public.kernel_routine_ownership
   set source_kind        = 'MANIFEST',
       source_file        = 'scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql',
       ownership_class    = 'QUOTESDONE_APPLICATION',
       classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence           = 'owner=postgres, no extension, and a scripts/sql/MANIFEST.txt file defines it',
       justification      = null,
       recorded_at        = now()
 where schema_name = 'public'
   and routine_name = 'fn_unsafe_match_eligibility_guard';
