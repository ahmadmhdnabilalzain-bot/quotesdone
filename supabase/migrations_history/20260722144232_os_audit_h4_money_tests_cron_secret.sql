-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722144232   name: os_audit_h4_money_tests_cron_secret
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H4: money_tests will now require inbound_secret in the body; the daily cron must send it.
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname = 'money_tests_daily'),
  command := $cmd$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/money_tests',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
    body := jsonb_build_object('__secret', (select value from app_secrets where key='inbound_secret'))
  );
  $cmd$
);
