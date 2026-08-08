-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623202807   name: cron_vt_scan
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

select cron.schedule('vt_scan_daily', '0 3 * * *', $$ select fn_run_vt() $$);
