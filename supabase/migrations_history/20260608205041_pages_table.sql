-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608205041   name: pages_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.pages (
  slug text primary key,
  html text not null,
  updated_at timestamptz default now()
);
alter table public.pages enable row level security;
