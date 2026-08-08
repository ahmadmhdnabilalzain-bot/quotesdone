-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607104755   name: supplier_account_link
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


alter table public.leads
  add column if not exists claimed_by text,           -- email of the account that claimed this supplier
  add column if not exists license_doc_path text,
  add column if not exists iban_doc_path text;
create index if not exists leads_claimed_by_idx on public.leads(claimed_by);

