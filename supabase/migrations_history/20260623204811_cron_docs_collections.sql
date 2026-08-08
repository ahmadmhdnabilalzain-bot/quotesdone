-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623204811   name: cron_docs_collections
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


select cron.schedule('agent_doc_control_daily', '30 5 * * *', $$ select fn_doc_control() $$);
select cron.schedule('agent_collections_daily', '0 6 * * *', $$ select fn_collections() $$);

