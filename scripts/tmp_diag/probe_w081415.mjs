import { q } from './q.mjs';
for (const wf of ['W08','W14','W15']) {
  const sql = `
do $p$
declare v_fx jsonb; v_dr jsonb; v_out text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','chk-${wf}'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-chk-${wf}','execution_context','test','for_workflow','${wf}'));
  v_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','scenario', v_fx, 'mode','happy'));
  raise exception '%', 'CHK ${wf} first_refusal=' || coalesce(v_dr->>'first_handler_refusal','(none)')
    || ' dispatches=' || coalesce(v_dr->>'dispatches_executed','?');
end $p$;`;
  try { await q(sql); console.log(wf, 'DID NOT RAISE'); }
  catch(e){ const m=String(e.message); const i=m.indexOf('CHK '); console.log((i<0?m.slice(0,400):m.slice(i)).split('\nCONTEXT')[0].slice(0,420)); }
}
