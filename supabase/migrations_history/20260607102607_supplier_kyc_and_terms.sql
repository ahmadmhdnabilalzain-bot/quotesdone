-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607102607   name: supplier_kyc_and_terms
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


alter table public.leads
  add column if not exists trn text,
  add column if not exists license_authority text,
  add column if not exists license_expiry date,
  add column if not exists license_doc_name text,
  add column if not exists iban_doc_name text,
  add column if not exists signatory_name text,
  add column if not exists emirates_id text,
  add column if not exists accepted_terms_at timestamptz,
  add column if not exists accepted_terms_version text;

