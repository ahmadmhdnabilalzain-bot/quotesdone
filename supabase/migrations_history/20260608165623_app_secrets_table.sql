-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608165623   name: app_secrets_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists app_secrets (key text primary key, value text not null, updated_at timestamptz default now());
alter table app_secrets enable row level security;
-- no policies = deny all to anon/authenticated; only service_role (which bypasses RLS) can read.;
