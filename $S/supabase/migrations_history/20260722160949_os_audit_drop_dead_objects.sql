-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722160949   name: os_audit_drop_dead_objects
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Verified dead (zero callers/deps/FKs/repo-refs; recoverable via PITR + git). Authorised cleanup (#54 + founder go).
drop function if exists public.run_licence_reminders();
drop table if exists public.pages_archive_20260721;
drop table if exists public._legacy_customer_pages_20260722;
