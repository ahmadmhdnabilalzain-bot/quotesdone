-- FALSE ALARM CORRECTED. The conductor flagged departments_plan and lessons_learned as
-- broken because it looked for an agent_runs row. cron.job_run_details shows dept_plan_daily
-- and dept_learn_daily both ran and SUCCEEDED (4 runs each in 7 days, last today 01:00 and
-- 00:30) - those functions simply do not always write an agent_runs row. A monitor that
-- raises a false alarm every morning is worse than no monitor, so the check now reads the
-- authoritative source: did the scheduled job actually fire and succeed.

create or replace function public.fn_cron_ran(p_jobname text, p_within interval default '26 hours')
returns boolean
language plpgsql stable security definer set search_path to 'cron','public','pg_temp'
as $fn$
declare v boolean;
begin
  select exists (
    select 1 from cron.job j
    join cron.job_run_details d on d.jobid = j.jobid
    where j.jobname = p_jobname
      and d.start_time > now() - p_within
      and d.status = 'succeeded'
  ) into v;
  return coalesce(v,false);
exception when others then
  return true;  -- if the history is unreadable, do not raise a false alarm
end $fn$;

create or replace function public.fn_day_conductor()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare d date := current_date; v_ok int := 0; v_bad int := 0;
begin
  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'ceo_reviews_company',1,'an exec or board report in the last 24h',
    jsonb_build_object('board_reports_24h',(select count(*) from board_reports where created_at>now()-interval '24 hours'),
                       'exec_reports_24h',(select count(*) from exec_reports where created_at>now()-interval '24 hours')),
    ((select count(*) from board_reports where created_at>now()-interval '24 hours')
   + (select count(*) from exec_reports where created_at>now()-interval '24 hours'))>0,
    'strategy_ai_daily / board_report_weekly / exec_meeting_weekly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'cos_reviews_departments',2,'cos_execute_hourly fired and succeeded',
    jsonb_build_object('cron_ok',fn_cron_ran('cos_execute_hourly','3 hours'),
                       'runs_24h',(select count(*) from agent_runs where agent='chief_of_staff' and started_at>now()-interval '24 hours')),
    fn_cron_ran('cos_execute_hourly','3 hours'),'cos_execute_hourly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'departments_plan',3,'dept_plan_daily fired and succeeded',
    jsonb_build_object('cron_ok',fn_cron_ran('dept_plan_daily')),
    fn_cron_ran('dept_plan_daily'),'dept_plan_daily (does not always write agent_runs)'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'tasks_execute',4,'agent runs happened',
    jsonb_build_object('runs_24h',(select count(*) from agent_runs where started_at>now()-interval '24 hours'),
                       'errors_24h',(select count(*) from agent_runs where started_at>now()-interval '24 hours' and status='error')),
    (select count(*) from agent_runs where started_at>now()-interval '24 hours')>0,'all scheduled workers'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'results_measured',5,'outcomes gradeable and KPIs measurable',
    jsonb_build_object('outcomes_pending',(select count(*) from outcome_record where verdict='pending'),
                       'kpis_measurable',(select count(*) from employee_kpi where active and measure_sql is not null)),
    (select count(*) from employee_kpi where active and measure_sql is not null)>0,'outcome_evaluate_daily / kpi_review_weekly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'lessons_learned',6,'dept_learn_daily fired and succeeded',
    jsonb_build_object('cron_ok',fn_cron_ran('dept_learn_daily'),
                       'memory_rows',(select count(*) from institutional_memory)),
    fn_cron_ran('dept_learn_daily'),'dept_learn_daily (does not always write agent_runs)'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'knowledge_updated',7,'knowledge touched in the last 24h',
    jsonb_build_object('touched_24h',(select count(*) from agent_knowledge where updated_at>now()-interval '24 hours')),
    (select count(*) from agent_knowledge where updated_at>now()-interval '24 hours')>0,'kb_deepen / knowledge_curator_daily'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  insert into day_cadence (business_day, stage, stage_order, expected, observed, ok, note)
  select d,'tomorrow_planned',8,'open work exists',
    jsonb_build_object('open_tasks',(select count(*) from org_tasks where status<>'done')),
    (select count(*) from org_tasks where status<>'done')>0,'dept_plan_daily / kpi_review_weekly'
  on conflict (business_day,stage) do update set observed=excluded.observed, ok=excluded.ok, checked_at=now();

  select count(*) filter (where ok), count(*) filter (where not ok) into v_ok, v_bad
    from day_cadence where business_day=d;

  if v_bad>0 then
    insert into founder_alerts (level,event,detail,channel)
    select 'high','daily_cadence_broken',
      'The daily operating loop did not complete. Failed stages: '||
      (select string_agg(stage,', ' order by stage_order) from day_cadence where business_day=d and not ok),'email'
    where not exists (select 1 from founder_alerts where event='daily_cadence_broken' and created_at>now()-interval '20 hours');
  end if;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('day_conductor',now(),now(),case when v_bad>0 then 'error' else 'ok' end,
    jsonb_build_object('stages_ok',v_ok,'stages_failed',v_bad),
    'Daily operating rhythm: '||v_ok||' of '||(v_ok+v_bad)||' stages verified.');

  return jsonb_build_object('day',d,'ok',v_ok,'failed',v_bad);
end $fn$;

revoke execute on function public.fn_day_conductor() from public, anon, authenticated;
revoke execute on function public.fn_cron_ran(text,interval) from public, anon, authenticated;