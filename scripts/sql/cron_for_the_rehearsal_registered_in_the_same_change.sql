-- CRON FOR THE REHEARSAL, REGISTERED IN THE SAME CHANGE
--
-- "Resilience is measured BEFORE real incidents occur" is a claim about frequency, not about one
-- run. A rehearsal executed once by hand on 14 Aug is a rehearsal that happened, not a company that
-- rehearses. Weekly, Sunday 03:10 UTC — quiet, and before the Monday 05:00 exec meeting so the
-- results are on the table when the officers report.
--
-- Registered in cron_registry in the SAME file: an unregistered job dropped Row #3 from 130 to 129
-- via s38 on 14 Aug, and the answer to that check is to register the job, never to relax it.

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

insert into public.cron_registry (jobname, human_name, category, purpose)
values ('scenario_rehearsal_weekly', 'Rehearse the failure scenarios', 'continuity',
        'Poses each failure scenario that has a rehearsal defined and computes the answer its expected_behaviour demands from live rows — burn rate, committed spend, measured campaign contribution, the response owner. Writes last_run and last_result. A scenario whose required facts cannot all be produced is recorded INCOMPLETE and names the missing fact; a scenario with no rehearsal defined is left untouched and keeps a null last_run.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
