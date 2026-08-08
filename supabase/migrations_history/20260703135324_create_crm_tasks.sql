-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260703135324   name: create_crm_tasks
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.crm_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  detail text,
  status text not null default 'open',
  priority text default 'normal',
  source text default 'admin',
  entity text,
  entity_id text,
  due_date date,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
alter table public.crm_tasks enable row level security;
create index if not exists idx_crm_tasks_status on public.crm_tasks(status, created_at desc);

