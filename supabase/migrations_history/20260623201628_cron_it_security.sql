-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623201628   name: cron_it_security
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


select cron.schedule('agent_it_health_hourly', '15 * * * *', $$ select run_agent('it_health') $$);
select cron.schedule('agent_security_6h', '45 */6 * * *', $$ select run_agent('security') $$);

