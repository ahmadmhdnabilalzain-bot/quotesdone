-- THE TWO DISABLED SALES DUTIES STOP FIRING EVERY FIVE MINUTES.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine.
--
-- WHAT WAS WRONG. seat_duty sales_engineer.framework_proposal and sales_engineer.negotiation_round are enabled = false (the
-- founder removed best-and-final rounds and framework rates), yet their own cron jobs still fire every five minutes:
--   job 544 seat_duty:sales_engineer.framework_proposal  0-59/5 * * * *  active
--   job 542 seat_duty:sales_engineer.negotiation_round   0-59/5 * * * *  active
-- (production SELECT on cron.job, 16 Nov 2026). Each tick enters fn_seat_duty_run, which reads sd.enabled first and returns
-- {"ran": false}: 576 empty runs a day, each leaving a cron.job_run_details row for fn_cron_history_purge to delete.
--
-- WHAT THIS DOES. Unschedules the two jobs by name (idempotent: an absent job selects no row). The two seat_duty rows are
-- NOT touched: they stay enabled = false, which is what the founder's "stay off" files read, and their own_job = true means
-- fn_seat_duties_tick (enabled and not own_job only) never picks them up either. Nothing else runs these duties.
--
-- REVERSAL, one line per job (the exact command each job ran on 16 Nov 2026):
--   select cron.schedule('seat_duty:sales_engineer.framework_proposal', '0-59/5 * * * *', $c$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.framework_proposal');$c$);
--   select cron.schedule('seat_duty:sales_engineer.negotiation_round', '0-59/5 * * * *', $c$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.negotiation_round');$c$);

select cron.unschedule(j.jobid)
  from cron.job j
 where j.jobname in ('seat_duty:sales_engineer.framework_proposal', 'seat_duty:sales_engineer.negotiation_round');

-- PROBE: a verdict row. Both jobs are gone, both duties still exist and are still off, and no other job runs either duty.
with v as (select
  (select count(*) from cron.job where command ~ 'sales_engineer\.(framework_proposal|negotiation_round)') jobs_left,
  (select count(*) from public.seat_duty where duty in ('sales_engineer.framework_proposal', 'sales_engineer.negotiation_round')) duties,
  (select count(*) from public.seat_duty where duty in ('sales_engineer.framework_proposal', 'sales_engineer.negotiation_round') and enabled) duties_on)
select case when jobs_left = 0 and duties = 2 and duties_on = 0
            then 'PROBE OK: no cron job runs framework_proposal or negotiation_round; both duties kept, both still off'
            else 'PROBE FAILED: jobs left ' || jobs_left || ', duty rows ' || duties || ', duties enabled ' || duties_on end as verdict
  from v;
