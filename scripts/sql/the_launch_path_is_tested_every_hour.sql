-- THE LAUNCH PATH IS TESTED EVERY HOUR (21 Sep 2026, it_engineer)
--
-- MEASURED. The supplier campaign launches ~23 Sep. The path an invited supplier and a customer take was
-- walked by the nightly journey (once a day, 02:00 Dubai) and by the post-deploy smoke (only after a
-- merge). Nothing looked at it in between, so a broken invitation page, a dead portal API or a sign-in
-- endpoint that stopped answering could sit unseen for up to 24 hours in the middle of the campaign.
--
-- WHAT THIS CHANGES. One row in public.resilience_step: the heartbeat (resilience_ping, every 15 min)
-- runs its new `launchpath` step at most once an hour. The step's probes are in
-- supabase/functions/_shared/launch_path.ts: the invitation link on www.quotesdone.com and quotesdone.ae
-- in EN and AR, the customer's /me page in EN and AR, supplier_portal and claim_lookup answering their
-- own refusals in ap-southeast-1, login_otp answering a reserved fixture mobile without sending, and the
-- five portal functions' x-qd-warm health. A broken path is ONE finding, duty:launch_path:down, through
-- the existing fn_it_duty_settle; the founder hears of it only via fn_it_engineer_alert_tick and
-- founder_mail_policy.
--
-- WHY THE HEARTBEAT AND NOT A GITHUB ACTIONS CRON. An hourly job is 720 billed minutes a month on the
-- allowance the 15-minute ping was moved off for (.github/workflows/resilience-ping.yml header).
--
-- budget_ms 8000: measured from Dubai on 21 Sep 2026, the fourteen probes in parallel finished in 0.9 s;
-- login_otp alone took 2.6-3.9 s cold earlier that day, and a retry adds 3 s plus the 12 s timeout at
-- worst. fn_resilience_step_record replaces the seed with ewma_ms
-- from the first run.
--
-- WHAT THIS DOES NOT CHANGE. No routine, no table, no policy. fn_resilience_tick_plan and the other
-- steps' rows are untouched (on conflict only this row's declared columns are refreshed).
-- ORDER: apply this BEFORE resilience_ping is deployed with the `launchpath` step, or the tick has a
-- runner the plan never names (scripts/checks/every_tick_step_is_scheduled.mjs fails until it is applied).
--
-- Prevented from coming back by: scripts/checks/the_launch_path_is_tested_every_hour.test.mjs (the
-- probes, their no-send guarantees and the no-flap rule), scripts/checks/every_tick_step_is_scheduled.mjs
-- (code and schedule agree), and the heartbeat's own starvation finding (duty:heartbeat:launchpath if the
-- step is passed over four ticks running).

insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('launchpath', interval '1 hour', 8000, 'plan', 0,
   'the launch path an invited supplier and a customer take, probed read-only (supabase/functions/_shared/launch_path.ts); one finding duty:launch_path:down')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms,
       place = excluded.place, rank = excluded.rank, note = excluded.note;

-- verdict row
select case when exists (select 1 from public.resilience_step
                          where step = 'launchpath' and every = interval '1 hour' and place = 'plan')
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;
