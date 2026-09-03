-- THE LEGACY SHARED SECRET IS RETIRED, THE PARALLEL TASK EXECUTOR STOPS, TWO DEAD WORKFLOWS PRUNED (3 Sep 2026).
--
-- MASTER_PLAN 5.3 / §4.3 / A5, each measured before the change:
--
-- 1. internal_credential id 1 (legacy.shared, scope ai_gateway/postiz_publish/knowledge_exam) is
--    the shared secret every caller used before scoped credentials existed. Its last ALLOWED use was
--    13 Aug 2026; in the last 30 days it was accepted 10 times (all before 13 Aug) and REFUSED 5,978
--    times (5,977 at kb_embed, the last on 31 Aug; 1 at refunds_api on 2 Sep, a probe). Nothing
--    active presents it any more. It is retired through fn_internal_credential_retire, so a caller
--    that still carries it is refused as unknown_credential and lands in the audit table.
--
-- 2. cron 124 cos_execute_hourly drained org_tasks in parallel with the kernel. In the last 7 days it
--    ran 9 times: 8 skipped (model held), 1 error, 0 tasks worked — while the kernel's employee_task
--    spine (trigger task.assigned, 286 events) closed 81 tasks. One spine, as the plan says: the tick
--    is deactivated (cron.alter_job) and its component recorded INTENTIONALLY_INACTIVE. The
--    cos_execute edge function stays: it is the bound executor of every workflow's `coordinate` step.
--
-- 3. Of the 11 active workflows whose trigger has never fired, 8 have a live emitter (a trigger or a
--    routine that calls fn_emit) and simply await a first occurrence — rfq.created, refund.requested,
--    customer.complaint, supplier.suspension_proposed, budget.exceeded, campaign.published,
--    invoice.received, goal.retired. Three had no emitter anywhere: deploy.completed (wired today in
--    scripts/deploy_functions.mjs), lead.qualified (there is no customer-lead pipeline; `leads` are
--    suppliers) and contract.submitted (no contract intake path). The last two are deactivated with
--    the reason on the row; they come back with their emitter.
--
--   node scripts/apply_sql.mjs scripts/sql/retire_the_legacy_credential_and_the_parallel_task_executor.sql --apply --ddl
begin;
set local app.change_reason = 'MASTER_PLAN 5.3/4.3/A5, 3 Sep 2026: legacy credential retired; parallel task executor stopped; two emitter-less workflows pruned';

-- 1. the legacy shared secret
do $c$ begin
  if exists (select 1 from public.internal_credential where id = 1 and active) then
    perform public.fn_internal_credential_retire(1,
      'MASTER_PLAN 5.3, 3 Sep 2026: the pre-scoped shared secret. Last allowed use 13 Aug 2026; 5,978 refusals since (kb_embed out_of_scope, last 31 Aug). Every live caller holds a scoped credential.');
  end if;
end $c$;

-- 2. the parallel org_task executor
do $c$ begin
  if exists (select 1 from cron.job where jobid = 124 and active) then
    perform cron.alter_job(124, active := false);
  end if;
end $c$;
update public.phase_c_component
   set activation_state = 'inactive', classification = 'INTENTIONALLY_INACTIVE',
       repair_or_keep_action = 'deactivated 3 Sep 2026 (MASTER_PLAN 4.3): the kernel''s employee_task spine works org_tasks (81 closed in 7 days); this hourly drain worked 0 in the same window (8 skipped on the hold, 1 error). One spine. The cos_execute edge function stays as the coordinate-step executor.',
       evidence = 'measured 3 Sep 2026: agent_runs cos_execute last 7d = 8 skipped + 1 error, 0 worked; workflow_run employee_task last 7d = 6 done / 43 running / 4 failed; org_tasks done last 7d = 81; cron.alter_job(124, active := false)'
 where component_id = 'cron:cos_execute_hourly';

-- 3. the two workflows with no emitter
update public.workflow
   set active = false,
       description = coalesce(description, '') || ' [RETIRED 3 Sep 2026 (MASTER_PLAN A5): no routine, trigger or function emits ' || trigger_event || '; reactivate with the emitter]'
 where workflow_key in ('lead_to_customer', 'contract_review') and active;

-- PROOF
do $proof$
declare v_cred record; v_cron boolean; v_comp record; v_wf int; v_reg int;
begin
  select active, retired_at into v_cred from public.internal_credential where id = 1;
  select active into v_cron from cron.job where jobid = 124;
  select activation_state, classification into v_comp from public.phase_c_component where component_id = 'cron:cos_execute_hourly';
  select count(*) into v_wf from public.workflow where workflow_key in ('lead_to_customer', 'contract_review') and active;
  select count(*) into v_reg from cron.job j where j.active and not exists (select 1 from public.cron_registry r where r.jobname = j.jobname);
  if v_cred.active or v_cred.retired_at is null then raise exception 'legacy credential still active'; end if;
  if v_cron then raise exception 'cron 124 still active'; end if;
  if v_comp.activation_state <> 'inactive' or v_comp.classification <> 'INTENTIONALLY_INACTIVE' then raise exception 'component not recorded inactive: % / %', v_comp.activation_state, v_comp.classification; end if;
  if v_wf > 0 then raise exception '% emitter-less workflows still active', v_wf; end if;
  if v_reg > 0 then raise exception '% active cron jobs undocumented in cron_registry', v_reg; end if;
  raise notice 'proof: legacy credential retired, cron 124 inactive and recorded, 2 workflows pruned, cron_registry complete';
end $proof$;
commit;
