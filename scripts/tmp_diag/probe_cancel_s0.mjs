import { sql } from '../lib/db.mjs';
const WF = process.argv[2] || 'W02';
const q = `do $emit$
declare v_fx jsonb; v3 jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_err text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','probecancel-${WF}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','pc-${WF.toLowerCase()}','execution_context','test','for_workflow', case when '${WF}'='W12' then '${WF}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v3 := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${WF}','label','pc-${WF.toLowerCase()}',
    'business_object_id', (select w2.primary_object from public.phase_b_workflow w2 where w2.workflow_id='${WF}') || ':00000000-0000-0000-0000-000000000000',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'max_steps',0));
  v_out := v_out || 'run_state=' || coalesce((select state from public.phase_c_workflow_run where run_id=(v3->>'run_id')::bigint),'?') || chr(10);
  for r in select step_id, state from public.phase_c_workflow_step_run where run_id=(v3->>'run_id')::bigint order by step_run_id loop
    v_out := v_out || 'step ' || r.step_id || '=' || r.state || chr(10);
  end loop;
  for r in select task_id, step_id, state from public.phase_c_task where run_id=(v3->>'run_id')::bigint order by task_id loop
    v_out := v_out || 'task ' || r.step_id || '=' || r.state || chr(10);
  end loop;
  for r in select handoff_id, status from public.phase_c_handoff_run where run_id=(v3->>'run_id')::bigint order by handoff_run_id loop
    v_out := v_out || 'handoff ' || r.handoff_id || '=' || r.status || chr(10);
  end loop;
  for r in select step_id, outcome, coalesce(refusal_code,'') rc from public.phase_d_dispatch where run_id=(v3->>'run_id')::bigint order by dispatch_id loop
    v_out := v_out || 'dispatch ' || r.step_id || '=' || r.outcome || ':' || r.rc || chr(10);
  end loop;
  begin
    perform public.fn_kernel_cancel(jsonb_build_object('subject_kind','workflow_run','subject_ref',(v3->>'run_id'),'op','cancel','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH probe','actor','risk_and_governance_manager'));
    v_out := v_out || 'CANCEL OK run_state=' || coalesce((select state from public.phase_c_workflow_run where run_id=(v3->>'run_id')::bigint),'?');
  exception when others then
    v_out := v_out || 'CANCEL REFUSED ' || SQLSTATE || ' ' || left(SQLERRM, 700);
  end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { const m = String(e.message); const a = m.indexOf('PROBE<<'); console.log(a < 0 ? m.slice(0, 1500) : m.slice(a + 7, m.indexOf('>>', a)).replace(/\n/g, '\n')); }
