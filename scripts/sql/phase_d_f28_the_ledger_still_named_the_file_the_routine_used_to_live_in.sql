-- F28 - the ledger still named the file the routine used to live in
--
-- application_source_of_truth.test.mjs, counter 6, "ledger claims the repository denies":
--
--     public.fn_phase_c_require_founder(p_actor text)
--       records source_file scripts/sql/kernel_k0_founder_authentication.sql,
--       manifest order says  scripts/sql/phase_d_f20_the_founder_is_a_verified_auth_subject_not_a_typed_string.sql
--
-- kernel_k0 is where founder authentication was BUILT. PCCR-003 replaced the body, so the canonical
-- file is now F20 -- and public.kernel_routine_ownership went on naming the old one. That is the
-- same shape D56 recorded once already: "the ledger named the file the routine used to live in".
--
-- A ledger that disagrees with the apply order is worse than no ledger: a reader looking for the
-- source of the founder guard would open a file that no longer defines it and find the vector E39
-- removed, still there, described as current.

UPDATE public.kernel_routine_ownership
   SET source_file = 'scripts/sql/phase_d_f20_the_founder_is_a_verified_auth_subject_not_a_typed_string.sql'
 WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_require_founder'
   AND source_file = 'scripts/sql/kernel_k0_founder_authentication.sql';
