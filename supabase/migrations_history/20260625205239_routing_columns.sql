-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625205239   name: routing_columns
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table inquiries add column if not exists routing jsonb;
alter table inquiry_matches add column if not exists match_reason text;
