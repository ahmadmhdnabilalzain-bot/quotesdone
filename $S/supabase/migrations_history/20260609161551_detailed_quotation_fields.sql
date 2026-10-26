-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260609161551   name: detailed_quotation_fields
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.quotes
  add column if not exists lead_time     text,   -- delivery / installation time
  add column if not exists validity      text,   -- how long the quote is valid
  add column if not exists payment_terms text,
  add column if not exists warranty      text,
  add column if not exists scope         text,   -- what's included / excluded
  add column if not exists conditions    text;   -- price based on conditions, site visit etc.;
