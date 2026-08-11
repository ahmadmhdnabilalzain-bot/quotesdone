-- SIX CRON JOBS RAN EVERY DAY AND THE MANUAL HAD NEVER HEARD OF THEM.
--
-- s38-manual-always-current measures drift in both directions: automation that runs and is not
-- documented, and documentation for automation that no longer exists. Measured on production
-- 2026-08-11: 0 ghosts, and SIX undocumented active jobs against 172 active and 183 registry rows.
--
-- FIVE OF THE SIX ARE FROM THE PREVIOUS SESSION AND ONE IS MINE. Every routine that session added
-- was created with a cron schedule and none was registered, so the company acquired five daily and
-- weekly behaviours nothing could describe. workflow_dispatch_10min is tonight's, and it is the
-- same defect - I registered the credential, the executor scope and the schedule, and not the
-- entry that tells a reader the job exists. Naming it here rather than quietly registering the
-- other five and leaving mine out.
--
-- A job that runs and is not in the registry is worse than an undocumented function: it acts on the
-- company on a schedule, and the only place its existence is written down is cron.job, which is not
-- where anybody looks. With these six the drift is 0 in both directions and the check turns MET on
-- its own evidence - nothing is weakened and nothing is backdated.

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('workflow_dispatch_10min', 'Workflow dispatcher — employee side', 'Operations',
   'Every ten minutes, hands up to two ready workflow steps to the EMPLOYEE who owns them: the step '
   || 'is claimed atomically by fn_workflow_step_claim, answered by that employee through '
   || 'agent_brain''s four-layer context, asserted against the NOT_WORK regex, then settled with '
   || 'fn_workflow_step_done so the run advances. The opposite number to workflow_step_sweep_10min, '
   || 'which handles only steps a registered edge executor can run. Refuses employee_task runs '
   || '(they follow their own org_task), the four founder gates, and any step a real executor owns. '
   || 'Capped at 24 delivered steps per UTC day; see '
   || 'scripts/sql/the_dispatcher_needed_a_daily_ceiling_before_it_needed_speed.sql for the cost '
   || 'measurement behind that number.'),

  ('employee_kpi_measure_daily', 'Employee KPI measurement', 'Intelligence',
   'Runs fn_employee_kpi_measure at 03:30 UTC: executes every employee_kpi.measure_sql, stores the '
   || 'result on the KPI as actual_value, and appends one row per KPI per UTC day to '
   || 'employee_kpi_history — a unique index on (kpi_id, measured_on) is what makes a fabricated '
   || 'performance trend impossible. 107 of 123 active KPIs carry a measure; the rest carry a '
   || 'written reason in no_measure_reason.'),

  ('dept_objective_measure_daily', 'Department objective measurement', 'Intelligence',
   'Runs fn_dept_objective_measure at 03:25 UTC, five minutes ahead of the employee KPIs so a '
   || 'department objective is scored before the individual KPIs that serve it. Executes each '
   || 'department_objective measure and records the actual against target.'),

  ('goal_decompose_weekly', 'Goal decomposition — management to departments', 'Leadership',
   'Runs fn_goal_decompose at 03:10 UTC on Mondays. Hands each MEASURABLE company goal down to the '
   || 'department that owns it as a department_objective — this is the mechanical link that makes '
   || 'the AED 1,000,000 target flow downward. A goal with no measure cannot be decomposed, which '
   || 'is why the measurable count is the ceiling on the whole chain.'),

  ('spend_concentration_weekly', 'AI spend concentration check', 'Finance',
   'Runs fn_spend_concentration_check at 03:40 UTC on Mondays. Compares 30-day model spend per OS '
   || 'against revenue and files an org_task to ai_director when the split is concentrated away '
   || 'from the OS meant to earn money. Its first run raised org_tasks 1309: 85.4% of spend to '
   || 'leadership, 0.04% to marketplace, against revenue of 0.'),

  ('delete_proposer_weekly', 'What should be deleted', 'Governance',
   'Runs fn_delete_proposer at 03:50 UTC on Mondays. Counts five classes of row that exist and '
   || 'cannot do anything — decorative goals, unmeasurable KPIs, unresolvable expectations, '
   || 'superseded identity policy, inactive employees — and opens an agent_action per class asking '
   || 'for remove, retire, or keep-with-a-reason. It NEVER deletes anything itself. A category '
   || 'answered "keep" is not asked again unless the count grows past what was accepted.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
