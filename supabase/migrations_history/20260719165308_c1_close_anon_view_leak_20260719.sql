-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719165308   name: c1_close_anon_view_leak_20260719
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- C1: revoke anon/authenticated read on 4 RLS-bypassing views (supplier PII + LLM telemetry).
-- service_role + postgres retain access. Both internal callers (fn_subscription_billing_run,
-- fn_llm_drift_watch) are SECURITY DEFINER (owner-run, RLS-bypassing) so they are unaffected.
revoke all on table public.v_supplier_billing   from anon, authenticated;
revoke all on table public.v_llm_model_mix       from anon, authenticated;
revoke all on table public.v_llm_offpolicy       from anon, authenticated;
revoke all on table public.v_kb_regulation_gaps  from anon, authenticated;
