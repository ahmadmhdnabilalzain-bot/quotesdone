// DOES A RECORDED `rejected` VERDICT STOP A STEP THAT DECLARES NO REVIEWER?
//
// The handler asks for an APPROVED verdict only when the frozen step row names an independent
// reviewer -- 28 of 257. On the other 229 nothing reads the verdict at all, so a reviewer who
// rejected the work is recorded and then ignored. This drives the claim rather than asserting it:
// hold the step open, seal a REJECTED verdict on its task through the kernel's own door, release
// the hold, and ask the handler to complete the step on its pass edge.
//
// Everything runs inside one transaction that ends in `raise exception`, so nothing survives.
import { probe } from './probe.mjs';

const STEP = process.argv[2] || 'W04-S03';
const WF = STEP.slice(0, 3);

const body = `do $p$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_srid bigint; v_task bigint;
        v_out text := ''; v_dec jsonb; v_state text; v_eff_before bigint; v_eff_after bigint;
        v_ref_key text; v_boid text; v_declared text;
begin
  perform set_config('app.phase_d_hold_step','${STEP}', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','revgap-${STEP.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','revgap-${STEP.toLowerCase()}','execution_context','test','for_workflow','${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;

  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','revgap-${STEP.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    'hold_at_step_id','${STEP}')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  if v_srid is null then
    raise exception 'REVGAP<<no_open_step for ${STEP}: %>>', coalesce(v->'stopped'->>'refused_with','-');
  end if;

  select nullif(btrim(coalesce(independent_reviewer_role_id,'')),'') into v_declared
    from public.phase_b_workflow_step where step_id='${STEP}';

  select t.task_id into v_task from public.phase_c_task t
   where t.run_id=(v->>'run_id')::bigint and t.step_id='${STEP}' order by t.task_id desc limit 1;
  if v_task is null then
    raise exception 'REVGAP<<no task opened for ${STEP}; declared_reviewer=%>>', coalesce(v_declared,'(none)');
  end if;

  -- Seal a REJECTED verdict through the canonical door. An independent reviewer, so the
  -- independence check cannot be what answers.
  v_dec := public.fn_kernel_review_decide(jsonb_build_object(
    'task_id', v_task, 'reviewer_role_id', v_rev, 'decision','rejected',
    'reason','PHASE_D_PROBE — the reviewer rejected this output'));
  v_out := 'declared_reviewer=' || coalesce(v_declared,'(none)')
        || ' | review_decide.ok=' || coalesce(v_dec->>'ok','-')
        || ' | review_decide.error=' || coalesce(v_dec->>'error','-')
        || ' | recorded_verdict=' || coalesce(public.fn_phase_d_recorded_review(v_srid)->>'verdict','(none)');

  -- Release the hold and ask for the pass edge.
  perform set_config('app.phase_d_hold_step','', true);
  select count(*) into v_eff_before from public.phase_d_effect_ledger;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
      'outcome','pass',
      'idempotency_key','revgap:${STEP}:' || v_srid,
      'inputs', jsonb_build_object('mode','pass after a recorded rejection'),
      'output', jsonb_build_object('status','ok','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','pass')),
      'requested_action','proceed',
      'acceptance_criteria','a rejected verdict must stop this',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH — probe',
      'object_version', 1));
    select count(*) into v_eff_after from public.phase_d_effect_ledger;
    select state into v_state from public.phase_c_workflow_step_run where step_run_id=v_srid;
    v_out := v_out || ' || COMPLETED state=' || coalesce(v_state,'-')
          || ' effects_added=' || (v_eff_after - v_eff_before)::text;
  exception when others then
    v_out := v_out || ' || REFUSED ' ||
      coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE)
      || ' :: ' || left(SQLERRM, 220);
  end;
  raise exception 'REVGAP<<%>>', v_out;
end $p$;`;

console.log(await probe(body, 'REVGAP'));
