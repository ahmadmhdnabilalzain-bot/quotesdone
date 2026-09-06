// N02 MUST NOT OVER-FIRE. A guard that refuses when the system is working is the defect this
// estate has found three times. Four arms, all on W04-S03 (declares no reviewer), each in its own
// aborted transaction:
//
//   noverdict   no review recorded at all              -> must COMPLETE
//   approved    an approved verdict                    -> must COMPLETE
//   corrected   rejected, then approved (correction)   -> must COMPLETE
//   failedge    rejected, completed with outcome fail  -> must reach state failed, not be refused
import { probe } from './probe.mjs';

const STEP = 'W04-S03', WF = 'W04';

const run = async (name, seal, outcome) => {
  const out = await probe(`do $p$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_srid bigint; v_task bigint;
        v_ref_key text; v_boid text; v_state text; v_out text;
begin
  perform set_config('app.phase_d_hold_step','${STEP}', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','n02-${name}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','n02-${name}','execution_context','test','for_workflow','${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','n02-${name}','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','${STEP}')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  select t.task_id into v_task from public.phase_c_task t
   where t.run_id=(v->>'run_id')::bigint and t.step_id='${STEP}' order by t.task_id desc limit 1;
  ${seal}
  perform set_config('app.phase_d_hold_step','', true);
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
      'outcome','${outcome}',
      'idempotency_key','n02${name}:' || v_srid,
      'inputs', jsonb_build_object('mode','${name}'),
      'output', jsonb_build_object('status','${outcome === 'pass' ? 'ok' : 'failed'}','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','${name}')),
      'requested_action','${outcome === 'pass' ? 'proceed' : 'block'}',
      'acceptance_criteria','positive control ${name}',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH — N02 positive control',
      'object_version', 1));
    select state into v_state from public.phase_c_workflow_step_run where step_run_id=v_srid;
    v_out := 'COMPLETED state=' || coalesce(v_state,'-');
  exception when others then
    v_out := 'REFUSED ' || coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE);
  end;
  raise exception 'N02<<verdict=%|%>>',
    coalesce(public.fn_phase_d_recorded_review(v_srid)->>'verdict','(none)'), v_out;
end $p$;`, 'N02');
  console.log(`${name.padEnd(11)} ${out}`);
};

const SEAL = (d) => `perform public.fn_kernel_review_decide(jsonb_build_object(
    'task_id', v_task, 'reviewer_role_id', v_rev, 'decision','${d}',
    'reason','PHASE_D_PROBE — ${d}'));`;

await run('noverdict', '', 'pass');
await run('approved', SEAL('approved'), 'pass');
await run('corrected', SEAL('rejected') + SEAL('approved'), 'pass');
await run('failedge', SEAL('rejected'), 'fail');
