-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260606233148   name: resecure_leads_after_profiles
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


revoke select, insert, update on public.leads from anon;
alter table public.leads enable row level security;

