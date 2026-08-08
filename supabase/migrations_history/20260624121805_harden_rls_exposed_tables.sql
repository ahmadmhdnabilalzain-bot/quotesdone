-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260624121805   name: harden_rls_exposed_tables
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Close the 6 tables that had RLS disabled while granting anon access.
alter table agent_knowledge        enable row level security;
alter table agent_memory           enable row level security;
alter table email_suppression      enable row level security;
alter table error_events           enable row level security;
alter table social_posts           enable row level security;
alter table supply_health_snapshots enable row level security;

-- Defense in depth: these are internal/admin tables; the frontend never reads them via the
-- public key (all access is through edge functions using the service role, which bypasses RLS).
revoke all on agent_knowledge        from anon, authenticated;
revoke all on agent_memory           from anon, authenticated;
revoke all on email_suppression      from anon, authenticated;
revoke all on error_events           from anon, authenticated;
revoke all on social_posts           from anon, authenticated;
revoke all on supply_health_snapshots from anon, authenticated;
