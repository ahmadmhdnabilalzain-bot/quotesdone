-- Q06. A SECURITY DEFINER FUNCTION CREATED AND LEFT EXECUTABLE BY PUBLIC.
--
-- NO TRANSACTION CONTROL. Two statements.
--
-- phase_d_q03 CREATED public.trg_customer_registered_kernel() as SECURITY DEFINER. Postgres grants
-- EXECUTE on a newly created function to PUBLIC, and nothing in that file revoked it. Measured:
--
--   scripts/checks/anon_cannot_execute_security_definer.test.mjs
--     'no SECURITY DEFINER routine in public is anon-executable'
--        -> ['trg_customer_registered_kernel']
--     'exactly the two customer-document routines are authenticated-executable'
--        -> the set changed
--
-- This is the exact trap the session's own standing rule names — *every SECURITY DEFINER function
-- you CREATE is granted EXECUTE to PUBLIC; revoke it in the same migration. CREATE OR REPLACE
-- preserves the ACL, so do not revoke there* — and Q01, which was a REPLACE of an existing
-- function, was correctly left alone. Q03 was a CREATE and was not.
--
-- HOW BIG IT WAS, STATED RATHER THAN MINIMISED. It is a trigger function: it takes no arguments,
-- returns `trigger`, and raises `0A000` if called outside a trigger context, so no caller could
-- have made it do anything. That is a reason the blast radius was small; it is not a reason to
-- leave it. An anon-executable SECURITY DEFINER routine in `public` is a surface, the check
-- measures the surface and not the exploit, and it is right to.
--
-- The ACL after this file is the one both of its siblings already carry —
-- `{postgres=X/postgres,service_role=X/postgres}` — and the trigger keeps firing regardless: the
-- executor invokes a trigger function without checking EXECUTE at all.
--
-- ROLLBACK: scripts/sql/down/phase_d_q06_a_security_definer_function_created_and_left_public_down.sql
-- re-grants PUBLIC. It exists so the change is reversible; applying it re-opens the surface and
-- turns scripts/checks/anon_cannot_execute_security_definer.test.mjs red again.

REVOKE ALL ON FUNCTION public.trg_customer_registered_kernel() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trg_customer_registered_kernel() TO service_role;

DO $assert$
DECLARE v_anon boolean; v_auth boolean; v_acl text;
BEGIN
  SELECT has_function_privilege('anon', p.oid, 'EXECUTE'),
         has_function_privilege('authenticated', p.oid, 'EXECUTE'),
         coalesce(p.proacl::text, '(default: PUBLIC)')
    INTO v_anon, v_auth, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'trg_customer_registered_kernel';

  IF v_anon OR v_auth THEN
    RAISE EXCEPTION 'Q06: trg_customer_registered_kernel is still reachable (anon=%, authenticated=%), acl %',
      v_anon, v_auth, v_acl USING errcode = '42501';
  END IF;

  RAISE NOTICE 'Q06 OK: anon=% authenticated=% acl=%', v_anon, v_auth, v_acl;
END $assert$;
