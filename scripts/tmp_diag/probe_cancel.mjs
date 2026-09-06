import { sql } from '../phase_b/lib/db.mjs';
const wf = process.argv[2] || 'W01';
const q = `do $emit$
declare v4 jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_res jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','cx-${wf}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','cx-${wf.toLowerCase()}','execution_context','test','for_workflow', case when '${wf}'='W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v4 := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','cx-${wf.toLowerCase()}','execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_first_open_step', true));
  v_out := 'run='||(v4->>'run_id')||' state_before='||(select state from public.phase_c_workflow_run where run_id=(v4->>'run_id')::bigint)||'~';
  v_res := public.fn_kernel_cancel(jsonb_build_object('subject_kind','workflow_run','subject_ref',(v4->>'run_id'),'op','cancel','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - probe','actor','risk_and_governance_manager'));
  v_out := v_out || 'ret='||left(v_res::text,300)||'~state_after='||coalesce((select state from public.phase_c_workflow_run where run_id=(v4->>'run_id')::bigint),'(gone)')
     ||'~steprun_states='||coalesce((select string_agg(step_id||':'||state,';' order by step_run_id) from public.phase_c_workflow_step_run where run_id=(v4->>'run_id')::bigint),'-');
  raise exception 'CX<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('CX<<'); console.log(a<0 ? 'ERR:'+m.slice(0,600) : m.slice(a+4, m.indexOf('>>',a))); }
