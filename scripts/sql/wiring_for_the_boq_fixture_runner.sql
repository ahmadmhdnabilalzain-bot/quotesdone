-- Wiring for boq_fixture_check: inbound scope, the hop it makes, and cron.
--
-- It makes NO model call of its own - it posts the drawing to drawing_boq, which owns the vision
-- call and its own fn_task_class routing - so there is no cred_fn_ credential to issue and no
-- audit-95 registration. What it needs is (a) to be accepted when cron presents cred_cron_agents,
-- and (b) permission to make the one hop it makes.

-- 1. INBOUND. requireInternal checks the presented credential's scope against this function's slug.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['boq_fixture_check']) s)
 where context = 'cron.agents' and active and not (scope @> array['boq_fixture_check']);

-- 2. THE HOP. It forwards the SAME credential it received to drawing_boq, so that credential must
--    also name drawing_boq or the callee refuses it. Widened deliberately and narrowly: this adds
--    one callee to one context, and drawing_boq is a read-and-reason function that writes no
--    business record of its own.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['drawing_boq']) s)
 where context = 'cron.agents' and active and not (scope @> array['drawing_boq']);

-- 3. CRON. Weekly, matching KPI 103's own cadence ('monthly' is the KPI cadence but the fixture is
--    cheap and a weekly grade catches a regression inside the month rather than after it). Sunday
--    04:10 UTC sits clear of the 03:10-03:50 measurement block so it is not competing with
--    fn_employee_kpi_measure for the same minute.
--
--    URL FROM app_secrets.project_ref AT RUN TIME, never a literal ref - this same text is applied
--    to both projects and a hardcoded production ref would give staging a job that grades
--    production's pipeline.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

-- 4. THE MANUAL. s38-manual-always-current went MET earlier today by registering six undocumented
--    jobs; a seventh added without an entry would take it straight back to MISSING.
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('boq_fixture_check_weekly', 'BOQ extraction accuracy against the fixture set', 'Intelligence',
   'Sundays 04:10 UTC. Reads each active boq_fixture''s drawing out of storage, posts it to '
   || 'drawing_boq exactly as a real caller would, and grades the result with fn_boq_fixture_score '
   || 'against expectations transcribed from the drawing''s OWN printed schedule - door and window '
   || 'counts exactly, area within tolerance, and NULL expectations not scored at all. Feeds '
   || 'employee_kpi 103 (boq_analyst, target 95%). A grading that cannot reach the pipeline is '
   || 'recorded ok=false and excluded from the KPI, so an outage reads as "not measured" rather '
   || 'than as the employee scoring zero.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
