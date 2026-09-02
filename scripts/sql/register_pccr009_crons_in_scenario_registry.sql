-- Register the 3 PCCR-009 re-enabled crons in the committed-scenario cron registry.
-- fn_phase_d_committed_scenario_guards refuses to OPEN a scenario while any active cron that reaches
-- a watched relation is unregistered. resilience_watch/legal_ai/employee_kpi_assign (PCCR-009) reach
-- watched relations and were unregistered, reddening kernel_positive_controls. Each writes its own
-- run-log / KPI / legal rows about the REAL estate; it runs in a separate transaction and cannot see
-- a scenario's uncommitted fixture, and close() asserts scenario rows by id -- so these writes do not
-- move the watermark. Validated by re-running the open/close probe after.
--
--   node scripts/apply_sql.mjs scripts/sql/register_pccr009_crons_in_scenario_registry.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (290, 'employee_kpi_assign_daily', 'Writes public.agent_runs', 'PCCR-009 re-enabled monitor (2 Sep 2026). Writes its own run-log / KPI / legal rows about the real estate; runs in a separate transaction and cannot see a scenario''s uncommitted fixture. close() asserts scenario rows by id, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (76, 'legal_ai_daily', 'Writes public.customers, public.documents', 'PCCR-009 re-enabled monitor (2 Sep 2026). Writes its own run-log / KPI / legal rows about the real estate; runs in a separate transaction and cannot see a scenario''s uncommitted fixture. close() asserts scenario rows by id, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (123, 'resilience_watch_10min', 'Writes public.agent_runs, public.inquiries, public.inquiry_matches, public.notifications, public.quotes', 'PCCR-009 re-enabled monitor (2 Sep 2026). Writes its own run-log / KPI / legal rows about the real estate; runs in a separate transaction and cannot see a scenario''s uncommitted fixture. close() asserts scenario rows by id, so these writes do not move the watermark.')
on conflict (jobid) do nothing;

commit;
