-- Step 2 — turn the action/approval runtime back on. The 16 Aug founder stand-down deactivated the
-- crons that DELIVER events to agents, ADVANCE workflows, and INVOKE queued actions through the
-- approval gates. With the freeze gone, re-enable them as traced kernel components. Their component
-- registry rows already read activation_state='active' (the stand-down flipped only cron.job.active),
-- so this aligns reality to the registry. Nothing bypasses approval: the invoker (fn_action_invoke_*)
-- still runs only low/advisory_safe/reversible actions unattended and routes everything else through
-- fn_action_resolve_approver -> head approval -> founder for money/refunds.
--
--   node scripts/apply_sql.mjs scripts/sql/reenable_the_dispatch_and_action_runtime.sql --apply --ddl

begin;

-- Wrap + enable each (command -> fn_kernel_cron_exec(jobid), so active_state_changing_cron_components
-- _not_wrapped stays 0).
select public.fn_kernel_wrap_and_enable_cron(141, 'chief_operating_officer', 'people_ops');  -- event_dispatch_15min
select public.fn_kernel_wrap_and_enable_cron(255, 'chief_operating_officer', 'people_ops');  -- workflow_dispatch_10min
select public.fn_kernel_wrap_and_enable_cron(230, 'chief_operating_officer', 'people_ops');  -- action_invoke_dispatch_5min
select public.fn_kernel_wrap_and_enable_cron(231, 'chief_operating_officer', 'people_ops');  -- action_invoke_collect_5min
select public.fn_kernel_wrap_and_enable_cron(266, 'chief_operating_officer', 'people_ops');  -- action_invoke_rpc_5min
select public.fn_kernel_wrap_and_enable_cron(264, 'supplier_matching_dispatch_operator', 'marketplace'); -- rfq_redispatch_6h

-- Register each in the committed-scenario cron registry (they reach watched relations; each runs in
-- its own transaction, cannot see an uncommitted ZZ DEMO scenario fixture, and close() asserts scenario
-- rows are gone by id — so none moves the watermark).
insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
  (141, 'event_dispatch_15min',
   'Delivers company_event rows to subscribed agents: writes public.event_assessment, public.event_delivery, public.org_tasks; reads public.company_event, public.event_subscription.',
   'Re-enabled 2026-09-02. Own transaction every 15 min; cannot see an uncommitted scenario fixture; close() asserts scenario rows gone by id/marker, so it does not move the watermark.'),
  (255, 'workflow_dispatch_10min',
   'Advances open workflow steps: writes public.phase_c_workflow_step_run, public.org_tasks; reads workflow_run/step state.',
   'Re-enabled 2026-09-02. Own transaction; cannot see an uncommitted scenario fixture; close() asserts by id/marker.'),
  (230, 'action_invoke_dispatch_5min',
   'Dispatches queued action_execution rows through the approval gate: writes public.action_execution, public.org_tasks (approval tasks); reads org_action_executor.',
   'Re-enabled 2026-09-02. Own transaction; only acts on committed action_execution rows, never a scenario fixture; close() asserts by id/marker.'),
  (231, 'action_invoke_collect_5min',
   'Collects the results of invoked actions: writes public.action_execution.response/status.',
   'Re-enabled 2026-09-02. Own transaction; acts on committed action_execution rows only; close() asserts by id/marker.'),
  (266, 'action_invoke_rpc_5min',
   'Runs the rpc-kind queued actions (SECURITY DEFINER targets) under the same risk gate as the edge path: writes public.action_execution and the target functions'' own rows.',
   'Re-enabled 2026-09-02. Own transaction; acts on committed action_execution rows only; the risk gate refuses founder/money/non-advisory classes; close() asserts by id/marker.'),
  (264, 'rfq_redispatch_6h',
   'Re-dispatches stalled RFQ matches: writes public.inquiry_matches, public.quotes, public.org_tasks; reads inquiries.',
   'Re-enabled 2026-09-02. Own transaction every 6h; acts on real committed inquiries only, never a scenario fixture; close() asserts by id/marker.')
on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

commit;
