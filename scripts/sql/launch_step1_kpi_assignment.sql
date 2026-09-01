-- LAUNCH STEP 1 — SOMETHING ASSIGNS AND MAINTAINS KPIs.
--
-- Founder question: "who assigns KPI?" Measured answer before this: nobody. employee_kpi was
-- hand-seeded and nothing kept it in step with org_agents — 1 active agent carried no KPI and 5 active
-- KPIs belonged to agents that are no longer active. For a company that hires and retires AI staff on
-- its own for a year, a KPI has to follow the org automatically.
--
-- fn_employee_kpi_assign() does two things and reports what it could not do:
--   (1) retires any active KPI whose owner is no longer an active employee;
--   (2) gives every active agent that lacks a KPI one tied to its DEPARTMENT'S primary active
--       objective, inheriting that objective's measure and target so the KPI is scorable from day one
--       and is linked upward into the target cascade (serves_objective). An agent whose department has
--       no active objective is left uncovered and REPORTED, never given an un-measurable placeholder.
-- It runs the same way the other org-maintenance sweeps do (called directly, or by a cron when the
-- founder lifts the stand-down); it fires no external effect and calls no model.
--
-- SECURITY DEFINER + new function -> EXECUTE is revoked from PUBLIC in the same migration.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_kpi_assignment.sql --apply

CREATE OR REPLACE FUNCTION public.fn_employee_kpi_assign()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_retired int := 0; v_created int := 0; v_uncovered int;
begin
  -- (1) A KPI whose owner is no longer active is not a live target — retire it.
  update public.employee_kpi k set active = false
   where k.active
     and not exists (select 1 from public.org_agents a where a.agent_key = k.agent_key and a.active);
  get diagnostics v_retired = row_count;

  -- (2) Every active agent without a KPI gets one tied to its department's primary active objective,
  --     inheriting that objective's measure/target so a miss is detectable. Measurable objectives are
  --     preferred over un-measured ones for the link.
  -- Linked upward by serves_goal (the company-goal text key the objective cascade counts);
  -- serves_objective is a FK to os_objective, a different objective layer, so it stays null here.
  insert into public.employee_kpi
    (agent_key, kpi, metric, target_value, unit, cadence, serves_goal,
     measure_sql, no_measure_reason, active)
  select a.agent_key,
         'Contribute to: ' || left(o.objective, 120),
         coalesce(nullif(o.objective, ''), 'department objective'),
         o.target_value, o.unit, 'monthly', o.goal_key,
         nullif(o.measure_sql, ''),
         case when coalesce(o.measure_sql, '') = '' then 'department objective carries no measure yet' end,
         true
    from public.org_agents a
    join lateral (
       select dobj.* from public.department_objective dobj
        where dobj.dept_key = a.department and dobj.active
        order by (coalesce(dobj.measure_sql, '') <> '') desc, dobj.sort, dobj.id
        limit 1
    ) o on true
   where a.active
     and not exists (select 1 from public.employee_kpi k where k.agent_key = a.agent_key and k.active);
  get diagnostics v_created = row_count;

  select count(*) into v_uncovered
    from public.org_agents a
   where a.active
     and not exists (select 1 from public.employee_kpi k where k.agent_key = a.agent_key and k.active);

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('employee_kpi_assign', now(), now(), 'ok',
          jsonb_build_object('retired', v_retired, 'created', v_created, 'still_uncovered', v_uncovered),
          'Retired '||v_retired||' KPI(s) whose owner is no longer active; created '||v_created||
          ' KPI(s) tying an un-KPI''d active agent to its department''s primary objective. '||
          v_uncovered||' active agent(s) still without a KPI because their department has no active '||
          'objective — reported, not given an unmeasurable placeholder.');

  return jsonb_build_object('retired', v_retired, 'created', v_created, 'still_uncovered', v_uncovered);
end $function$;

revoke execute on function public.fn_employee_kpi_assign() from public;
