-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625211810   name: approval_timestamps
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table leads add column if not exists approved_at timestamptz;
alter table leads add column if not exists approval_decided_by text;
alter table leads add column if not exists rejection_reason text;
