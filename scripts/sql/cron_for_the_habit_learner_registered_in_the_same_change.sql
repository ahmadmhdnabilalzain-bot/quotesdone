-- CRON FOR THE HABIT LEARNER, REGISTERED IN THE SAME CHANGE
--
-- fn_founder_habits_learn is worthless run once by hand: a habit is a moving average over what the
-- founder keeps doing, and a store computed on 14 Aug and never again is a snapshot pretending to
-- be a profile. Daily at 04:20 UTC, after the nightly writers have settled and before the 05:00
-- Monday exec meeting reads anything.
--
-- REGISTERED IN cron_registry IN THE SAME FILE, deliberately. On 14 Aug a cron was scheduled and
-- not registered, and s38 correctly dropped Row #3 from 130 to 129 for it. The check was working:
-- an unregistered job is a job nobody can explain, and the answer is to register it, never to relax
-- the check.

select cron.schedule('founder_habits_daily', '20 4 * * *',
                     $$select public.fn_founder_habits_learn();$$);

insert into public.cron_registry (jobname, human_name, category, purpose)
values ('founder_habits_daily', 'Learn the founder''s habits', 'intelligence',
        'Recomputes public.founder_habit from the founder''s own decisions on agent_actions — what he approves, what he rejects and how long he takes per kind. Every habit carries its sample size and is marked unconfident below three observations. Presentation adapts to these; governance does not.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
