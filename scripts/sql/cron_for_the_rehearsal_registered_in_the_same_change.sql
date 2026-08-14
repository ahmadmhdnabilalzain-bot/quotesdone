-- CRON FOR THE REHEARSAL, REGISTERED IN THE SAME CHANGE
--
-- "Resilience is measured BEFORE real incidents occur" is a claim about frequency, not about one
-- run. A rehearsal executed once by hand on 14 Aug is a rehearsal that happened, not a company that
-- rehearses. Weekly, Sunday 03:10 UTC — quiet, and before the Monday 05:00 exec meeting so the
-- results are on the table when the officers report.
--
-- Registered in cron_registry in the SAME file: an unregistered job dropped Row #3 from 130 to 129
-- via s38 on 14 Aug, and the answer to that check is to register the job, never to relax it.

select cron.schedule('scenario_rehearsal_weekly', '10 3 * * 0',
                     $$select public.fn_scenario_rehearse_all();$$);

insert into public.cron_registry (jobname, human_name, category, purpose)
values ('scenario_rehearsal_weekly', 'Rehearse the failure scenarios', 'continuity',
        'Poses each failure scenario that has a rehearsal defined and computes the answer its expected_behaviour demands from live rows — burn rate, committed spend, measured campaign contribution, the response owner. Writes last_run and last_result. A scenario whose required facts cannot all be produced is recorded INCOMPLETE and names the missing fact; a scenario with no rehearsal defined is left untouched and keeps a null last_run.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
