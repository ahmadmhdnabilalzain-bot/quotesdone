-- DOWN for O13. Classification: mixed. One new trigger + routine (reversed here), one write-map row
-- edit (reversed here), and two ROUTINE_RESTORE replacements.
--
-- fn_phase_d_package_revisions_dispatchable and fn_phase_d_fixture_scenario are NOT reproduced here:
-- the restore is to re-apply the last file before O13 that defines each, by scripts/sql/MANIFEST.txt
-- position (phase_d_o04 and phase_d_o11 respectively), confirmed by
-- `node scripts/checks/canonical_routine_manifest.mjs --all` reporting 0 repository -> production
-- drift. Expect the 25 red step-contract cases back on W08, W14 and W15 afterwards: that is the
-- state O13 corrected, not a new fault.
DROP TRIGGER IF EXISTS a20_quote_comparison_publication_stamp ON public.quote_comparisons;
DROP FUNCTION IF EXISTS public.fn_quote_comparison_publication_stamp();
UPDATE public.phase_d_object_write_map
   SET column_map = column_map - 'publication_state'
 WHERE object_id = 'quotation_comparison';
