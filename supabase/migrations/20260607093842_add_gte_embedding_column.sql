-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607093842   name: add_gte_embedding_column
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.leads add column if not exists embedding_gte vector(384);
