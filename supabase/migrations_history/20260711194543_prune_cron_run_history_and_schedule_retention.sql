-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711194543   name: prune_cron_run_history_and_schedule_retention
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- pg_cron never prunes cron.job_run_details; it had grown to ~93k rows / 53 MB
-- in one month. Trim to a rolling 14-day window and keep it pruned daily.
-- Pure execution-log data; nothing depends on it.
delete from cron.job_run_details
where end_time < now() - interval '14 days';

-- Daily retention at 00:20 UTC (idempotent: unschedule an old copy first if present).
do $$
begin
  perform cron.unschedule('cron_history_prune');
exception when others then null;
end $$;

select cron.schedule(
  'cron_history_prune',
  '20 0 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '14 days'$$
);
