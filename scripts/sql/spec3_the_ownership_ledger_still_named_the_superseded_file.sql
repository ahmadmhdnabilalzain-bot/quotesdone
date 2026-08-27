-- THE LEDGER NAMED THE FILE THAT USED TO OWN THE ROUTINE.
--
-- scripts/sql/spec3_the_sixth_reputation_axis_had_no_column.sql redefines fn_reputation_recompute
-- and was appended to scripts/sql/MANIFEST.txt, which makes it canonical — position in that file,
-- not a git timestamp, decides. public.kernel_routine_ownership still recorded
--
--   fn_reputation_recompute()  source_file scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql
--   recorded_at 2026-08-16 23:11:33
--
-- so the Phase C kernel gate reported "ledger claims the repository denies 1 / 1225" and exited 1:
-- the ledger asserted an owner the manifest no longer agrees with. Measured:
--   select routine_name, source_file from public.kernel_routine_ownership
--    where routine_name = 'fn_reputation_recompute';
--
-- This is the ledger being kept in step with the manifest, which is the one repair that gate wants.
-- It is not a re-classification: ownership_class stays QUOTESDONE_APPLICATION and source_kind stays
-- MANIFEST. Only the file name moves, and it moves to the file that actually holds the body running
-- on production right now.

begin;

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/spec3_the_sixth_reputation_axis_had_no_column.sql',
       recorded_at = now()
 where schema_name = 'public'
   and routine_name = 'fn_reputation_recompute'
   and source_file = 'scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql';

commit;
