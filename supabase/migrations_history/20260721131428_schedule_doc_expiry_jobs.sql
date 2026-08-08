-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721131428   name: schedule_doc_expiry_jobs
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Repoint the existing daily reconcile at the wider function (licence + insurance, with supplier
-- notification). fn_reconcile_licence_blocks is intentionally left in place, unscheduled, so this
-- is a one-line rollback if the wider scope turns out to be wrong for the business.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'licence_block_reconcile_daily'),
  command => 'select public.fn_reconcile_doc_blocks(0)'
);

-- Final notice runs daily, seven days ahead of expiry. Placed at 05:10, after doc_reminders_daily
-- (05:00) so the two never contend, and well before the next day's reconcile.
select cron.schedule('doc_final_notice_daily', '10 5 * * *', 'select public.fn_doc_final_notice(7)');
