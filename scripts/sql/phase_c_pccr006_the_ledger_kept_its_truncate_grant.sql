-- PCCR-006 FOLLOW-UP. THE APPEND-ONLY GOVERNANCE LEDGER KEPT ITS TRUNCATE GRANT.
--
-- NO TRANSACTION CONTROL. Two statements and an assertion.
--
-- PCCR-006 created public.phase_c_governance_decision, attached z00_kernel_truncate_guard to it,
-- and made every UPDATE and DELETE raise -- and left service_role holding TRUNCATE. Measured on
-- production immediately after applying it:
--
--   fn_kernel_truncate_protection_state :: enforcing_tables_still_granting_truncate  1 of 93
--   public.phase_c_governance_decision  relacl {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}
--
-- The D in arwdDxtm is TRUNCATE. A table whose whole design is "a recorded governance decision is a
-- fact about the past and may not be edited" is not append-only while one statement can empty it.
-- The guard would raise -- z00_kernel_truncate_guard is attached and it does fire -- but a guard and
-- a grant disagreeing about the same table is the state this board exists to find, and it found it.
--
-- THIS IS THE SECOND TIME IN ONE SESSION. phase_d_q07 attached a raising trigger to
-- founder_command_clarification and revoked TRUNCATE from PUBLIC only, while service_role held it
-- directly; the same board row caught that too. Revoking from PUBLIC is not revoking.
--
-- NOT FIXED BY EDITING THE APPLIED MIGRATION. phase_c_pccr006_governance_approval_authenticity.sql
-- is applied and its bootstrap approval record is written against it. Editing it now would leave the
-- committed file describing something other than what was applied. This is a separate file, in the
-- order it happened.
--
-- ROLLBACK: scripts/sql/down/phase_c_pccr006_the_ledger_kept_its_truncate_grant_down.sql

REVOKE TRUNCATE ON public.phase_c_governance_decision FROM PUBLIC;
REVOKE TRUNCATE ON public.phase_c_governance_decision FROM service_role;

DO $assert$
DECLARE v_acl text; v_red int;
BEGIN
  SELECT coalesce(relacl::text,'(default)') INTO v_acl FROM pg_class
   WHERE relname = 'phase_c_governance_decision' AND relnamespace = 'public'::regnamespace;

  IF has_table_privilege('service_role','public.phase_c_governance_decision','TRUNCATE')
     OR has_table_privilege('anon','public.phase_c_governance_decision','TRUNCATE')
     OR has_table_privilege('authenticated','public.phase_c_governance_decision','TRUNCATE') THEN
    RAISE EXCEPTION 'PCCR-006 follow-up: a role still holds TRUNCATE on the governance ledger. acl %',
      v_acl USING errcode = '42501';
  END IF;

  -- REPORTED, NOT ASSERTED TO ZERO. This file closes the ledger's grant, which is the one it is
  -- about. public.phase_d_output_domain_registry carries the same guard and the same grant and is
  -- NOT closed here: it is older than this session, nothing in this session created it, and closing
  -- a table this file was not written for is how an unrelated regression gets attributed to a
  -- governance change. It is named so it is not lost.
  SELECT count(*) INTO v_red FROM public.fn_kernel_truncate_protection_state() WHERE NOT ok;
  RAISE NOTICE 'PCCR-006 follow-up: governance ledger acl %, truncate-protection board red rows %',
    v_acl, v_red;
END $assert$;
