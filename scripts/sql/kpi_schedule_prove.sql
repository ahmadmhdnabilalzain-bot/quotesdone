-- comp-11-schedule: the KPI engine's two jobs are ACTIVE but neither had ever completed a run.
-- kpi_review_weekly died once on a statement timeout (employee_kpi #71's measure_sql selected FROM
-- fn_kpi_scoreboard(), so the scoreboard recursed until it was cancelled — that row is now retired
-- and the scoreboard returns 94 rows in 0.67s), and improvement_plan_daily was created after its
-- 02:20 slot had passed, so it had no run at all.
--
-- A job row is a claim; only cron.job_run_details makes it a fact. This accelerates both jobs to
-- every-minute so pg_cron itself executes them, and kpi_schedule_restore.sql puts the stated
-- schedules back. Name-guarded so it is a no-op on any project that does not carry these jobs.
do $$
declare j bigint;
begin
  select jobid into j from cron.job where jobname = 'kpi_review_weekly';
  if j is not null then perform cron.alter_job(j, schedule => '* * * * *'); end if;

  select jobid into j from cron.job where jobname = 'improvement_plan_daily';
  if j is not null then perform cron.alter_job(j, schedule => '* * * * *'); end if;
end $$;
