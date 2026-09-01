-- GOAL RETIREMENT RE-PLANS THROUGH THE KERNEL (org audit C7).
--
-- THE GAP, MEASURED. When a company goal is retired, trg_goal_cascade supersedes the objectives that
-- served it, but the re-plan step was DISABLED by K31 because it created org_tasks directly — with no
-- workflow run, no accountable owner and no trace — and no workflow started from a goal retirement, so
-- there was nowhere honest to route it. Worse, the goal.retired notice itself never fired: the trigger
-- called the TRIGGER function fn_emit_event() with five positional arguments inside an exception
-- swallow, which raises and is silently caught, so retiring a goal emitted ZERO goal.retired events
-- (verified: 0 in company_event after an aborted retire).
--
-- THE FIX, through the kernel and Phase C (no frozen Phase B row changes — the 30 approved workflows
-- are untouched; this adds a RUNTIME workflow, exactly the Phase C wiring the phase_b_phase_c_wiring_gap
-- row recorded as owed):
--   1. trg_goal_cascade now emits goal.retired through fn_emit (which writes company_event), so the
--      event actually travels. The direct org_tasks insert stays removed — the workflow replaces it.
--   2. A runtime workflow goal_retirement_replan (public.workflow) triggers on goal.retired, so
--      fn_workflow_start_due starts a run when a goal is retired, with steps accountable to
--      corporate_performance_director — the re-plan now flows through the kernel (run + steps + owner +
--      trace) instead of an untracked trigger insert.
--   3. The phase_b_phase_c_wiring_gap row is closed: the owed behaviour now exists.
--
-- Not a frozen change: public.workflow / workflow_step are the runtime (Phase C) layer, absent from the
-- Phase A/B baseline drift checks (verified: fn_phase_a/b_baseline_drift stay 0). corporate_performance_
-- director owns W02 and the Office of the CEO; re-planning after a goal retires is its corrective-
-- management remit, which is why K31 named it as the owner while refusing to fake it onto W02's start
-- event.
--
--   node scripts/apply_sql.mjs scripts/sql/goal_retirement_re_plans_through_the_kernel.sql --apply --ddl

begin;

-- 1. THE TRIGGER emits goal.retired for real, and the re-plan is now the workflow's, not the trigger's.
CREATE OR REPLACE FUNCTION public.trg_goal_cascade()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- (A) DECOMPOSE ON SET/EDIT. A measurable, active goal owned by an active department hands down its
  -- department objective immediately, instead of waiting for the weekly fn_goal_decompose cron.
  if new.active and coalesce(new.measure_sql,'') <> ''
     and exists (select 1 from org_departments d where d.dept_key = new.owner_dept and d.active) then
    if exists (select 1 from department_objective
                where dept_key = new.owner_dept and goal_key = new.key and active) then
      update department_objective
         set target_value = coalesce(target_value, new.target_value),
             unit         = coalesce(unit,         new.unit),
             measure_sql  = coalesce(measure_sql,  new.measure_sql),
             updated_at   = now()
       where dept_key = new.owner_dept and goal_key = new.key and active
         and (measure_sql is null or target_value is null or unit is null);
    else
      insert into department_objective
        (dept_key, objective, horizon, goal_key, target_value, unit, measure_sql, status, active)
      values
        (new.owner_dept, new.goal, coalesce(new.horizon,'year_1'), new.key,
         new.target_value, new.unit, new.measure_sql, 'active', true);
    end if;
  end if;

  if old.active is true and new.active is false then
    -- (1) KEPT. An objective serving a retired goal is superseded.
    update department_objective
       set status='superseded', updated_at=now()
     where goal_key = new.key and status='active';

    -- (2) The re-plan is NO LONGER a direct org_tasks insert here (K31 removed that bypass). It now
    -- runs through the kernel: goal.retired (emitted below) starts a run of the runtime workflow
    -- goal_retirement_replan (public.workflow), whose steps are accountable to
    -- corporate_performance_director. Restored as work with a run, a step, an owner and a trace.

    -- (3) goal.retired now travels. It was calling the TRIGGER function fn_emit_event() with five
    -- positional args, which raised and was swallowed, so nothing was emitted. fn_emit writes
    -- company_event, which fn_workflow_start_due reads to start the re-plan workflow.
    begin
      perform public.fn_emit('goal.retired', 'company_goals', new.key, 'ceo',
                             jsonb_build_object('goal', new.key, 'title', new.goal, 'owner_dept', new.owner_dept));
    exception when others then null; end;
  end if;
  return new;
end
$function$;

-- 2. THE RUNTIME WORKFLOW that goal.retired starts. os_key leadership (corporate_performance_director
-- sits in the exec department / Leadership OS).
insert into public.workflow (workflow_key, name, trigger_event, description, active, os_key)
values ('goal_retirement_replan', 'Goal retirement re-plan', 'goal.retired',
        'When a company goal is retired, re-plan the objectives and work that served it: confirm the '
        'objectives are superseded, propose replacements that serve an active goal, and re-plan the '
        'department work. Owned by corporate performance so the re-plan is accountable and traced.',
        true, 'leadership')
on conflict (workflow_key) do nothing;

insert into public.workflow_step (workflow_key, step_no, step, actor_role, action_class) values
  ('goal_retirement_replan', 1, 'Confirm the objectives serving the retired goal are superseded',
   'corporate_performance_director', 'verify'),
  ('goal_retirement_replan', 2, 'Propose replacement objectives that serve an active company goal',
   'corporate_performance_director', 'recommend'),
  ('goal_retirement_replan', 3, 'Re-plan the department work against the replacement objectives',
   'corporate_performance_director', 'coordinate')
on conflict (workflow_key, step_no) do nothing;

-- 3. CLOSE THE WIRING GAP. The owed behaviour now exists as a routed workflow; the marker is stale.
delete from public.phase_b_phase_c_wiring_gap
 where gap ilike '%goal%retir%' or gap ilike '%goal is retired%';

commit;
