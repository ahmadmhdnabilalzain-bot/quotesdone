-- THE RETIRED LEAD SOURCING JOB AND THE HOURLY BANK MATCH STOP RUNNING.
--
-- Assigned: it_engineer (the schedule) + accountant (its duty). Agent: simplify_build_D, 16 Nov 2026. Founder ledgers
-- 1714/1715. Audit: scratchpad audit_simplify/STALE.md S6 and S7.
--
-- 1. cron job 396 'lead_sourcing_batch' ('*/10 * * * *', command 'select public.fn_lead_sourcing_kick();', active).
--    RULING 1205 (12 Oct 2026): "supplier lead finding is done by Claude in chat once every month (on the subscription) and
--    ingested into the leads for the agents - not by the automated daily lead_sourcing job (Serper + model spend). Replaces the
--    automated job". MEASURED 16 Nov 2026 (SELECT): 144 runs in the last 24 hours, 144 succeeded, each a no-op:
--    fn_lead_sourcing_today() = {"stop":"lead quota","quota":0} (app_secrets.lead_sourcing_daily_quota = '0'); no other cron
--    job names lead sourcing. The job is unscheduled here; the routine, the marketing action and the keys stay (removing the
--    code is a separate change).
--    REVERSAL, if ever wanted:  select cron.schedule('lead_sourcing_batch', '*/10 * * * *', 'select public.fn_lead_sourcing_kick();');
--
-- 2. seat_duty 'accountant.bank_reconcile' (every 1 hour, enabled, routine fn_accountant_bank_reconcile_hourly -> 
--    fn_accountant_bank_reconcile; its own cron job 1881 runs fn_seat_duty_run('accountant.bank_reconcile') every 5 minutes).
--    RULING 1559 (10 Nov 2026): "No bank statement reconciliation. Near each month end the founder will tell the session to
--    scan his email and check the receipts there." MEASURED 16 Nov 2026 (SELECT): last result statements 2, matched_now 0,
--    payouts 0; bank_statement_line holds 11 rows, the newest value date 1 Oct 2026 (inserted 4 Oct); the same
--    fn_accountant_bank_reconcile also runs once a day inside accountant.stripe_reconcile (fn_accountant_stripe_reconcile_duty),
--    which stays. accountant.receipt_bank_match was already retired for 1559 on 10 Nov. fn_seat_duty_run reads only an
--    enabled duty, so cron job 1881 becomes a no-op; it is left in place so the duty can be switched back by data.
--    REVERSAL: update public.seat_duty set enabled = true where duty = 'accountant.bank_reconcile';
-- prevented by: the verdict row at the end of this file.
set local lock_timeout = '3s';

do $unschedule$
begin
  if exists (select 1 from cron.job where jobid = 396 and jobname = 'lead_sourcing_batch' and command ~ 'fn_lead_sourcing_kick') then
    perform cron.unschedule(396);
  end if;
end $unschedule$;

update public.seat_duty set enabled = false,
  what = 'RETIRED 16 Nov 2026 (accountant): founder ruling 1559, no bank statement reconciliation. It matched the bank statement '
      || 'lines to the books every hour; the newest statement line is of 1 Oct 2026, and the daily accountant.stripe_reconcile '
      || 'still runs the same match once a day. See scripts/sql/the_retired_lead_sourcing_job_and_the_hourly_bank_match_stop_running.sql.'
 where duty = 'accountant.bank_reconcile' and enabled;

select case
  when exists (select 1 from cron.job where jobname = 'lead_sourcing_batch' or command ~ 'fn_lead_sourcing_kick')
    then 'PROBE FAILED: the retired lead sourcing job is still scheduled'
  when exists (select 1 from public.seat_duty where duty = 'accountant.bank_reconcile' and enabled)
    then 'PROBE FAILED: the hourly bank match is still enabled'
  else 'PROBE OK: no lead sourcing job; accountant.bank_reconcile disabled with its reason' end as verdict;
