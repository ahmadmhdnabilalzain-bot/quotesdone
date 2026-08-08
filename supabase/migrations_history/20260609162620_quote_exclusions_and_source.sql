-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260609162620   name: quote_exclusions_and_source
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.quotes
  add column if not exists exclusions text,
  add column if not exists anonymized boolean default false;   -- true when produced by the AI anonymizer;
