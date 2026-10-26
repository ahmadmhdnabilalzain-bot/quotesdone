-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711032811   name: prelaunch_lock_erp_views_and_secdef_rpcs
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Pre-launch hardening: the ERP/reporting SECURITY DEFINER views and the internal
-- SECURITY DEFINER business/admin functions were reachable by the public anon/authenticated
-- roles (anon key is embedded in site JS). The frontend uses only edge functions (service_role),
-- so revoking public access is safe. service_role + postgres keep their explicit direct grants.
DO $$
DECLARE r record;
BEGIN
  -- 1) Lock the ERP/reporting views (financials, budgets, inventory, AP, reports, KPIs)
  FOR r IN
    SELECT c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN ('v','m')
      AND c.relname IN ('inv_on_hand','inv_valuation','fa_register','budget_vs_actual',
        'budget_vs_actual_summary','gl_ledger','gl_account_balances','gl_trial_balance',
        'gl_pnl','gl_balance_sheet','po_open','ap_open_bills','ap_aging',
        'report_registry','report_kpis','strategy_kpis','governance_kpis')
  LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated;', r.relname);
  END LOOP;

  -- 2) Lock the RPC-exposed SECURITY DEFINER functions (accounting, PDPL, ops, admin).
  --    Exclude trigger/event_trigger functions (not RPC-exposed). Revoke from PUBLIC+anon+authenticated;
  --    service_role/postgres retain their explicit direct EXECUTE grants.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND pg_get_function_result(p.oid) NOT IN ('trigger','event_trigger')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated;', r.sig);
  END LOOP;
END $$;

-- 3) Pin a stable search_path on the one flagged mutable-search_path function
ALTER FUNCTION public.fn_security_audit_immutable() SET search_path = public, pg_temp;
