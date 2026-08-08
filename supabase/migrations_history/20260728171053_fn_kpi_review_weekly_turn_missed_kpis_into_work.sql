-- A measurement nobody reads is not management. fn_kpi_scoreboard() was built today
-- but no scheduled job consumed it. This turns a missed KPI into actual work on the
-- owning department's list, which is what a real manager does at a weekly review.
create or replace function public.fn_kpi_review()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r record;
  v_opened int := 0;
  v_missed int := 0;
  v_nodata int := 0;
  v_title  text;
begin
  for r in select * from fn_kpi_scoreboard() loop

    if r.verdict = 'NO DATA' then
      v_nodata := v_nodata + 1;
      continue;
    end if;

    if r.verdict <> 'MISSED' then
      continue;
    end if;

    v_missed := v_missed + 1;
    v_title := 'KPI missed: ' || r.metric || ' (' || r.agent_key || ')';

    -- idempotent: never stack duplicates of an unresolved item
    if exists (
      select 1 from org_tasks
      where title = v_title and status <> 'done'
    ) then
      continue;
    end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    values (
      coalesce(r.department, 'exec'),
      v_title,
      'Owner: ' || r.agent_key ||
      '. Target ' || coalesce(r.target::text,'?') || ' ' || coalesce(r.unit,'') ||
      ', actual ' || coalesce(r.actual::text,'?') ||
      ' (' || coalesce(r.attainment::text,'?') || '% of target), cadence ' || coalesce(r.cadence,'?') ||
      '. Serves company goal: ' || coalesce(r.serves_goal,'unassigned') ||
      '. Diagnose the cause and either close the gap or propose a revised target with evidence.',
      'proposed',
      'advisory',
      false,
      'recommend'
    );
    v_opened := v_opened + 1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('kpi_review', now(), now(),
          case when v_missed > 0 and v_opened = 0 then 'ok' else 'ok' end,
          jsonb_build_object('missed', v_missed, 'opened', v_opened, 'no_data', v_nodata),
          'Weekly KPI review: ' || v_missed || ' KPI(s) missing target, ' || v_opened ||
          ' new task(s) opened, ' || v_nodata || ' KPI(s) had no data in the measurement window.');

  return jsonb_build_object('missed', v_missed, 'opened', v_opened, 'no_data', v_nodata);
end
$fn$;

revoke execute on function public.fn_kpi_review() from public, anon, authenticated;

comment on function public.fn_kpi_review() is
  'Weekly. Evaluates every KPI and opens an org_task against the owning department for each MISSED target. Idempotent: will not duplicate an unresolved task.';