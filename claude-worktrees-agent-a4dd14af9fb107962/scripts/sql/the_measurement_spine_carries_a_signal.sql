-- THE MEASUREMENT SPINE CARRIES A SIGNAL (org audit B5).
--
-- THE GAP, MEASURED. org_tasks.objective_id was set on 1 of 1,095 rows and employee_kpi.serves_objective
-- on 0 of 122. The a05_org_task_fill_ownership trigger matched a department_objective.goal_key in the
-- task text (rarely present) and otherwise fell back to "the department's ONE active objective" — a
-- guard that can never fire because every one of the ten departments has several. So the spine that ties
-- work and KPIs to objectives was structurally empty.
--
-- THE FIX, at the source and then backfilled. objective_id -> department_objective (by dept_key,goal_key);
-- serves_objective -> os_objective (by the department's operating system, os_department.os_key). Both are
-- wired to their real FK targets, measured here, not assumed.
--   1. a05 trigger: keep the goal_key text match; replace the dead sole-objective fallback with the
--      department's PRIMARY active objective (measurable ones first) as an explainable default, so
--      departmental work is no longer objective-less.
--   2. fn_kpi_review: stamp objective_id on the KPI-miss task PRECISELY from the KPI's serves_goal ->
--      department_objective, overriding the trigger default with the exact objective.
--   3. fn_employee_kpi_assign: set serves_objective on KPI creation from the agent's department ->
--      os_department.os_key -> os_objective (primary, measurable first). Was deliberately left null.
--   4. Backfill the 1,094 tasks and 122 KPIs with the same deterministic logic.
--
-- department_objective (92 active) is the one live objective ledger for org_tasks; os_objective (50) is
-- the OS layer employee_kpi.serves_objective FKs to. Neither is fabricated: a KPI/task in a department or
-- OS with no objective stays null rather than being forced onto a wrong one.
--
--   node scripts/apply_sql.mjs scripts/sql/the_measurement_spine_carries_a_signal.sql --apply

begin;

-- 1. THE TRIGGER: a real linker, then a departmental default instead of a dead guard.
CREATE OR REPLACE FUNCTION public.fn_org_task_fill_ownership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_pick text; v_obj bigint; v_text text;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
    'compliance_check','legal_review','supplier_verify','capability_review','self_review'];
begin
  -- OBJECTIVE: the live department objective this task serves.
  if new.objective_id is null and coalesce(new.dept_key,'') <> '' then
    v_text := lower(coalesce(new.title,'')||' '||coalesce(new.detail,''));
    select o.id into v_obj
      from public.department_objective o
     where o.active and o.status='active' and o.dept_key = new.dept_key
       and coalesce(o.goal_key,'') <> ''
       and v_text ~ ('\y'||o.goal_key||'\y')
     order by length(o.goal_key) desc, o.id
     limit 1;
    if v_obj is null then
      -- DEFAULT: a department's work serves its PRIMARY active objective unless its text names
      -- another. This replaced 'exactly one objective', which never fired (every department has
      -- several) and left the spine empty. Measurable objectives are preferred for the default.
      select o.id into v_obj
        from public.department_objective o
       where o.active and o.status='active' and o.dept_key = new.dept_key
       order by (coalesce(o.measure_sql,'') <> '') desc, o.sort, o.id
       limit 1;
    end if;
    new.objective_id := v_obj;
  end if;

  -- OWNER: a task born as real work gets the least-loaded eligible colleague in its department.
  if new.assigned_agent is null and coalesce(new.status,'') in ('assigned','in_progress')
     and coalesce(new.dept_key,'') <> '' then
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status='active'
     where a.active and coalesce(a.available,true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = new.dept_key
       and (coalesce(rr.runtime_mode,'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(new.action_class,'') = any(REVIEW_CLASSES))
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks,6)
     order by case when p.tier='probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;
    new.assigned_agent := v_pick;   -- may remain null if the department is saturated
  end if;

  return new;
end $function$;

-- 2. fn_kpi_review: the KPI-miss task carries the EXACT objective the KPI serves.
CREATE OR REPLACE FUNCTION public.fn_kpi_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_opened int:=0; v_missed int:=0; v_nodata int:=0; v_title text; v_task bigint;
  v_remediated int:=0; v_trained int:=0; v_rem bigint; v_comp text; v_tr jsonb; v_agent text;
begin
  for r in select * from fn_kpi_scoreboard() loop
    if r.verdict='NO DATA' then v_nodata:=v_nodata+1; continue; end if;
    if r.verdict<>'MISSED' then continue; end if;
    v_missed := v_missed+1;
    v_title := 'KPI missed: '||r.metric||' ('||r.agent_key||')';
    if exists (select 1 from org_tasks where title=v_title and status<>'done') then continue; end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, objective_id)
    values (coalesce(r.department,'exec'), v_title,
      'Owner: '||r.agent_key||'. Target '||coalesce(r.target::text,'?')||' '||coalesce(r.unit,'')||
      ', actual '||coalesce(r.actual::text,'?')||' ('||coalesce(r.attainment::text,'?')||'% of target), cadence '||coalesce(r.cadence,'?')||
      '. Serves company goal: '||coalesce(r.serves_goal,'unassigned')||
      '. Diagnose the cause and either close the gap or propose a revised target with evidence.',
      'proposed','advisory', false, 'recommend',
      -- the objective this KPI serves, resolved precisely from serves_goal -> department_objective
      (select o.id from public.department_objective o
        where o.active and o.status='active' and o.dept_key = coalesce(r.department,'exec')
          and coalesce(r.serves_goal,'') <> '' and o.goal_key = r.serves_goal
        order by o.id limit 1))
    returning id into v_task;

    perform fn_outcome_open(
      p_actor           => r.agent_key,
      p_decision        => 'Close the gap on: '||r.metric,
      p_subject_type    => 'org_task',
      p_subject_id      => v_task::text,
      p_expected_kpi_id => r.kpi_id,
      p_rationale       => 'KPI missed at '||coalesce(r.attainment::text,'?')||'% of target. Opened automatically by the weekly KPI review.',
      p_direction       => case when r.unit='percent_max' then 'down' else 'up' end,
      p_measure_after   => case when r.cadence='weekly' then interval '14 days' else interval '35 days' end
    );

    v_comp := coalesce(nullif(r.serves_goal,''), r.metric);
    v_agent := coalesce(public.fn_org_agent_resolve(r.agent_key), r.agent_key);
    if exists (select 1 from org_agents o where o.agent_key = v_agent and o.active)
       and not exists (select 1 from agent_remediation ar
                    where ar.agent_key = v_agent and ar.failure_class = 'kpi_miss'
                      and coalesce(ar.detail->>'metric','') = r.metric and ar.status = 'open') then
      v_rem := fn_open_remediation(v_agent, 'kpi_miss', v_comp,
        jsonb_build_object('metric', r.metric, 'kpi_id', r.kpi_id, 'attainment', r.attainment,
                           'target', r.target, 'actual', r.actual, 'serves_goal', r.serves_goal,
                           'org_task_id', v_task, 'owner_key', r.agent_key, 'source', 'fn_kpi_review'));
      v_remediated := v_remediated + 1;
      begin
        v_tr := fn_assign_training(v_agent, null, 'practice', 3);
        v_trained := v_trained + coalesce((v_tr->>'assigned')::int, 0);
      exception when others then null;
      end;
    end if;

    v_opened := v_opened+1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('kpi_review', now(), now(), 'ok',
          jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata,
                             'remediations_opened',v_remediated,'practice_assigned',v_trained),
          'Weekly KPI review: '||v_missed||' missing target, '||v_opened||' task(s) + outcome record(s) opened, '
          ||v_remediated||' remediation(s) opened, '||v_trained||' practice case(s) assigned, '||v_nodata||' with no data.');
  return jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata,
                            'remediations_opened',v_remediated,'practice_assigned',v_trained);
end $function$;

-- 3. fn_employee_kpi_assign: a new KPI is tied to its operating system's objective too.
-- ROUTINE REMOVED 7 September 2026. public.fn_employee_kpi_assign was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 4. BACKFILL the existing spine with the same deterministic logic.
update public.org_tasks t
   set objective_id = coalesce(
     (select o.id from public.department_objective o
       where o.active and o.status='active' and o.dept_key = t.dept_key and coalesce(o.goal_key,'') <> ''
         and lower(coalesce(t.title,'')||' '||coalesce(t.detail,'')) ~ ('\y'||o.goal_key||'\y')
       order by length(o.goal_key) desc, o.id limit 1),
     (select o.id from public.department_objective o
       where o.active and o.status='active' and o.dept_key = t.dept_key
       order by (coalesce(o.measure_sql,'') <> '') desc, o.sort, o.id limit 1))
 where t.objective_id is null and coalesce(t.dept_key,'') <> '';

update public.employee_kpi k
   set serves_objective = (
     select oo.id from public.os_objective oo
       join public.os_department od on od.os_key = oo.os_key
       join public.org_agents a on a.agent_key = k.agent_key
      where od.dept_key = a.department and oo.active
      order by (coalesce(oo.measure_sql,'') <> '') desc, oo.id limit 1)
 where k.active and k.serves_objective is null;

commit;
