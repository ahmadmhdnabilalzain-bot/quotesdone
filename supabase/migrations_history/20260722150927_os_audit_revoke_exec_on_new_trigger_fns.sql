-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722150927   name: os_audit_revoke_exec_on_new_trigger_fns
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The two SECURITY DEFINER trigger functions added in F2 (H17/H18) inherited Postgres's default PUBLIC EXECUTE.
-- They only ever run as triggers (on founder_alerts / agent_actions), so no role needs EXECUTE — revoke it.
REVOKE EXECUTE ON FUNCTION public.fn_normalize_founder_alert_level() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_page_high_agent_action() FROM PUBLIC, anon, authenticated;
