-- "Platform availability 80%" was wrong and it mattered: it was averaging two different
-- things. Over 7 days, check_kind 'http' is 100.0% across 672 checks. check_kind
-- 'agent_runs' is 0.0% across 168 - because that watchdog writes ok=false whenever ANY
-- agent errored in the window, so it can never read anything but zero. Averaging a real
-- uptime probe with a structurally-zero meta-check produced a fictional 80%.
--
-- Availability now measures availability. Agent reliability gets its own honest metric.

update employee_kpi
   set measure_sql = $q$select round(100.0*count(*) filter (where ok)/nullif(count(*),0),2) from health_checks where check_kind='http' and created_at > now()-interval '7 days'$q$
 where metric = 'Platform availability' and active;

insert into employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active)
select 'it','Agent run reliability','Scheduled agent runs completing without error', 97::numeric,'percent','weekly','customer_satisfaction',
  $q$select round(100.0*count(*) filter (where status<>'error')/nullif(count(*),0),2) from agent_runs where started_at > now()-interval '7 days'$q$, true
where not exists (select 1 from employee_kpi where kpi='Agent run reliability');

-- the miscalibrated watchdog is itself work
insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
select 'it','Recalibrate the agent_runs health watchdog',
 'health_checks.check_kind=''agent_runs'' has written ok=false on 168 of 168 rows over 7 days because it flags the whole window whenever any single agent errors. It cannot report anything but 0%, so it carried the platform availability KPI down to a fictional 80% while real HTTP availability was 100%. Give it a threshold (for example: not-ok only when the error rate exceeds 5% of runs in the window) so it produces signal instead of a constant.',
 'proposed','advisory', false, 'incident_fix'
where not exists (select 1 from org_tasks where title='Recalibrate the agent_runs health watchdog' and status<>'done');