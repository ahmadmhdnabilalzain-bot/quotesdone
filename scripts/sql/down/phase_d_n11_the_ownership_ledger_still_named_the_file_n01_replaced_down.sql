-- ROLLBACK for phase_d_n11_the_ownership_ledger_still_named_the_file_n01_replaced.sql
--
-- Restores public.kernel_routine_ownership's row for fn_unsafe_match_eligibility_guard to name the
-- K05 file.
--
-- ONLY CORRECT WHILE N01 IS ALSO ROLLED BACK. The ledger records which file the repository says is
-- a routine's canonical source; pointing it at K05 while N01 is still the highest-sequence file
-- defining the routine would make application_source_of_truth red for the same reason N11 fixed,
-- in the other direction. Roll back N01 first, or not at all.
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
