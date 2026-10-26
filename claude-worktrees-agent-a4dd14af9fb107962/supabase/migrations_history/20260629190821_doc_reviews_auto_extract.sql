-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260629190821   name: doc_reviews_auto_extract
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


alter table public.doc_reviews add column if not exists auto_applied boolean default false;
alter table public.doc_reviews add column if not exists extracted jsonb;

