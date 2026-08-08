-- Restores the KPI engine's stated schedules after kpi_schedule_prove.sql has produced a real
-- succeeded run for each. Weekly Monday 04:00 for the KPI review, daily 02:20 for the plan refresh.
do $$
declare j bigint;
begin
  select jobid into j from cron.job where jobname = 'kpi_review_weekly';
  if j is not null then perform cron.alter_job(j, schedule => '0 4 * * 1'); end if;

  select jobid into j from cron.job where jobname = 'improvement_plan_daily';
  if j is not null then perform cron.alter_job(j, schedule => '20 2 * * *'); end if;
end $$;
