-- A TASK IS BORN OWNED AND TIED TO ITS TARGET — org_tasks.assigned_agent and objective_id at creation.
--
-- Two gaps measured on htdblwldjkcgjvmqkbeh:
--
-- 1. objective_id was set by ZERO inserts and could not be: its FK pointed at public.org_objectives,
--    the DEAD founder-objective table (0 rows) that everything else was repointed off. The LIVE
--    objectives are in public.department_objective, which is exactly what fn_founder_brief already
--    joins objective_id against (`o.id = t.objective_id`, o = department_objective). So the FK is
--    repointed to the table the column is actually used against. All 1095 rows are null, so nothing
--    is orphaned by the change; ON DELETE SET NULL so a task outlives an objective being superseded.
--
-- 2. assigned_agent was set at creation by a single hardcoded inserter; every other task waited for
--    the fn_org_task_assign sweep, and 'proposed' tasks never got there at all.
--
-- One BEFORE INSERT trigger fills both at birth, for every inserter (the event handler, fn_exec_meeting,
-- fn_kpi_review and the rest) rather than editing each:
--   * objective_id: the live department objective this task's department serves and NAMES — the goal
--     whose key appears as a whole word in the title/detail (fn_kpi_review writes "Serves company
--     goal: <key>", the cascade names it too), most specific first; or the department's sole active
--     objective when it has exactly one; else left null rather than mislinked.
--   * assigned_agent: for a task born 'assigned'/'in_progress', the least-loaded eligible colleague
--     in the owning department, by the same rule fn_org_task_assign uses (skip independent reviewers
--     for non-review work, never past max_open_tasks). A saturated department leaves it null — visible,
--     as before. Proposals are owned when accepted, not at birth.
--
-- No LLM. Pure routing.
--
--   node scripts/apply_sql.mjs scripts/sql/a_task_is_born_owned_and_tied_to_its_target.sql --apply --ddl

begin;

-- 1. Repoint the objective FK from the dead table to the live objective layer.
alter table public.org_tasks drop constraint if exists org_tasks_objective_id_fkey;
alter table public.org_tasks
  add constraint org_tasks_objective_id_fkey
  foreign key (objective_id) references public.department_objective(id) on delete set null;

-- 2. Fill ownership at birth.
create or replace function public.fn_org_task_fill_ownership()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public','pg_temp'
as $fn$
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
      -- exactly one active objective in the department => that is the one it serves
      select case when count(*)=1 then min(o.id) end into v_obj
        from public.department_objective o
       where o.active and o.status='active' and o.dept_key = new.dept_key;
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
end $fn$;

revoke execute on function public.fn_org_task_fill_ownership() from public;

drop trigger if exists a05_org_task_fill_ownership on public.org_tasks;
create trigger a05_org_task_fill_ownership
  before insert on public.org_tasks
  for each row execute function public.fn_org_task_fill_ownership();

-- 3. Backfill the objective link on open tasks that already name their goal.
update public.org_tasks t
   set objective_id = sub.oid, updated_at = now()
  from (
    select t2.id,
           (select o.id from public.department_objective o
             where o.active and o.status='active' and o.dept_key = t2.dept_key
               and coalesce(o.goal_key,'') <> ''
               and lower(coalesce(t2.title,'')||' '||coalesce(t2.detail,'')) ~ ('\y'||o.goal_key||'\y')
             order by length(o.goal_key) desc, o.id limit 1) as oid
      from public.org_tasks t2
     where t2.objective_id is null and t2.status not in ('done','cancelled','failed')
  ) sub
 where t.id = sub.id and sub.oid is not null;

commit;
