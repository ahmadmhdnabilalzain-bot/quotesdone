-- Register the 21 re-enabled failure/state-management crons in the committed-scenario cron
-- registry. fn_phase_d_committed_scenario_guards refuses to OPEN a scenario while any ACTIVE cron
-- that reaches a watched relation is unregistered (so its concurrent writes are accounted for). The
-- 21 watchers/sweeps re-enabled on 2 Sep reach watched relations and were unregistered, reddening
-- kernel_positive_controls (fn_phase_d_committed_scenario_open). Each writes its OWN agent_runs
-- run-log and any alerts/tasks/events about the REAL estate; it runs in a separate transaction and
-- cannot see this scenario's uncommitted ZZ DEMO fixture, so it never writes about a scenario row.
-- close() asserts only the rows THIS scenario created are gone (by id/marker), so these concurrent
-- writes do not move the scenario watermark. Validated by re-running the open/close probe after.
--
--   node scripts/apply_sql.mjs scripts/sql/register_reenabled_crons_in_scenario_registry.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (217, 'action_queue_sweep_hourly', 'Writes public.founder_alerts', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (112, 'agent_silence_watch_daily', 'Writes public.agent_runs, public.founder_alerts, public.notifications', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (90, 'backup_watch_daily', 'Writes public.agent_runs, public.founder_alerts, public.notifications, public.quotes', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (182, 'dead_letter_drain_held', 'Writes public.notifications', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (171, 'edge_health_scan_15min', 'Writes public.agent_runs, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (99, 'email_cron_2min', 'Writes public.notifications', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (190, 'emit_metric_alerts', 'Writes public.company_event', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (206, 'emit_task_assigned', 'Writes public.company_event, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (191, 'event_consolidate', 'Writes public.agent_runs, public.company_event, public.event_assessment, public.event_delivery, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (56, 'exception_alerts_hourly', 'Writes public.founder_alerts, public.notifications, public.quotes', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (289, 'handoff_watchdog_6h', 'Writes public.agent_runs, public.founder_alerts', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (279, 'incident_watchdog_hourly', 'Writes public.agent_runs', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (25, 'ops_watch_hourly', 'Writes public.agent_runs, public.inquiries, public.notifications, public.quotes', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (262, 'org_task_assign_hourly', 'Writes public.agent_runs, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (286, 'org_task_sla_watch_daily', 'Writes public.agent_runs, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (281, 'remediation_escalate_consume_daily', 'Writes public.agent_runs, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (248, 'runner_silence_watch_daily', 'Writes public.agent_runs, public.founder_alerts, public.notifications', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (101, 'sla_watch_hourly', 'Writes public.founder_alerts, public.inquiries, public.notifications, public.quotes', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (183, 'task_approve_hourly', 'Writes public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (137, 'watch_failed_runs_hourly', 'Writes public.agent_runs', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (247, 'workflow_step_sweep_10min', 'Writes public.agent_runs, public.org_tasks', 'Re-enabled failure/state watcher (2 Sep 2026, PCCR-008). Writes its own agent_runs run-log and any alerts/tasks/events about the real estate; runs in a separate transaction and cannot see this scenario''s uncommitted ZZ DEMO fixture, so never writes about a scenario row. close() asserts only the rows this scenario created are gone by id/marker, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

commit;
