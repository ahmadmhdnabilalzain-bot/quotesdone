-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260713083547   name: create_inquiry_intake
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists inquiry_intake (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid,
  email text,
  category text,
  status text not null default 'needs_info',
  raw_input text,
  turns jsonb not null default '[]'::jsonb,
  brief jsonb,
  readiness int not null default 0,
  missing jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table inquiry_intake enable row level security;
create index if not exists inquiry_intake_customer_idx on inquiry_intake(customer_id);
create index if not exists inquiry_intake_email_idx on inquiry_intake(email);
create index if not exists inquiry_intake_status_idx on inquiry_intake(status);
