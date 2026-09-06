import { sql } from '../phase_b/lib/db.mjs';

const body = `
do $emit$
declare v_out text := ''; v_w jsonb; v_st text; v_rc text; v_p boolean;
  v_qbad uuid; v_qgood uuid; v_appr text; v_draft text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-thirteen-probeD'));

  v_appr := 'zz-safe-approved';  v_draft := 'zz-safe-draft';
  perform public.fn_phase_d_object_write(jsonb_build_object(
    'object_id','supplier_safe_package','business_key', v_appr,'owner_ref','zz-inq',
    'created_by','decide_probe','state','approved','payload', jsonb_build_object('n',1)));
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_safe_package','business_key', v_draft,'owner_ref','zz-inq',
      'created_by','decide_probe','state','draft','payload', jsonb_build_object('n',2)));
    v_out := v_out || 'draftok|';
  exception when others then v_out := v_out || 'draftERR ' || left(SQLERRM,60) || '|'; end;

  -- D3 BR-012: an UNAPPROVED package
  select rc.state, rc.refusal_code into v_st, v_rc from public.fn_phase_d_rule_check('BR-012',
    jsonb_build_object('safe_package_ref', v_draft,'safe_package_approved_by','marketplace_content_privacy_reviewer')) rc;
  v_out := v_out || 'D3inj=' || v_st || '/' || v_rc || '|';
  select rc.state into v_st from public.fn_phase_d_rule_check('BR-012',
    jsonb_build_object('safe_package_ref', v_appr,'safe_package_approved_by','marketplace_content_privacy_reviewer')) rc;
  v_out := v_out || 'D3ctl=' || v_st || '|';
  select g.passed into v_p from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
    'safe_package_ref', v_appr,'safe_package_approved_by','marketplace_content_privacy_reviewer',
    'actor_role_id','marketplace_content_privacy_reviewer')) g;
  v_out := v_out || 'D3g13self=' || v_p || '|';
  select g.passed into v_p from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
    'safe_package_ref', v_appr,'safe_package_approved_by','compliance_and_privacy_officer',
    'actor_role_id','marketplace_content_privacy_reviewer')) g;
  v_out := v_out || 'D3g13indep=' || v_p || '|';

  -- L1 BR-026: a certificate before an acceptance record
  perform public.fn_phase_d_object_write(jsonb_build_object(
    'object_id','customer_terms_acceptance','business_key','zz-acc-real','owner_ref','zz-cust',
    'created_by','decide_probe','state','accepted','payload', jsonb_build_object('n',1)));
  select rc.state, rc.refusal_code into v_st, v_rc from public.fn_phase_d_rule_check('BR-026',
    jsonb_build_object('acceptance_ref','zz-acc-that-does-not-exist')) rc;
  v_out := v_out || 'L1inj=' || v_st || '/' || v_rc || '|';
  select rc.state into v_st from public.fn_phase_d_rule_check('BR-026',
    jsonb_build_object('acceptance_ref','zz-acc-real')) rc;
  v_out := v_out || 'L1ctl=' || v_st || '|';

  -- Q2 GATE-017: a quote missing a mandatory commercial field
  insert into public.quotes (id, quote_amount, status, source)
    values (gen_random_uuid(), 1000, '', 'zz-probe') returning id into v_qbad;
  insert into public.quotes (id, quote_amount, status, source)
    values (gen_random_uuid(), 1000, 'submitted', 'zz-probe') returning id into v_qgood;
  select g.passed, g.refusal_code into v_p, v_rc from public.fn_phase_d_gate_evaluate('GATE-017',
    jsonb_build_object('quote_id', v_qbad::text)) g;
  v_out := v_out || 'Q2inj=' || v_p || '/' || v_rc || '|';
  select g.passed into v_p from public.fn_phase_d_gate_evaluate('GATE-017',
    jsonb_build_object('quote_id', v_qgood::text)) g;
  v_out := v_out || 'Q2ctl=' || v_p || '|';
  begin
    insert into public.quotes (id, quote_amount, status, source)
      values (gen_random_uuid(), null, 'submitted', 'zz-probe');
    v_out := v_out || 'Q2noamt=ACCEPTED|';
  exception when others then v_out := v_out || 'Q2noamt=' || left(SQLERRM,55) || '|'; end;

  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;

try { await sql(body); console.log('did not raise'); }
catch (e) {
  const m = String(e.message); const a = m.indexOf('PROBE<<');
  console.log(a < 0 ? 'ERR: ' + m.slice(0, 2000) : m.slice(a + 7, m.indexOf('>>', a)).split('|').join('\n'));
}
