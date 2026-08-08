-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260606233030   name: add_profile_columns
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


alter table public.leads
  add column if not exists description  text,
  add column if not exists founded_year integer,
  add column if not exists company_type text,
  add column if not exists company_size text;

-- temporary load access for upsert via API key (revoked after)
grant select, insert, update on public.leads to anon;

