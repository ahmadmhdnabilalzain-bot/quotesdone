-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260609163536   name: auto_approve_toggle
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.pricing_config add column if not exists auto_approve_suppliers boolean default false;
update public.pricing_config set auto_approve_suppliers = true where id = 1;  -- TESTING: skip manual approval. Set false to re-enable verification.;
