-- PCCR-006 FOLLOW-UP, SECOND PART. THE LEDGER KEPT ITS INSERT, UPDATE AND DELETE GRANTS TOO.
--
-- NO TRANSACTION CONTROL. Five statements and an assertion.
--
-- phase_c_pccr006_the_ledger_kept_its_truncate_grant.sql closed the D in
-- {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres} and stopped there. Measured on
-- production 2026-08-25T18:1x:xxZ, after that file was applied:
--
--   public.phase_c_governance_decision  service_role  DELETE,INSERT,REFERENCES,SELECT,TRIGGER,UPDATE
--   public.phase_c_change_request       service_role  SELECT
--   public.phase_c_founder_auth_event   service_role  SELECT
--   public.phase_c_freeze_amendment     service_role  SELECT
--
-- The append-only ledger is the ONE table of the four that service_role can still write. Its own
-- migration says what was intended two lines apart:
--
--   REVOKE ALL ON TABLE public.phase_c_governance_decision FROM PUBLIC, anon, authenticated;
--   GRANT SELECT ON TABLE public.phase_c_governance_decision TO service_role;
--
-- The REVOKE omits service_role, so the GRANT SELECT added nothing to a role that already held
-- everything through Supabase's default privileges on public. A grant that reads as "SELECT only"
-- and is in fact "SELECT plus a, w and d" is the same shape as the TRUNCATE miss one file earlier,
-- and the third instance of it in this session.
--
-- WHAT WAS MEASURED BEFORE CHANGING ANYTHING, so this is not filed as an open door:
--   * a00_phase_c_governance_decision_is_session_backed fires BEFORE INSERT OR UPDATE OR DELETE and
--     raises on any TG_OP that is not INSERT, and on an INSERT with no bound auth event. Forced as
--     service_role in an aborted transaction: REFUSED 28000 pccr_governance_no_auth_event.
--   * fn_phase_c_governance_decide is SECURITY DEFINER owned by postgres, so the one legitimate
--     writer inserts as the owner and never needs a service_role grant.
--
-- So this is defence in depth that was specified and not applied, not a hole that was open. It is
-- still worth closing: the guard and the grant disagree about the same table, which is the state
-- that produced BOTH earlier instances, and the next person to read relacl would be told the ledger
-- is writable by the role every edge function runs as.
--
-- NOT FIXED BY EDITING EITHER APPLIED MIGRATION, for the reason the previous file states: both are
-- applied and the bootstrap approval record is written against them. This is a separate file, in
-- the order it happened.
--
-- ROLLBACK: scripts/sql/down/phase_c_pccr006_the_ledger_kept_its_write_grants_too_down.sql

REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER ON public.phase_c_governance_decision FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER ON public.phase_c_governance_decision FROM anon;
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER ON public.phase_c_governance_decision FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER ON public.phase_c_governance_decision FROM service_role;
GRANT SELECT ON public.phase_c_governance_decision TO service_role;

DO $assert$
DECLARE v_acl text; v_bad text;
BEGIN
  SELECT coalesce(relacl::text,'(default)') INTO v_acl FROM pg_class
   WHERE relname = 'phase_c_governance_decision' AND relnamespace = 'public'::regnamespace;

  SELECT string_agg(r || ':' || p, ', ' ORDER BY r, p) INTO v_bad
    FROM unnest(ARRAY['service_role','anon','authenticated']) r,
         unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) p
   WHERE has_table_privilege(r, 'public.phase_c_governance_decision', p);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'PCCR-006 follow-up 2: the append-only governance ledger is still writable by %. acl %',
      v_bad, v_acl USING errcode = '42501';
  END IF;

  -- THE READ-BACK THAT MATTERS: SELECT must survive. Revoking too far would make the ledger
  -- unreadable from every edge function, and fn_phase_c_freeze_drift reads it on every board load.
  IF NOT has_table_privilege('service_role','public.phase_c_governance_decision','SELECT') THEN
    RAISE EXCEPTION 'PCCR-006 follow-up 2: the revoke went too far -- service_role can no longer READ the ledger. acl %',
      v_acl USING errcode = '42501';
  END IF;

  -- THE THREE SIBLINGS ARE THE STANDARD THIS FILE IS MATCHING. Asserted rather than assumed, so a
  -- later widening of any of them is caught by the file that named them.
  SELECT string_agg(t || ':' || p, ', ' ORDER BY t, p) INTO v_bad
    FROM unnest(ARRAY['phase_c_change_request','phase_c_founder_auth_event','phase_c_freeze_amendment']) t,
         unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) p
   WHERE has_table_privilege('service_role', 'public.' || t, p);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'PCCR-006 follow-up 2: a sibling governance table is writable by service_role: %', v_bad
      USING errcode = '42501';
  END IF;

  RAISE NOTICE 'PCCR-006 follow-up 2: governance ledger acl %', v_acl;
END $assert$;
