-- Register the re-enabled loop-start cron (job 195, workflow_start_due) in the committed-scenario
-- cron registry. fn_phase_d_committed_scenario_guards refuses OPEN while any ACTIVE cron that reaches
-- a watched relation is unregistered; re-enabling job 195 (Tier-1 loop wiring) reaches public.org_tasks,
-- public.phase_c_workflow_run and public.phase_c_workflow_step_run (all watched), so it must be
-- registered with its quarantine reasoning, exactly as PCCR-008's re-enabled watchers were.
--
--   node scripts/apply_sql.mjs scripts/sql/register_workflow_start_due_in_scenario_registry.sql --apply --ddl

begin;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (195, 'workflow_start_due',
        'Starts a workflow_run per company_event whose event_type matches a workflow.trigger_event: writes public.phase_c_workflow_run, public.phase_c_workflow_step_run and (through the opened steps) public.org_tasks; reads public.company_event and public.workflow.',
        'Re-enabled loop-start bridge (2026-09-02, company-loop wiring). Runs in its own transaction every 15 minutes and cannot see this scenario''s uncommitted ZZ DEMO fixture rows, so it never starts a workflow ABOUT a scenario row; it is idempotent on workflow_run.idempotency_key = workflow_key:company_event.id, and close() asserts only the rows this scenario created are gone by id/marker, so its writes do not move the watermark.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

commit;
