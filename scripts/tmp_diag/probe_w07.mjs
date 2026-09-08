import { sql } from '../lib/db.mjs';
const q = `
do $emit$
declare v_fx jsonb; v jsonb; v_sr bigint; v_out text := ''; v_pay jsonb; e record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-w07'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','diagw07','execution_context','test'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W07','label','diagw07','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager'));
  select max(step_run_id) into v_sr from public.phase_c_workflow_step_run where step_id='W07-S01';
  v_pay := public.fn_phase_d_fixture_effect_payload(v_sr);
  select * into e from public.phase_d_step_effect where step_id='W07-S01';
  v_out := 'effect_object=' || coalesce(e.effect_object_id,'(null)')
        || ' type=' || coalesce(e.expected_effect_type,'?') || chr(31)
        || 'fixture_effect_payload=' || coalesce(v_pay::text,'(null)') || chr(31)
        || 'fixture_input_bucket=' || coalesce((select fi.value::text from
             public.fn_phase_d_fixture_input(v_sr,'EFFECT_PAYLOAD','bucket') fi limit 1),'(null)') || chr(31)
        || 'first_refusal=' || left(coalesce(v->'first_handler_refusal'->>'reason','(none)'),300);
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
