-- DOWN. RETURN BOTH OWNERSHIP LEDGER ROWS TO THE SUPERSEDED FILE THEY NAMED.
--
-- NO TRANSACTION CONTROL. Two UPDATEs.
--
-- APPLYING THIS restores the state application_source_of_truth reported as
-- "ledger claims the repository denies 2 / 1225". In particular it points
-- public.fn_phase_c_require_founder back at the pre-PCCR-006 file -- the version WITHOUT verified
-- auth-subject resolution -- for the routine that decides whether a caller is the founder. It
-- exists so the change is reversible, not because reverting is advisable.

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/phase_d_f20_the_founder_is_a_verified_auth_subject_not_a_typed_string.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_require_founder';

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/source_of_truth_the_repository_records_what_production_runs.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_schema_export';
