import { sql } from '../phase_b/lib/db.mjs';

const body = `
do $emit$
declare v_out text := ''; v_id bigint; v_ok boolean; v_st text; v_rc text;
  v_ov text := 'category_overlay_001_construction-materials-suppliers';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-thirteen-probeB'));

  -- A5 injection / control through the registered writer
  begin
    v_id := public.fn_phase_c_task_create(jsonb_build_object(
      'source_kind','probe','source_ref','zz-a5','accountable_role_id', v_ov,
      'objective','zz','idempotency_key','zz-a5-inj'));
    v_out := v_out || 'A5inj=ACCEPTED task ' || v_id || '|';
  exception when others then v_out := v_out || 'A5inj=REFUSED ' || left(SQLERRM,80) || '|'; end;
  begin
    v_id := public.fn_phase_c_task_create(jsonb_build_object(
      'source_kind','probe','source_ref','zz-a5c','accountable_role_id','compliance_and_privacy_officer',
      'objective','zz','idempotency_key','zz-a5-ctl'));
    v_out := v_out || 'A5ctl=ACCEPTED task ' || v_id || '|';
  exception when others then v_out := v_out || 'A5ctl=REFUSED ' || left(SQLERRM,80) || '|'; end;

  -- L5 injection / control: the W28-S04 compliance review, creator as its own reviewer
  begin
    v_id := public.fn_phase_c_task_create(jsonb_build_object(
      'source_kind','probe','source_ref','zz-l5','workflow_id','W28','step_id','W28-S04',
      'accountable_role_id','compliance_and_privacy_officer','reviewer_required',true,
      'reviewer_role_id','compliance_and_privacy_officer','objective','zz','idempotency_key','zz-l5-inj'));
    v_out := v_out || 'L5inj=ACCEPTED task ' || v_id || '|';
  exception when others then v_out := v_out || 'L5inj=REFUSED ' || left(SQLERRM,80) || '|'; end;
  begin
    v_id := public.fn_phase_c_task_create(jsonb_build_object(
      'source_kind','probe','source_ref','zz-l5c','workflow_id','W28','step_id','W28-S04',
      'accountable_role_id','compliance_and_privacy_officer','reviewer_required',true,
      'reviewer_role_id','general_counsel','objective','zz','idempotency_key','zz-l5-ctl'));
    v_out := v_out || 'L5ctl=ACCEPTED task ' || v_id || '|';
  exception when others then v_out := v_out || 'L5ctl=REFUSED ' || left(SQLERRM,80) || '|'; end;

  -- D5 BR-048
  select rc.state, rc.refusal_code into v_st, v_rc from public.fn_phase_d_rule_check('BR-048', jsonb_build_object('actor_role_id', v_ov)) rc;
  v_out := v_out || 'D5inj=' || v_st || '/' || v_rc || '|';
  select rc.state into v_st from public.fn_phase_d_rule_check('BR-048', jsonb_build_object('actor_role_id','inquiry_router')) rc;
  v_out := v_out || 'D5ctl=' || v_st || '|';

  -- F1 BR-031
  select rc.state, rc.refusal_code into v_st, v_rc from public.fn_phase_d_rule_check('BR-031',
    jsonb_build_object('accountable_role_id','financial_controller','reviewer_role_id','financial_controller')) rc;
  v_out := v_out || 'F1inj=' || v_st || '/' || v_rc || '|';
  select rc.state into v_st from public.fn_phase_d_rule_check('BR-031',
    jsonb_build_object('accountable_role_id','financial_controller','reviewer_role_id','trust_and_safety_manager')) rc;
  v_out := v_out || 'F1ctl=' || v_st || '|';

  -- P1 BR-011
  select rc.state, rc.refusal_code into v_st, v_rc from public.fn_phase_d_rule_check('BR-011',
    jsonb_build_object('supplier_payload','RFQ 12 tonnes rebar. Contact zz.customer@example.invalid 0501234567')) rc;
  v_out := v_out || 'P1inj=' || v_st || '/' || v_rc || '|';
  select rc.state into v_st from public.fn_phase_d_rule_check('BR-011',
    jsonb_build_object('supplier_payload','RFQ 12 tonnes rebar grade B500B, delivery Dubai, no identity')) rc;
  v_out := v_out || 'P1ctl=' || v_st || '|';

  -- Q3 BR-027
  select rc.state, rc.refusal_code into v_st, v_rc from public.fn_phase_d_rule_check('BR-027',
    jsonb_build_object('claim','grade B500B certified')) rc;
  v_out := v_out || 'Q3inj=' || v_st || '/' || v_rc || '|';
  select rc.state into v_st from public.fn_phase_d_rule_check('BR-027',
    jsonb_build_object('claim','grade B500B certified','evidence_refs', jsonb_build_array('doc:1#p3'))) rc;
  v_out := v_out || 'Q3ctl=' || v_st || '|';

  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;

try { await sql(body); console.log('did not raise'); }
catch (e) {
  const m = String(e.message); const a = m.indexOf('PROBE<<');
  console.log(a < 0 ? 'ERR: ' + m.slice(0, 2000) : m.slice(a + 7, m.indexOf('>>', a)).split('|').join('\n'));
}
