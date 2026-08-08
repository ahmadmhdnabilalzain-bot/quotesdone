-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623200406   name: cron_founder_brief
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

select cron.schedule('founder_brief_daily', '30 4 * * *', $$ select fn_founder_brief() $$);
