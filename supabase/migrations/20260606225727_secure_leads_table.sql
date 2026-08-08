-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260606225727   name: secure_leads_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


revoke select, insert on public.leads from anon;
revoke usage, select on sequence public.leads_id_seq from anon;
alter table public.leads enable row level security;
-- no permissive policies => anon/publishable key has no access.
-- Access is via the dashboard (service role) only, which bypasses RLS.
;
