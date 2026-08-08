-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260621103926   name: email_suppressions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists email_suppressions (
  email text primary key,
  reason text default 'unsubscribe',
  source text,
  created_at timestamptz default now()
);
alter table public.email_suppressions enable row level security;
revoke all on public.email_suppressions from anon, authenticated;
