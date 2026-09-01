-- THE MEASURE SPINE LEAVES NO KPI UNLINKED (autonomy audit, degrading gap 9).
--
-- MEASURED. 17 of 122 active KPIs (8 of them headline primary-objective rows) carry a NULL
-- serves_objective, so their attainment climbs to nothing — the objective they feed cannot be scored
-- from them. fn_employee_kpi_assign already resolves the link for NEW rows (agent -> department ->
-- operating system -> that OS's primary objective), but it is UNSCHEDULED, so the link is never
-- maintained and the existing NULLs were never healed.
--
-- THIS FILE:
--   1. heals the NULL serves_objective on active KPIs with the SAME resolver the assigner uses, so a KPI
--      points at the OS objective its owner's department serves. MEASURED: it links 0 of the current 17,
--      because those 17 sit under departments that map to no active OS objective (the orphan-OS symptom
--      the structure audit flags separately) — an honest no-op, never a fabricated link. It heals any
--      KPI that IS resolvable, now and on every future run.
--   2. schedules fn_employee_kpi_assign daily (DISABLED, before the measure job), documented in
--      cron_registry, so the link is kept current and unassigned agents get a KPI once the founder
--      resumes. This scheduling — the assigner was never scheduled — is the file's live deliverable.
-- (os_objective still lacks a target_value to score the OS tier met/missed — a larger change that must
-- choose real targets — deferred; and the 17 unresolved links need the OS-structure fix first.)
--
--   node scripts/apply_sql.mjs scripts/sql/the_measure_spine_leaves_no_kpi_unlinked.sql --apply --ddl

begin;

update public.employee_kpi k
   set serves_objective = (
         select oo.id
           from public.os_objective oo
           join public.os_department od on od.os_key = oo.os_key
           join public.org_agents a on a.agent_key = k.agent_key
          where od.dept_key = a.department and oo.active
          order by (coalesce(oo.measure_sql,'') <> '') desc, oo.id
          limit 1)
 where k.active
   and k.serves_objective is null
   and exists (
         select 1 from public.os_objective oo
           join public.os_department od on od.os_key = oo.os_key
           join public.org_agents a on a.agent_key = k.agent_key
          where od.dept_key = a.department and oo.active);

-- daily 04:40 UTC, before the objective/KPI measures. DISABLED (writes work-adjacent rows while the
-- workforce is down); enable-ready on resume. cron.schedule re-activates on re-apply, so the disable
-- runs last.
select cron.schedule('employee_kpi_assign_daily', '40 4 * * *', $$select public.fn_employee_kpi_assign();$$);
select cron.alter_job((select jobid from cron.job where jobname='employee_kpi_assign_daily'), active := false);
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('employee_kpi_assign_daily', 'Keep every employee KPI linked to an objective', 'strategy',
  'Daily: assigns a KPI to any active agent that has none and links each KPI to the OS objective its owner''s department serves, so the objective tier can always be scored from its KPIs. Scheduled disabled until the founder resumes.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

commit;
