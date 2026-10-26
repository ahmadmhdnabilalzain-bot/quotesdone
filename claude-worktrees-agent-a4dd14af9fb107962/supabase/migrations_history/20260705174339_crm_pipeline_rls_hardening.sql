-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260705174339   name: crm_pipeline_rls_hardening
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- New config tables: enable RLS with no public policy (service role bypasses).
alter table crm_stages enable row level security;
alter table crm_lost_reasons enable row level security;
-- Analytics views respect the querying role's RLS (service role bypasses; anon blocked).
alter view crm_pipeline_report set (security_invoker = on);
alter view crm_deal_kpis set (security_invoker = on);
-- Revoke any default grants to anon/authenticated on the new objects (edge fn uses service role).
revoke all on crm_stages from anon, authenticated;
revoke all on crm_lost_reasons from anon, authenticated;
revoke all on crm_pipeline_report from anon, authenticated;
revoke all on crm_deal_kpis from anon, authenticated;
