-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607101334   name: supplier_portal_fields
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


alter table public.leads
  add column if not exists claimed boolean default false,
  add column if not exists contact_name text,
  add column if not exists service_emirates text[],
  add column if not exists bank_name text,
  add column if not exists bank_iban text,
  add column if not exists bank_account_name text,
  add column if not exists trade_license_no text,
  add column if not exists verified boolean default false,
  add column if not exists portal_updated_at timestamptz;

