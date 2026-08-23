-- =================================================================================================
-- PHASE D DOWN — reverses
-- scripts/sql/phase_d_k09_the_ownership_ledger_still_named_the_file_k05_replaced.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- HAND-WRITTEN, because the classifier does not require a down script for a file that only updates
-- rows and the header of K09 promises one anyway. A promise in a header with no file behind it is
-- the shape this estate keeps finding, so here it is.
--
-- WHAT IT RESTORES: the two public.kernel_routine_ownership rows to the values they held before K05
-- moved their canonical source file.
--
--   public.trg_gate_incomplete_match()          HISTORICAL_APPLICATION, R5_TRACKED_SQL_OUTSIDE_MANIFEST,
--                                               supabase/migrations_history/20260708131431_rfq_qualification_gate_and_clarify.sql
--   public.fn_unsafe_match_eligibility_guard()  QUOTESDONE_APPLICATION, R4_MANIFEST_DEFINES_IT,
--                                               scripts/sql/v3_repair_09_unsafe_safeguards.sql
--
-- ONLY CORRECT WHILE K05 IS ALSO ROLLED BACK, and the guard below enforces it rather than trusting
-- the operator to remember. public.a00_kernel_routine_ownership_guard re-derives the class from
-- public.fn_kernel_routine_ownership at write time, and while
-- scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql is still listed in
-- scripts/sql/MANIFEST.txt the deriver answers R4/QUOTESDONE_APPLICATION for BOTH routines — so
-- writing HISTORICAL_APPLICATION here would be refused by the estate itself. Roll back K05 and
-- remove its MANIFEST line first; then this file writes cleanly.
--
-- ROW COUNT AT RISK: none. Two rows are updated in place; nothing is inserted or deleted.
-- =================================================================================================

begin;

do $down$
begin
  if exists (select 1 from public.kernel_routine_ownership
              where routine_name = 'trg_gate_incomplete_match'
                and source_file = 'scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql')
     and (select count(*) from regexp_split_to_table(
            coalesce(pg_read_file('scripts/sql/MANIFEST.txt'), ''), E'\n') l
           where btrim(l) = 'scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql') > 0
  then
    raise exception
      'K05 is still the canonical file for these routines. Roll K05 back and remove its MANIFEST.txt line first, or a00_kernel_routine_ownership_guard will refuse the rows this file writes.'
      using errcode = '23514';
  end if;
exception when insufficient_privilege or undefined_file then
  -- pg_read_file is not available to this role on a managed instance. The guard cannot read the
  -- manifest, so it steps aside rather than blocking a rollback for want of a file read; the
  -- ownership guard below still refuses an inconsistent row.
  null;
end $down$;

update public.kernel_routine_ownership
   set source_kind        = 'TRACKED_SQL_OUTSIDE_MANIFEST',
       source_file        = 'supabase/migrations_history/20260708131431_rfq_qualification_gate_and_clarify.sql',
       ownership_class    = 'HISTORICAL_APPLICATION',
       classified_by_rule = 'R5_TRACKED_SQL_OUTSIDE_MANIFEST',
       evidence           = 'owner=postgres, no MANIFEST file defines it, tracked SQL elsewhere does',
       recorded_at        = now()
 where schema_name = 'public' and routine_name = 'trg_gate_incomplete_match';

update public.kernel_routine_ownership
   set source_kind        = 'MANIFEST',
       source_file        = 'scripts/sql/v3_repair_09_unsafe_safeguards.sql',
       ownership_class    = 'QUOTESDONE_APPLICATION',
       classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence           = 'owner=postgres, no extension, and a scripts/sql/MANIFEST.txt file defines it',
       recorded_at        = now()
 where schema_name = 'public' and routine_name = 'fn_unsafe_match_eligibility_guard';

commit;
