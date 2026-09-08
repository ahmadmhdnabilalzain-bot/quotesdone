import { sql } from '../lib/db.mjs';
const WFS = process.argv[2]
  ? process.argv[2].split(',')
  : (await sql('select workflow_id from public.phase_b_workflow order by workflow_id')).map(r => r.workflow_id);

for (const wf of WFS) {
  const q = `do $emit$
declare v jsonb; v4 jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text:=''; sr record; v_state text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','hold-${wf}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','hd-${wf.toLowerCase()}','execution_context','test',
    'for_workflow', case when '${wf}'='W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;

  -- FAILURE: hold at the first open step, then fail it.
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','hdf-${wf.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    'hold_at_first_open_step', true));
  v_out := 'held=' || coalesce(v->>'held_step_id','(none)') || '~';
  if (v->>'held_step_run_id') is not null then
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', (v->>'held_step_run_id')::bigint,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=(v->>'held_step_run_id')::bigint),
        'outcome','fail','idempotency_key','hdf-${wf.toLowerCase()}:fail:'||(v->>'held_step_run_id'),
        'inputs', jsonb_build_object('mode','failure path'),
        'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - deliberate failure path'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),
        'requested_action','block','acceptance_criteria','the failure path is exercised',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the Phase D failure path, driven deliberately inside a transaction that is aborted',
        'object_version', 1));
      select state into v_state from public.phase_c_workflow_step_run where step_run_id=(v->>'held_step_run_id')::bigint;
      v_out := v_out || 'failure=step:'||coalesce(v_state,'(null)')||',run:'||coalesce((select state from public.phase_c_workflow_run where run_id=(v->>'run_id')::bigint),'?')||'~';
    exception when others then
      v_out := v_out || 'failure=REFUSED:'||coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE)||':'||left(SQLERRM,120)||'~';
    end;
  else
    v_out := v_out || 'failure=NO_HELD_STEP stopped='||coalesce(v->'stopped'->>'refused_with','-')||':'||coalesce(left(v->'stopped'->>'reason',100),'')||'~';
  end if;

  -- CANCELLATION: its own run, also held.
  v4 := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${wf}','label','hdc-${wf.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    'hold_at_first_open_step', true));
  begin
    perform public.fn_kernel_cancel(jsonb_build_object('subject_kind','workflow_run','subject_ref',(v4->>'run_id'),
      'op','cancel','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D cancellation path, inside a transaction that is aborted',
      'actor','risk_and_governance_manager'));
    select state into v_state from public.phase_c_workflow_run where run_id=(v4->>'run_id')::bigint;
    v_out := v_out || 'cancellation='||coalesce(v_state,'(null)')||'~';
  exception when others then
    v_out := v_out || 'cancellation=REFUSED:'||coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE)||':'||left(SQLERRM,140)||'~';
  end;
  v_out := v_out || 'cheld='||coalesce(v4->>'held_step_id','(none)');
  raise exception 'HOLD<<%>>', v_out;
end $emit$;`;
  let out;
  try { await sql(q); out = '(no marker)'; }
  catch (e) { const m = String(e.message); const a = m.indexOf('HOLD<<'); out = a < 0 ? 'ERR:' + m.slice(0, 400).replace(/\s+/g, ' ') : m.slice(a + 6, m.indexOf('>>', a)); }
  console.log(wf.padEnd(4), out);
}
