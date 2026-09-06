-- THE REPORT PDF FUNCTION IS A COMPONENT (6 Sep 2026).
--
-- reports_are_corporate_pdfs.sql deployed the report_pdf edge function (corporate PDF renderer,
-- pdf-lib, no model) and the parity gate's "every deployed edge function in the repository is a
-- component" went red: no phase_c_component row named it. Recorded here with the same shape as its
-- siblings: invoked by the action invoker (org_action_executor report.pdf) and by os_api on a
-- founder click; owned by Data & Experimentation, whose reports it renders.
--
--   node scripts/apply_sql.mjs scripts/sql/the_report_pdf_function_is_a_component.sql --apply --ddl
begin;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
  schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id,
  workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
  activation_state, classification, gap, repair_or_keep_action, evidence, measured_at)
select
  'edge:report_pdf', 'edge_function', 'supabase/functions/report_pdf/index.ts',
  'invoked by repo/database/cron caller', 'action_invoke_dispatch (executor report.pdf), os_api report_pdf_url',
  'internal_credential_only', 'AFTER INSERT on board_reports / exec_reports / finance_reports -> fn_report_pdf_enqueue',
  true, 'service_role', 'system.task_engine', 'data_intelligence_director', 'data_intel',
  c.workflow_id, c.step_id, 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'request:slug:business_key',
  'caller_retry_with_same_key', 'deployed', 'WIRE_TO_CANONICAL', '',
  'keep; renders every report to a corporate PDF (private bucket reports), lazily on first click and on insert through the action invoker',
  'callers=2 (edge 1: os_api; db 1: fn_action_invoke_dispatch via executor report.pdf); measured 6 Sep 2026', now()
from public.phase_c_component c
where c.component_id = 'edge:uptime_check'
on conflict (component_id) do update set
  activation_state = excluded.activation_state, classification = excluded.classification,
  current_callers = excluded.current_callers, evidence = excluded.evidence, measured_at = excluded.measured_at;

do $proof$
declare v int;
begin
  select count(*) into v from public.phase_c_component where component_id = 'edge:report_pdf' and activation_state = 'deployed';
  if v <> 1 then raise exception 'edge:report_pdf is not recorded (template row edge:reporting_ai may be missing)'; end if;
  raise notice 'proof: edge:report_pdf recorded';
end $proof$;

commit;
