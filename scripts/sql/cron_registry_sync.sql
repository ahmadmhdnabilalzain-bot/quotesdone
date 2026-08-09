-- The operating manual, made current with what actually runs.
--
-- Section 38 measures DRIFT IN BOTH DIRECTIONS, because one number would hide the other:
-- automation that runs and is not documented, and documentation for automation that no longer
-- exists. Production had 28 of the first and 2 of the second.
--
-- Every purpose below is read off the job's own command, not invented. Where a job posts to an
-- edge function the purpose names the function; where it calls a routine it names the routine.
--
--   node scripts/apply_sql.mjs scripts/sql/cron_registry_sync.sql --ddl --promote
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('ai_spend_guard_hourly','AI Spend Guard','AI cost','fn_ai_spend_guard() — holds AI spending inside the department budgets each hour.'),
  ('control_mode_sweep_5min','Control Mode Sweep','Security','fn_control_mode_sweep() — expires Control Mode sessions that were opened and never closed.'),
  ('cost_snapshot_balance_daily','Cost Snapshot & Balance','Finance','Posts to the cost snapshot edge function daily to record the running cost and cash balance.'),
  ('dead_letter_drain_held','Dead Letter Drain','Messaging','fn_notifications_dead_letter_held(30) — retries notifications held in the dead-letter queue.'),
  ('edge_health_scan_15min','Edge Health Scan','Technology','fn_edge_health_scan() — probes every edge function every 15 minutes and records the verdict.'),
  ('emit_metric_alerts','Metric Alert Emitter','Data','fn_emit_metric_alerts() — raises an event when a tracked metric crosses its threshold.'),
  ('emit_task_assigned','Task Assignment Emitter','Operations','fn_emit_task_assigned(60) — emits a task.assigned event for work assigned in the last hour.'),
  ('event_consolidate','Event Consolidation','Data','fn_event_consolidate() — rolls the raw event stream up into the event rollup.'),
  ('execution_run_hourly','Execution Run','Operations','fn_execution_run() — advances workflow executions that are due.'),
  ('execution_sweep_hourly','Execution Sweep','Operations','fn_execution_sweep() — clears executions that finished or stalled.'),
  ('improvement_handover_hourly','Improvement Handover','Evolution','fn_improvement_handover() — hands finished improvement work to the next owner.'),
  ('improvement_plan_daily','Improvement Plan Refresh','Evolution','fn_improvement_plan_refresh() — rebuilds each employee''s improvement plan daily.'),
  ('knowledge_exam_loop','Knowledge Exam Loop','Knowledge','Posts to the exam edge function every 4 hours: writes questions, grades answers, auto-fills verified gaps.'),
  ('lead_lifecycle_refresh_daily','Lead Lifecycle Refresh','Supplier growth','fn_refresh_lead_lifecycle() — recomputes where every supplier lead sits in its lifecycle.'),
  ('learning_loop_sweep_hourly','Learning Loop Sweep','Knowledge','fn_learning_loop_sweep() — moves learning items through the loop and closes finished ones.'),
  ('memory_promotion_weekly','Memory Promotion','Knowledge','fn_promote_memory_sweep() — promotes durable agent memories into institutional memory.'),
  ('model_autoswitch_daily','Model Autoswitch','AI cost','fn_model_autoswitch() — moves task classes onto the cheapest model that still meets quality.'),
  ('model_benchmark_daily','Model Benchmark','AI cost','fn_model_benchmark() — benchmarks the routed models on quality, latency and cost.'),
  ('os_health_brief_weekly','OS Health Brief','Governance','fn_os_health_brief() — scores each Operating System and refreshes resource pressure.'),
  ('os_objective_measure_daily','OS Objective Measure','Leadership','fn_os_objective_measure() — measures each operating-system objective against its measure_sql.'),
  ('seo_gen_weekly','SEO Generation','Marketing','Posts to the SEO edge function weekly to generate and refresh search content.'),
  ('supplier_registration_state_resync_daily','Supplier Registration Resync','Supplier growth','fn_resync_supplier_registration_state() — realigns registration state with what actually happened.'),
  ('supplier_risk_complaints','Supplier Risk — Complaints','Marketplace','fn_supplier_risk_monitor(''complaints'') — raises a risk item when supplier complaints cluster.'),
  ('supplier_risk_performance_drops','Supplier Risk — Performance Drops','Marketplace','fn_supplier_risk_monitor(''performance_drops'') — raises a risk item when supplier performance falls.'),
  ('supplier_risk_response_delays','Supplier Risk — Response Delays','Marketplace','fn_supplier_risk_monitor(''response_delays'') — raises a risk item when suppliers stop replying in time.'),
  ('supplier_score_refresh_daily','Supplier Score Refresh','Marketplace','fn_supplier_score_refresh() — recomputes every supplier''s capability and reliability score.'),
  ('task_approve_hourly','Task Auto-Approve','Operations','fn_task_approve() — approves tasks that sit inside the authority the org model already grants.'),
  ('workflow_start_due','Workflow Starter','Operations','fn_workflow_start_due(1440) — starts workflows whose trigger fell due in the last day.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

-- THE OTHER DIRECTION. Two rows document automation that no longer exists, so the manual is
-- telling the founder about jobs that cannot run. Documentation for a removed job is not history
-- worth keeping — the job's own record lives in cron.job_run_details — so the stale rows go.
delete from public.cron_registry r
 where not exists (select 1 from cron.job j where j.jobname = r.jobname);
