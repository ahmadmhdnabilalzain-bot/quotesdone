-- xos-11. THE INTELLIGENCE OS WAS ALERTING OFF FIGURES NOBODY REFRESHED.
--
-- Measured on production 2026-08-06: public.fn_bi_snapshot() — the only writer of
-- metric_snapshot, and therefore the only thing that ever moves v_bi_scorecard — has ZERO
-- callers in pg_proc and ZERO rows in cron.job. max(metric_snapshot.taken_at) was
-- 2026-07-27 00:44, ten days stale, 0 rows in the last 7 days. v_bi_scorecard takes
-- DISTINCT ON (metric_key) ... ORDER BY taken_at DESC, so every OFF_TARGET verdict this
-- function emitted was a verdict on a ten-day-old number, and every ON_TARGET metric was
-- unfalsifiable: a KPI that stops being measured can never be missed.
--
-- This is the same defect the spec file exists to catch, one layer down — an asset that was
-- built, is correct, and is called by nothing. The fix is one line and it belongs here rather
-- than in a new cron: the routine that judges the metrics is the routine that must take them.
-- Cadence is this function's own cron (emit_metric_alerts, '0 3 * * 1'), so the figures are at
-- most a week old, which is what xos-11 now asserts.
create or replace function public.fn_emit_metric_alerts()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare n integer := 0; r record; v_off int := 0; v_names text;
begin
  -- Take the measurement before judging it. See the header.
  perform count(*) from public.fn_bi_snapshot();

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

  -- xos-13. The scorecard state itself, as the Intelligence OS's declared output.
  select count(*), string_agg(metric_key, ', ' order by metric_key)
    into v_off, v_names from v_bi_scorecard where state = 'OFF_TARGET';
  if v_off > 0 and not exists (
    select 1 from company_event e where e.event_type = 'metric.alert'
      and e.occurred_at > date_trunc('day', now())) then
    perform public.fn_emit('metric.alert', 'scorecard', 'v_bi_scorecard', 'intel_director',
              jsonb_build_object('off_target', v_off, 'metrics', v_names));
    n := n + 1;
  end if;

  return n;
end; $function$;
