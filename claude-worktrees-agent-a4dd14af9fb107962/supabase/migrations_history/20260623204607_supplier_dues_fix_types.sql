-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623204607   name: supplier_dues_fix_types
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


drop table if exists supplier_dues;
create table supplier_dues (
  id bigint generated always as identity primary key,
  transaction_id uuid unique,
  supplier_id bigint,
  quote_id uuid,
  quote_amount numeric,
  commission_pct numeric default 2,
  amount_due numeric,
  currency text default 'AED',
  reveal_date date,
  due_date date,
  due_date_30 date,
  status text default 'pending',
  reminders int default 0,
  last_reminder_at timestamptz,
  overdue_emailed_at timestamptz,
  fine_pct numeric default 0,
  fine_amount numeric default 0,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);
alter table supplier_dues enable row level security;

