import { sql } from '../lib/db.mjs';
const STEP = process.argv[2] || 'W03-S02';
const WF = STEP.slice(0,3);
const q = `do $p$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_run bigint; v_srid bigint; v_out text := '';
        v_full jsonb; v_actor text; ins public.phase_d_handler_schema%rowtype; v_k text;
        v_e0 bigint; v_e1 bigint;
begin
  perform set_config('app.phase_d_hold_step','${STEP}', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-case'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-case','execution_context','test','for_workflow','${WF}'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','dbg-case','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager','reviewer_candidates',v_cands,
    'hold_at_step_id','${STEP}'));
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  perform set_config('app.phase_d_hold_step','', true);
  v_out := 'held=' || coalesce(v_srid::text,'NULL');
  if v_srid is null then raise exception 'DBG<<%>>', v_out; end if;
  select accountable_role_id into v_actor from public.phase_c_workflow_step_run where step_run_id=v_srid;
  v_full := (public.fn_phase_d_step_inputs(v_srid))->'inputs';
  select * into ins from public.phase_d_handler_schema where step_id='${STEP}' and schema_kind='input';
  select count(*) into v_e0 from public.phase_d_effect_ledger;

  -- wrong actor, full payload
  begin
    perform public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id','zz_not_a_canonical_role',
      'idempotency_key','dbg-actor', 'inputs', v_full, 'execution_context','production'));
    v_out := v_out || ' | wrong_actor=ACCEPTED';
  exception when others then v_out := v_out || ' | wrong_actor=' || coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1],left(SQLERRM,90)); end;

  -- missing one declared input key
  v_k := ins.required_keys[1];
  begin
    perform public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor,
      'idempotency_key','dbg-missing', 'inputs', v_full - v_k, 'execution_context','production'));
    v_out := v_out || ' | missing_input=ACCEPTED';
  exception when others then v_out := v_out || ' | missing_input=' || coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1],left(SQLERRM,90)); end;

  select count(*) into v_e1 from public.phase_d_effect_ledger;
  v_out := v_out || ' | effects_after_negatives=' || (v_e1-v_e0)::text;

  -- positive, full payload, right actor
  begin
    perform public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor,
      'idempotency_key','dbg-pos', 'inputs', v_full, 'execution_context','production'));
    v_out := v_out || ' | positive=OK';
  exception when others then v_out := v_out || ' | positive=' || coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1],left(SQLERRM,120)); end;
  v_out := v_out || ' | effects_after_positive=' || ((select count(*) from public.phase_d_effect_ledger)-v_e0)::text;
  raise exception 'DBG<<%>>', v_out;
end $p$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,2500));
}
