-- Q8: department_objective had no link to company_goals, so a CEO reprioritisation had
-- nothing to cascade through and superseded objectives were orphaned undetectably.
alter table public.department_objective
  add column if not exists goal_key text references company_goals(key),
  add column if not exists status text not null default 'active'
      check (status in ('active','superseded','achieved','dropped')),
  add column if not exists superseded_by bigint,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists department_objective_goal_idx on public.department_objective (goal_key);

-- Best-effort auto-link: match each objective to a goal owned by the same department.
update department_objective o
set goal_key = g.key
from (
  select distinct on (owner_dept) owner_dept, key
  from company_goals where active and owner_dept is not null
  order by owner_dept, sort nulls last, key
) g
where o.goal_key is null and o.dept_key = g.owner_dept;

-- Cascade: when a company goal is deactivated, every objective serving it is marked
-- superseded and the owning department gets work to re-plan. No more orphans.
create or replace function public.trg_goal_cascade()
returns trigger
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
begin
  if old.active is true and new.active is false then
    update department_objective
       set status='superseded', updated_at=now()
     where goal_key = new.key and status='active';

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    select distinct o.dept_key,
           'Re-plan after goal retired: '||new.key,
           'Company goal "'||coalesce(new.goal,new.key)||'" was retired. Objectives serving it are now superseded. Propose replacement objectives that serve an active goal.',
           'proposed','advisory', false, 'coordinate'
      from department_objective o
     where o.goal_key = new.key and o.status='superseded'
       and not exists (select 1 from org_tasks t where t.title='Re-plan after goal retired: '||new.key and t.status<>'done');

    begin
      perform fn_emit_event('goal.retired','company_goals',new.key,'ceo',
                            jsonb_build_object('goal',new.key));
    exception when others then null; end;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_goal_cascade on public.company_goals;
create trigger trg_goal_cascade after update on public.company_goals
  for each row execute function public.trg_goal_cascade();

-- Q9: goal_period had 183 rows, 0 actual values and no writer. Department-level
-- measurement was a table nobody filled. Fill it from the live goal measures.
create or replace function public.fn_goal_period_refresh()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v numeric; n int := 0;
begin
  for r in
    select gp.id, gp.goal_key, gp.target_value, g.measure_sql, g.direction
    from goal_period gp join company_goals g on g.key = gp.goal_key
    where g.active and g.measure_sql is not null
  loop
    v := null;
    begin execute r.measure_sql into v; exception when others then v := null; end;
    if v is not null then
      update goal_period
         set actual_value = v,
             status = case
               when r.target_value is null or r.target_value = 0 then 'tracking'
               when coalesce(r.direction,'up') = 'down'
                 then case when v <= r.target_value then 'on_track' else 'at_risk' end
                 else case when v >= r.target_value then 'on_track'
                           when v >= r.target_value * 0.9 then 'near' else 'at_risk' end
             end,
             updated_at = now()
       where id = r.id;
      n := n + 1;
    end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('goal_period_refresh', now(), now(), 'ok', jsonb_build_object('updated', n),
          'Department/company goal periods refreshed from live measures: '||n||' rows updated.');
  return jsonb_build_object('updated', n);
end $fn$;

revoke execute on function public.fn_goal_period_refresh() from public, anon, authenticated;