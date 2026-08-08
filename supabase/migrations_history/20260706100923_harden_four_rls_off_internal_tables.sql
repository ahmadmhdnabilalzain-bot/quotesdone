-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706100923   name: harden_four_rls_off_internal_tables
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Close anon exposure on 4 internal tables (service_role/edge functions bypass RLS, so unaffected)
alter table public.agent_command_log     enable row level security;
alter table public.agent_pending_actions enable row level security;
alter table public.canary_records        enable row level security;
alter table public.crm_activities        enable row level security;

revoke all on public.agent_command_log     from anon, authenticated;
revoke all on public.agent_pending_actions from anon, authenticated;
revoke all on public.canary_records        from anon, authenticated;
revoke all on public.crm_activities        from anon, authenticated;
