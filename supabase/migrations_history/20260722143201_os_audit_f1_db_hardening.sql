-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722143201   name: os_audit_f1_db_hardening
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H2: revoke anon/authenticated EXECUTE on the 4 exposed SECURITY DEFINER RPCs (cron/service-invoked only)
DO $mig$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('fn_category_sales','fn_notify_supplier','fn_split_inquiry','fn_supplier_capability_chase')
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION '||r.sig::text||' FROM anon, authenticated';
  END LOOP;
END
$mig$;

-- M15: pin search_path on the 6 mutable-search_path functions (advisor: function_search_path_mutable)
DO $mig$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('fn_accrue_dues_interest','fn_ban_overdue_dues','fn_gl_sync_business','mask_contact','qd_on_refund_resolved','trg_mask_quote_contact')
  LOOP
    EXECUTE 'ALTER FUNCTION '||r.sig::text||' SET search_path = public, pg_temp';
  END LOOP;
END
$mig$;

-- Duplicate index (advisor: duplicate_index) — keep the PK, drop the redundant unique
DROP INDEX IF EXISTS public.ux_supplier_capabilities_supplier;

-- Unindexed FK (advisor: unindexed_foreign_keys) — covering index for the multi-trade split path
CREATE INDEX IF NOT EXISTS ix_inquiries_parent_inquiry ON public.inquiries(parent_inquiry_id);
