-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260630181647   name: reveal_invoice_cache
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.reveal_invoices (
  transaction_id uuid primary key references public.transactions(id) on delete cascade,
  invoice_no text,
  bucket text,
  path text,
  created_at timestamptz default now()
);
insert into app_secrets(key, value) values ('company_trn','') on conflict (key) do nothing;

