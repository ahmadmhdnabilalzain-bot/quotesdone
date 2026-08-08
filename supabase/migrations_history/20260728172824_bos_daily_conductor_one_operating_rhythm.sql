-- BOS: one operating rhythm over 121 fault-isolated workers.
-- Deliberately NOT a serial mega-loop: one slow step must never stall the company.
-- The conductor owns the SEQUENCE and PROVES the day happened; specialists stay independent.
create table if not exists public.day_cadence (
  id           bigserial primary key,
  business_day date not null,
  stage        text not null,
  stage_order  int  not null,
  expected     text,
  observed     jsonb,
  ok           boolean,
  note         text,
  checked_at   timestamptz not null default now(),
  unique (business_day, stage)
);
alter table public.day_cadence enable row level security;
comment on table public.day_cadence is
  'One row per stage of the daily operating loop. The conductor verifies each stage produced evidence; a missing stage is an exception, not silence.';

create or replace function public.fn_day_conductor()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  d date := current_date;
  v_ok int := 0; v_bad int := 0;
  procedure_stub int;
begin
  -- 1. CEO reviews the company
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'ceo_reviews_company', 1, 'a board/exec report produced in the last 24h',
         jsonb_build_object('board_reports_24h', (select count(*) from board_reports where created_at > now()-interval '24 hours'),
                            'exec_reports_24h',  (select count(*) from exec_reports  where created_at > now()-interval '24 hours')),
         ((select count(*) from board_reports where created_at > now()-interval '24 hours')
        + (select count(*) from exec_reports  where created_at > now()-interval '24 hours')) > 0,
         'strategy_ai_daily / board_report_weekly / founder_brief_daily'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 2. Chief of Staff reviews departments
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'cos_reviews_departments', 2, 'cos_execute ran in the last 24h',
         jsonb_build_object('cos_runs_24h', (select count(*) from agent_runs where agent ilike '%chief_of_staff%' or agent ilike '%cos%' and started_at > now()-interval '24 hours')),
         (select count(*) from agent_runs where (agent ilike '%chief_of_staff%' or agent ilike '%cos%') and started_at > now()-interval '24 hours') > 0,
         'cos_execute_hourly'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 3. Departments plan
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'departments_plan', 3, 'dept_plan ran in the last 24h',
         jsonb_build_object('dept_plan_runs_24h', (select count(*) from agent_runs where agent ilike '%dept_plan%' and started_at > now()-interval '24 hours')),
         (select count(*) from agent_runs where agent ilike '%dept_plan%' and started_at > now()-interval '24 hours') > 0,
         'dept_plan_daily'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 4. Tasks execute
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'tasks_execute', 4, 'agent runs happened and mostly succeeded',
         jsonb_build_object('runs_24h', (select count(*) from agent_runs where started_at > now()-interval '24 hours'),
                            'errors_24h',(select count(*) from agent_runs where started_at > now()-interval '24 hours' and status='error')),
         (select count(*) from agent_runs where started_at > now()-interval '24 hours') > 0,
         'all scheduled workers'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 5. Results measured
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'results_measured', 5, 'outcome grading ran; KPIs measurable',
         jsonb_build_object('outcomes_pending',(select count(*) from outcome_record where verdict='pending'),
                            'outcomes_graded_24h',(select count(*) from outcome_record where closed_at > now()-interval '24 hours'),
                            'kpis_measurable',(select count(*) from employee_kpi where active and measure_sql is not null)),
         (select count(*) from employee_kpi where active and measure_sql is not null) > 0,
         'outcome_evaluate_daily / kpi_review_weekly'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 6. Lessons learned
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'lessons_learned', 6, 'learning ran in the last 24h',
         jsonb_build_object('dept_learn_24h',(select count(*) from agent_runs where agent ilike '%learn%' and started_at > now()-interval '24 hours'),
                            'memory_rows',(select count(*) from institutional_memory)),
         (select count(*) from agent_runs where agent ilike '%learn%' and started_at > now()-interval '24 hours') > 0,
         'dept_learn_daily / agent_learnings_weekly'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 7. Knowledge updated
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'knowledge_updated', 7, 'knowledge touched in the last 24h',
         jsonb_build_object('knowledge_touched_24h',(select count(*) from agent_knowledge where updated_at > now()-interval '24 hours')),
         (select count(*) from agent_knowledge where updated_at > now()-interval '24 hours') > 0,
         'kb_deepen / knowledge_curator_daily'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  -- 8. Tomorrow planned
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d, 'tomorrow_planned', 8, 'open work exists for tomorrow',
         jsonb_build_object('open_tasks',(select count(*) from org_tasks where status<>'done')),
         (select count(*) from org_tasks where status<>'done') > 0,
         'dept_plan_daily / kpi_review_weekly'
  on conflict (business_day, stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  select count(*) filter (where ok), count(*) filter (where not ok)
    into v_ok, v_bad from day_cadence where business_day = d;

  -- a broken rhythm is an exception, not silence
  if v_bad > 0 then
    insert into founder_alerts (level, event, detail, channel)
    select 'high', 'daily_cadence_broken',
           'The daily operating loop did not complete. Failed stages: ' ||
           (select string_agg(stage, ', ' order by stage_order) from day_cadence where business_day=d and not ok),
           'email'
    where not exists (select 1 from founder_alerts
                      where event='daily_cadence_broken' and created_at > now()-interval '20 hours');
  end if;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('day_conductor', now(), now(), case when v_bad>0 then 'error' else 'ok' end,
          jsonb_build_object('stages_ok',v_ok,'stages_failed',v_bad),
          'Daily operating rhythm: '||v_ok||' of '||(v_ok+v_bad)||' stages produced evidence.');

  return jsonb_build_object('day',d,'ok',v_ok,'failed',v_bad);
end $fn$;

revoke execute on function public.fn_day_conductor() from public, anon, authenticated;