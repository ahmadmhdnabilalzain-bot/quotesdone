-- DOWN for scripts/sql/phase_e_wire_the_ledger_collections_and_experiments.sql (4 Sep 2026).
--
-- Nothing runs this (scripts/sql/down/README.md). It puts the four jobs back where the stand-down left
-- them: gl_sync_nightly (jobid 62) inactive with its raw command; the three new jobs unscheduled;
-- their wrapper rows and cron component rows removed; the routine component rows returned to
-- DEFERRED_RUNTIME_IMPLEMENTATION / inactive; fn_experiment_conclude dropped with its ledger row.
-- Rows the wrapped jobs wrote while active (gl_journal postings, supplier_dues reminders,
-- agent_actions experiment verdicts, pruned os_blueprint_result rows) are NOT reversed: gl_journal is
-- immutable by guard, and a down that re-inserted pruned rows would be fabricating data.
begin;

do $unwrap$
declare r record;
begin
  -- gl_sync_nightly: restore the raw command and deactivate (the wrapper row holds the original)
  perform cron.alter_job(62, command := coalesce((select original_command from public.phase_c_system_execution_wrapper where jobid = 62), 'select public.fn_gl_sync_business();'), active := false);
  delete from public.phase_c_system_execution_wrapper where jobid = 62;
  update public.phase_c_component set activation_state = 'inactive', classification = 'INACTIVE_HISTORICAL',
         accountable_role_id = 'payments_and_billing_manager', repair_or_keep_action = 'restored by the Phase E down script'
   where component_id = 'cron:gl_sync_nightly';
  for r in select jobid, jobname from cron.job where jobname in ('collections_reminders_daily', 'experiment_conclude_daily', 'blueprint_result_prune_weekly') loop
    delete from public.phase_c_system_execution_wrapper where jobid = r.jobid;
    delete from public.phase_c_component where component_id = 'cron:' || r.jobname;
    perform cron.unschedule(r.jobid);
  end loop;
end $unwrap$;

update public.phase_c_component
   set activation_state = 'inactive', classification = 'DEFERRED_RUNTIME_IMPLEMENTATION', current_callers = '',
       trace_policy_id = 'TRACE-ROLE-ACTION', repair_or_keep_action = 'restored by the Phase E down script',
       evidence = 'restored by phase_e_wire_the_ledger_collections_and_experiments_down.sql'
 where component_id in (
   'dbfn:fn_collections()',
   'dbfn:fn_experiment_results(p_key text)',
   'dbfn:fn_experiment_assign(p_key text, p_subject text)',
   'dbfn:fn_experiment_record(p_key text, p_subject text, p_event text, p_value numeric)',
   'dbfn:fn_agent_decision(p_agent text, p_kind text, p_title text, p_recommendation text, p_confidence numeric, p_evidence jsonb, p_risk text, p_detail jsonb)',
   'dbfn:fn_blueprint_result_prune()');

delete from public.phase_c_component where component_id = 'dbfn:fn_experiment_conclude(p_min_subjects integer)';
delete from public.kernel_routine_ownership where schema_name = 'public' and routine_name = 'fn_experiment_conclude';
drop function if exists public.fn_experiment_conclude(integer);

do $ctl$
begin
  if exists (select 1 from cron.job where jobname in ('collections_reminders_daily', 'experiment_conclude_daily', 'blueprint_result_prune_weekly')) then
    raise exception 'a Phase E job still exists';
  end if;
  if exists (select 1 from cron.job where jobid = 62 and active) then raise exception 'gl_sync_nightly is still active'; end if;
  if exists (select 1 from pg_proc where proname = 'fn_experiment_conclude') then raise exception 'fn_experiment_conclude still exists'; end if;
end $ctl$;

commit;
