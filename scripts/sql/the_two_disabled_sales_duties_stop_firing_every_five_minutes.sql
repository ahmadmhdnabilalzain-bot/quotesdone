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
-- WHAT THIS DOES. Unschedules the two jobs by name (idempotent: an absent job selects no row) and sets own_job = false on
-- the two duties, as the 10 Nov retirement of accountant.receipt_bank_match did: an own_job duty with no job fails
-- scripts/checks/seat_duties_run_on_their_clock.test.mjs ('an own_job duty has no job'). enabled stays false, which is what
-- the founder's "stay off" files read, so fn_seat_duties_tick (enabled and not own_job) still never picks them up; if one is
-- ever switched back on, the shared tick runs it and fn_seat_duty_isolate gives it its own job again if it is slow.
--
-- REVERSAL (the exact command each job ran on 16 Nov 2026, and own_job as it was):
--   update public.seat_duty set own_job = true where duty in ('sales_engineer.framework_proposal', 'sales_engineer.negotiation_round');
--   select cron.schedule('seat_duty:sales_engineer.framework_proposal', '0-59/5 * * * *', $c$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.framework_proposal');$c$);
--   select cron.schedule('seat_duty:sales_engineer.negotiation_round', '0-59/5 * * * *', $c$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.negotiation_round');$c$);

select cron.unschedule(j.jobid)
  from cron.job j
 where j.jobname in ('seat_duty:sales_engineer.framework_proposal', 'seat_duty:sales_engineer.negotiation_round');

update public.seat_duty set own_job = false
 where duty in ('sales_engineer.framework_proposal', 'sales_engineer.negotiation_round') and own_job;

-- PROBE: a verdict row. Both jobs are gone, both duties still exist and are still off, and no other job runs either duty.
with v as (select
  (select count(*) from cron.job where command ~ 'sales_engineer\.(framework_proposal|negotiation_round)') jobs_left,
  (select count(*) from public.seat_duty where duty in ('sales_engineer.framework_proposal', 'sales_engineer.negotiation_round')) duties,
  (select count(*) from public.seat_duty where duty in ('sales_engineer.framework_proposal', 'sales_engineer.negotiation_round') and enabled) duties_on,
  (select count(*) from public.seat_duty s where s.own_job and not exists (select 1 from cron.job c where c.jobname = 'seat_duty:' || s.duty)) own_without_job)
select case when jobs_left = 0 and duties = 2 and duties_on = 0 and own_without_job = 0
            then 'PROBE OK: no cron job runs framework_proposal or negotiation_round; both duties kept, both still off; no own_job duty lacks its job'
            else 'PROBE FAILED: jobs left ' || jobs_left || ', duty rows ' || duties || ', duties enabled ' || duties_on || ', own_job duties without a job ' || own_without_job end as verdict
  from v;
