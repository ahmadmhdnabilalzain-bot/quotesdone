import { sql } from '../phase_c/lib/db.mjs';
const WF = process.argv[2] || 'W09';
const q = `
do $emit$
declare v_fx jsonb; v3 jsonb; sr record; v_out text := ''; v_rev text; v_cands jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-fail'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'')<>'';
  select coalesce((select s.independent_reviewer_role_id from public.phase_b_workflow_step s
     where s.workflow_id='${WF}' and coalesce(btrim(s.independent_reviewer_role_id),'')<>''
     order by s.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','diagfail','execution_context','test'));
  v3 := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','diagfail',
    'business_object_id',(select primary_object from public.phase_b_workflow where workflow_id='${WF}')
                         || ':00000000-0000-0000-0000-000000000000',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    'max_steps', 0));
  v_out := 'run_state=' || coalesce((select state from public.phase_c_workflow_run
                                      where run_id=(v3->>'run_id')::bigint),'?') || chr(31)
        || 'step_runs=' || coalesce((select string_agg(step_id||':'||state,', ' order by step_run_id)
             from public.phase_c_workflow_step_run where run_id=(v3->>'run_id')::bigint),'(none)') || chr(31);
  select * into sr from public.phase_c_workflow_step_run
   where run_id=(v3->>'run_id')::bigint
     and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
   order by step_run_id limit 1;
  if not found then
    v_out := v_out || 'no_open_step=true';
  else
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', sr.step_run_id, 'actor_role_id', sr.accountable_role_id, 'outcome','fail',
        'idempotency_key','diagfail:'||sr.step_run_id,
        'inputs', jsonb_build_object('mode','failure path'),
        'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),
        'requested_action','block','acceptance_criteria','the failure path is exercised',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH — deliberate failure path',
        'object_version', 1));
      v_out := v_out || 'failed_ok step=' || (select state from public.phase_c_workflow_step_run
                                               where step_run_id=sr.step_run_id);
    exception when others then
      v_out := v_out || 'REFUSED sqlstate=' || SQLSTATE || ' msg=' || left(SQLERRM, 400);
    end;
  end if;
  raise exception 'DIAG%', v_out;
end $emit$;`;
try { await sql(q); console.error('no raise'); }
catch (err) {
  const m = String(err?.message ?? err); const i = m.indexOf('DIAG');
  let g = m.slice(i + 4).replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const c = g.indexOf('\nCONTEXT:'); if (c >= 0) g = g.slice(0, c);
  for (const l of g.split(String.fromCharCode(31))) if (l.trim()) console.log(l + '\n');
}
