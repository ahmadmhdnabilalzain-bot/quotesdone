-- ROLLBACK for scripts/sql/phase_c_the_ownership_ledger_named_the_pccr006_file_again.sql
--
-- NO TRANSACTION CONTROL. One UPDATE and an assertion.
--
-- Restores public.kernel_routine_ownership to the row it held before: fn_phase_c_require_founder
-- recorded against the PCCR-006 file. APPLYING THIS PUTS CI BACK IN THE RED -- line 6 of
-- application_source_of_truth reports "ledger claims the repository denies 1 / 1225" -- and points a
-- reader at the founder door WITHOUT PCCR-007's session_user predicate. It exists so the change is
-- reversible, not because reversing it is a good idea.

update public.kernel_routine_ownership set
       source_file = 'scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql'
 where schema_name = 'public' and routine_name = 'fn_phase_c_require_founder'
   and coalesce(identity_args,'') = 'p_actor text';

DO $assert$
DECLARE v_file text;
BEGIN
  SELECT source_file INTO v_file FROM public.kernel_routine_ownership
   WHERE schema_name = 'public' AND routine_name = 'fn_phase_c_require_founder';
  IF v_file IS DISTINCT FROM 'scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql' THEN
    RAISE EXCEPTION 'rollback did not restore the PCCR-006 pointer (found %)', coalesce(v_file,'(none)')
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'ownership ledger pointer restored to the PCCR-006 file; CI line 6 is red again';
END $assert$;
