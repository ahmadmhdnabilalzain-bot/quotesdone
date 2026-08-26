-- THE OWNERSHIP LEDGER NAMED A FILE THE MANIFEST HAD SUPERSEDED.
--
-- NO TRANSACTION CONTROL. Two UPDATEs and an assertion.
--
-- CI "the Phase C kernel gate" runs application_source_of_truth, which reported:
--
--   6. ledger claims the repository denies             2 / 1225
--     public.fn_phase_c_require_founder(p_actor text)  records source_file
--       scripts/sql/phase_d_f20_the_founder_is_a_verified_auth_subject_not_a_typed_string.sql,
--       manifest order says scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql
--     public.fn_schema_export()  records source_file
--       scripts/sql/source_of_truth_the_repository_records_what_production_runs.sql,
--       manifest order says scripts/sql/phase_c_the_export_had_no_tiebreaker.sql
--
-- public.kernel_routine_ownership records, per routine, WHICH FILE the estate considers its source.
-- scripts/sql/MANIFEST.txt decides canon by position, so the moment a later file redefines a
-- routine the ledger's stored answer becomes the previous one. Neither routine drifted -- lines 1
-- through 5 and line 7 of that report are all 0 -- the ledger simply had not been told.
--
-- BOTH ARE THIS SESSION'S DOING, one of them at one remove:
--   * fn_phase_c_require_founder moved to the PCCR-006 file when the amendment was applied, and the
--     ledger was not updated then. It has been reporting the pre-PCCR-006 file ever since, which is
--     the more serious of the two: it points a reader at the version WITHOUT the verified-subject
--     resolution, for the routine that decides whether someone is the founder.
--   * fn_schema_export moved when phase_c_the_export_had_no_tiebreaker.sql was applied earlier
--     today.
--
-- WHY THIS IS A DATA FIX AND NOT A CODE FIX. The ledger is a recorded fact, not a derivation; the
-- canonical engine (canonical_routine_manifest) computes the same answer live and reports 0 for
-- every one of its six lines. That two instruments disagreed about one subject is precisely what
-- line 6 exists to catch, and it caught it.
--
-- ROLLBACK: scripts/sql/down/phase_c_the_ownership_ledger_named_a_file_the_manifest_had_superseded_down.sql

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_require_founder'
   AND source_file = 'scripts/sql/phase_d_f20_the_founder_is_a_verified_auth_subject_not_a_typed_string.sql';

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/phase_c_the_export_had_no_tiebreaker.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_schema_export'
   AND source_file = 'scripts/sql/source_of_truth_the_repository_records_what_production_runs.sql';

DO $assert$
DECLARE v_a text; v_b text;
BEGIN
  SELECT source_file INTO v_a FROM public.kernel_routine_ownership
   WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_require_founder';
  SELECT source_file INTO v_b FROM public.kernel_routine_ownership
   WHERE schema_name = 'public' AND routine_name = 'fn_schema_export';

  IF v_a IS DISTINCT FROM 'scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql' THEN
    RAISE EXCEPTION 'fn_phase_c_require_founder still records source_file %', coalesce(v_a,'(none)')
      USING errcode = '23514';
  END IF;
  IF v_b IS DISTINCT FROM 'scripts/sql/phase_c_the_export_had_no_tiebreaker.sql' THEN
    RAISE EXCEPTION 'fn_schema_export still records source_file %', coalesce(v_b,'(none)')
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'ownership ledger: both rows now name the manifest-canonical file';
END $assert$;
