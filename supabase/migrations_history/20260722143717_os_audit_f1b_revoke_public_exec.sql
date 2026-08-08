-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722143717   name: os_audit_f1b_revoke_public_exec
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H2 (corrected): the EXECUTE grant on these 4 SECURITY DEFINER RPCs comes from PUBLIC (Postgres default),
-- so it must be revoked from PUBLIC. service_role is granted explicitly so edge functions (customer_api,
-- route_inquiry) keep calling them; pg_cron runs as postgres (owner) and is unaffected.
DO $mig$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace='public'::regnamespace
      AND p.proname IN ('fn_category_sales','fn_notify_supplier','fn_split_inquiry','fn_supplier_capability_chase')
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION '||r.sig::text||' FROM PUBLIC, anon, authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION '||r.sig::text||' TO service_role';
  END LOOP;
END
$mig$;
