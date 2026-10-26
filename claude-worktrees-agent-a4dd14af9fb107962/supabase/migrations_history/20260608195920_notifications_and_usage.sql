-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608195920   name: notifications_and_usage
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.notifications (
  id bigint generated always as identity primary key,
  type text not null,
  to_email text,
  to_role text,
  lead_id bigint,
  inquiry_id uuid,
  quote_id uuid,
  subject text,
  body text,
  status text not null default 'pending',
  created_at timestamptz default now(),
  sent_at timestamptz
);
create index if not exists notifications_status_idx on public.notifications(status, created_at);
alter table public.notifications enable row level security;

create table if not exists public.ai_usage (
  id bigint generated always as identity primary key,
  email text,
  kind text,
  created_at timestamptz default now()
);
create index if not exists ai_usage_email_time_idx on public.ai_usage(email, created_at);
alter table public.ai_usage enable row level security;
