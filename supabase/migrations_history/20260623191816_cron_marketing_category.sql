-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623191816   name: cron_marketing_category
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


select cron.schedule('agent_marketing_weekly', '0 6 * * 1', $$ select run_agent('marketing') $$);
select cron.schedule('agent_category_sales_daily', '30 5 * * *', $$ select run_agent('category_sales') $$);

