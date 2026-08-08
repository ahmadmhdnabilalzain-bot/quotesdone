-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619131723   name: sms_notifications_and_phone_otp
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.notifications
  add column if not exists channel text default 'email',
  add column if not exists to_phone text;

alter table public.customers
  add column if not exists phone_verified boolean default false;

create table if not exists public.customer_phone_otps (
  id bigint generated always as identity primary key,
  customer_id uuid references public.customers(id) on delete cascade,
  phone text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int default 0,
  consumed boolean default false,
  created_at timestamptz default now()
);
create index if not exists cpo_cust_idx on public.customer_phone_otps(customer_id, created_at desc);
alter table public.customer_phone_otps enable row level security;
