-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260713113350   name: notifications_html_column
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table notifications add column if not exists html text;
