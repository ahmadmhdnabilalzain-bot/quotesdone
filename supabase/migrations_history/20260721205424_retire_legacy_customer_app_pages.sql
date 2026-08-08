-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721205424   name: retire_legacy_customer_app_pages
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The app / app-ar edge functions (which served these rows) were just deleted, so these
-- page rows now serve nothing. app_prev / app-ar_prev were pre-redesign backups. Snapshot
-- all four into a dated archive table (recoverable) and remove them from the live pages table.
create table if not exists public._legacy_customer_pages_20260722 as
  select * from public.pages
  where slug in ('app', 'app-ar', 'app_prev_20260719', 'app-ar_prev_20260719');

delete from public.pages
  where slug in ('app', 'app-ar', 'app_prev_20260719', 'app-ar_prev_20260719');
