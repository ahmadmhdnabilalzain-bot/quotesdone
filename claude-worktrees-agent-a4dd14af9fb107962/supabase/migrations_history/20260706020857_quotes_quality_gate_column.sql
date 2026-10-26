-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706020857   name: quotes_quality_gate_column
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table quotes add column if not exists quality jsonb;
