-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260629174442   name: admin_mfa_sessions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.admin_mfa_sessions(
  session_id text primary key,
  email text,
  verified_at timestamptz default now(),
  expires_at timestamptz not null,
  ip text,
  created_at timestamptz default now()
);
alter table public.admin_mfa_sessions enable row level security;
revoke all on public.admin_mfa_sessions from anon, authenticated;

