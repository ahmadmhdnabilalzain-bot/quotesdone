-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727014443   name: goal_at_risk_one_per_department
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- First pass emitted one goal.at_risk per goal per off-target metric: 38 events and 38 tasks
-- for what is really one fact per department. A signal that floods is a signal nobody reads.
create or replace function public.fn_emit_metric_alerts() returns integer
language plpgsql security definer set search_path = public as $fn$
declare n integer := 0; r record;
begin
  for r in
    select metric_key, label, value, target, owner_dept, state from v_bi_scorecard
    where state = 'OFF_TARGET'
  loop
    if not exists (
      select 1 from company_event e
      where e.event_type = 'kpi.missed' and e.entity_id = r.metric_key
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('kpi.missed','metric', r.metric_key, coalesce(r.owner_dept,'exec'),
              jsonb_build_object('label', r.label, 'value', r.value, 'target', r.target, 'state', r.state));
      n := n + 1;
    end if;
  end loop;

  -- One goal.at_risk per DEPARTMENT per day, naming the goals and the failing metrics.
  for r in
    select s.owner_dept,
           array_agg(distinct s.label) as failing_metrics,
           (select array_agg(g.key) from company_goals g where g.active and g.owner_dept = s.owner_dept) as goals
    from v_bi_scorecard s
    where s.state = 'OFF_TARGET' and s.owner_dept is not null
    group by s.owner_dept
  loop
    if r.goals is not null and not exists (
      select 1 from company_event e
      where e.event_type = 'goal.at_risk' and e.entity_id = r.owner_dept
        and e.occurred_at > date_trunc('day', now())
    ) then
      insert into company_event (event_type, entity_type, entity_id, actor, payload)
      values ('goal.at_risk','department', r.owner_dept, r.owner_dept,
              jsonb_build_object('failing_metrics', r.failing_metrics, 'goals_at_risk', r.goals));
      n := n + 1;
    end if;
  end loop;

  return n;
end; $fn$;

revoke execute on function public.fn_emit_metric_alerts() from anon, authenticated, public;

-- Undo the flood: remove the per-goal events, their deliveries and the tasks they spawned.
delete from org_tasks where decided_by = 'fn_event_dispatch'
  and id in (select task_id from event_delivery d
             join company_event e on e.id = d.event_id
             where e.event_type = 'goal.at_risk' and e.entity_type = 'company_goal');
delete from event_delivery d using company_event e
  where e.id = d.event_id and e.event_type = 'goal.at_risk' and e.entity_type = 'company_goal';
delete from company_event where event_type = 'goal.at_risk' and entity_type = 'company_goal';
