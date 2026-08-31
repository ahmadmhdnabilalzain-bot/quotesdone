-- LAUNCH STEP 1 — A NEW OR EDITED TARGET CASCADES DOWN THE MOMENT IT IS SET.
--
-- Measured 2026-08-31 on htdblwldjkcgjvmqkbeh: the CEO's AED 1,000,000 target is present and the
-- decomposition mechanism (fn_goal_decompose) routes it to a department_objective correctly. But
-- nothing cascaded a NEW or edited target automatically: trg_goal_cascade fired AFTER UPDATE only and
-- acted solely on goal RETIREMENT (old.active true -> new.active false), and its weekly driver
-- (fn_goal_decompose, cron jobid 251) is inactive under the stand-down. So a target the CEO adds or
-- refines propagated nothing downward until a human ran the batch.
--
-- This adds a decomposition arm that hands a measurable, active goal down to its owning department the
-- moment it is inserted or edited - the SAME adopt/create logic fn_goal_decompose runs, for the one
-- goal that changed. It writes ONLY a department_objective (an objective owned by the goal's owner
-- department). It does NOT create a task or a workflow: the K31 task-creation arm stays removed,
-- because a goal change starts no honest Phase B workflow and inventing one to obtain a connected
-- count is what the conduct rules forbid. The trigger is widened to AFTER INSERT OR UPDATE so a
-- freshly-created target cascades too; on INSERT, OLD is NULL and the retirement arm safely no-ops.
--
-- The adopt branch only fills NULLs and the create branch is guarded by "no active objective for this
-- (dept, goal) yet", so it is idempotent and cannot duplicate what fn_goal_decompose already made.
-- trg_goal_cascade is not a frozen subject; department_objective carries no freeze.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_a_new_target_cascades.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.trg_goal_cascade()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- (A) DECOMPOSE ON SET/EDIT. A measurable, active goal owned by an active department hands down its
  -- department objective immediately, instead of waiting for the weekly fn_goal_decompose cron. Same
  -- adopt/create logic as fn_goal_decompose, for this one goal. Objectives only, never tasks.
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
    -- (1) KEPT. An objective serving a retired goal is superseded. This is the goal's own record
    -- being made consistent, not the creation of work, and leaving it out would strand objectives
    -- against a goal that no longer exists.
    update department_objective
       set status='superseded', updated_at=now()
     where goal_key = new.key and status='active';

    -- (2) DISABLED BY K31 — this was the bypass. It created an operational task per affected
    -- department, with no workflow run, no step, no accountable owner resolved through the kernel
    -- and no trace. No Phase B workflow starts from a goal retirement, so there is nowhere honest
    -- to route it; inventing a workflow to obtain a connected count is what §3 forbids. The
    -- statement is left here, commented, so a reader sees what was removed:
    --
    --   insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    --   select distinct o.dept_key,
    --          'Re-plan after goal retired: '||new.key,
    --          'Company goal "'||coalesce(new.goal,new.key)||'" was retired. Objectives serving it
    --           are now superseded. Propose replacement objectives that serve an active goal.',
    --          'proposed','advisory', false, 'coordinate'
    --     from department_objective o
    --    where o.goal_key = new.key and o.status='superseded'
    --      and not exists (select 1 from org_tasks t
    --                       where t.title='Re-plan after goal retired: '||new.key and t.status<>'done');
    --
    -- It had never produced a row: org_tasks held zero 'Re-plan after goal retired' titles when
    -- this was written. The owed behaviour is recorded in phase_b_phase_c_wiring_gap.

    -- (3) KEPT. fn_emit_event does not write phase_c_event_outbox — measured, not assumed — so
    -- this is a legacy notice and not a second copy of a canonical domain event.
    begin
      perform fn_emit_event('goal.retired','company_goals',new.key,'ceo',
                            jsonb_build_object('goal',new.key));
    exception when others then null; end;
  end if;
  return new;
end
$function$;

-- Widen the trigger so a freshly-created target cascades too. AFTER UPDATE -> AFTER INSERT OR UPDATE.
DROP TRIGGER IF EXISTS trg_goal_cascade ON public.company_goals;
CREATE TRIGGER trg_goal_cascade AFTER INSERT OR UPDATE ON public.company_goals
  FOR EACH ROW EXECUTE FUNCTION public.trg_goal_cascade();
