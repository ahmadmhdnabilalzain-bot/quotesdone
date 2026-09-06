import { sql } from '../phase_b/lib/db.mjs';
const wf = process.argv[2] || 'W01';
const q = `do $emit$
declare v jsonb; v4 jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_res jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','cy-${wf}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','cy-${wf.toLowerCase()}','execution_context','test','for_workflow', case when '${wf}'='W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  -- arm 1: failure
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','cyf-${wf.toLowerCase()}','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_first_open_step', true));
  perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',(v->>'held_step_run_id')::bigint,
    'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=(v->>'held_step_run_id')::bigint),
    'outcome','fail','idempotency_key','cyf:'||(v->>'held_step_run_id'),'inputs', jsonb_build_object('mode','failure path'),
    'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH'),
    'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),'requested_action','block',
    'acceptance_criteria','x','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH probe','object_version',1));
  v_out := 'run1='||(v->>'run_id')||' cmd1='||coalesce((select command_id::text from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'-')
    ||' cmdstate='||coalesce((select state from public.founder_command where command_id=(select command_id from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint)),'-')||'~';
  -- arm 2: cancellation
  v4 := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','cyc-${wf.toLowerCase()}','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_first_open_step', true));
  v_out := v_out||'run2='||(v4->>'run_id')||' cmd2='||coalesce((select command_id::text from public.phase_c_workflow_run where run_id=(v4->>'run_id')::bigint),'-')||' before='||(select state from public.phase_c_workflow_run where run_id=(v4->>'run_id')::bigint)||'~';
  v_res := public.fn_kernel_cancel(jsonb_build_object('subject_kind','workflow_run','subject_ref',(v4->>'run_id'),'op','cancel','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - probe','actor','risk_and_governance_manager'));
  v_out := v_out||'ret='||left(v_res::text,260)||'~after='||(select state from public.phase_c_workflow_run where run_id=(v4->>'run_id')::bigint);
  raise exception 'CY<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('CY<<'); console.log(a<0 ? 'ERR:'+m.slice(0,600) : m.slice(a+4, m.indexOf('>>',a))); }
