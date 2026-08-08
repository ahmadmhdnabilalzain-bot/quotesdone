-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619145742   name: messages_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  inquiry_id uuid references public.inquiries(id) on delete cascade,
  supplier_id bigint references public.leads(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  sender text not null check (sender in ('customer','supplier')),
  body text not null,
  created_at timestamptz default now(),
  read_by_customer boolean default false,
  read_by_supplier boolean default false
);
create index if not exists messages_thread_idx on public.messages(inquiry_id, supplier_id, created_at);
alter table public.messages enable row level security;
