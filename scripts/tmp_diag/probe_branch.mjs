import { sql } from '../phase_b/lib/db.mjs';
const wf = process.argv[2] || 'W18', step = process.argv[3] || 'W18-S05';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; v_state text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','br-${wf}'));
  perform set_config('app.phase_d_hold_step','${step}', true);
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','br-${wf.toLowerCase()}','execution_context','test','for_workflow', case when '${wf}'='W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','br-${wf.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','${step}'));
  v_out := 'held='||coalesce(v->>'held_step_id','(none)')||' srid='||coalesce(v->>'held_step_run_id','-');
  if (v->>'held_step_run_id') is not null then
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',(v->>'held_step_run_id')::bigint,
      'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=(v->>'held_step_run_id')::bigint),
      'outcome','fail','idempotency_key','br:'||(v->>'held_step_run_id'),'inputs',jsonb_build_object('mode','failure path'),
      'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),'requested_action','block',
      'acceptance_criteria','the failure path is exercised','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH probe','object_version',1));
    v_out := v_out||' step='||(select state from public.phase_c_workflow_step_run where step_run_id=(v->>'held_step_run_id')::bigint)
      ||' run='||(select state from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint)
      ||' declared='||(select failure_workflow_state from public.phase_b_workflow_step where step_id='${step}');
  end if;
  v_out := v_out||' refusals='||coalesce((select string_agg(step_id||'='||coalesce(nullif(refusal_code,''),outcome),';' order by dispatch_id) from public.phase_d_dispatch where run_id=(v->>'run_id')::bigint),'-');
  raise exception 'BR<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('BR<<'); console.log(a<0 ? 'ERR:'+m.slice(0,600).replace(/\s+/g,' ') : m.slice(a+4, m.indexOf('>>',a))); }
