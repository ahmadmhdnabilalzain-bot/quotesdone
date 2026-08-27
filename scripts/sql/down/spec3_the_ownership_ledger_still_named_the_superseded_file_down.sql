-- Reverse of scripts/sql/spec3_the_ownership_ledger_still_named_the_superseded_file.sql.
--
-- Only meaningful alongside a rollback of the routine itself: pointing the ledger back at the
-- superseded file while the new body is live re-creates exactly the disagreement the Phase C kernel
-- gate exists to catch.

begin;

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql',
       recorded_at = now()
 where schema_name = 'public'
   and routine_name = 'fn_reputation_recompute'
   and source_file = 'scripts/sql/spec3_the_sixth_reputation_axis_had_no_column.sql';

commit;
