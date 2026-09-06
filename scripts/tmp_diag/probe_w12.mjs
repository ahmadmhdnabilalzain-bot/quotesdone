import { q } from './q.mjs';
const sql = `
do $p$
declare v_fx jsonb; v_dr jsonb; v_key text; v_rev text; v_out text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','w12-check'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-w12-check','execution_context','test','for_workflow','W12'));
  select o.business_key into v_key from public.phase_d_object_record o
   where o.object_id='supplier_safe_package' order by o.record_id desc limit 1;
  select count(*)::text into v_out from public.phase_d_file_revision where package_ref = v_key;
  v_out := 'package=' || coalesce(v_key,'(none)') || ' revisions=' || v_out;
  v_out := v_out || ' | pkg_dispatchable=' ||
    coalesce((select refusal_code from public.fn_phase_d_package_revisions_dispatchable(v_key)),'OK');
  v_out := v_out || ' | BR-012=' || (select state from public.fn_phase_d_rule_check('BR-012',
    jsonb_build_object('safe_package_ref', v_key, 'safe_package_approved_by','compliance_and_privacy_officer')));
  v_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W12','scenario', v_fx, 'mode','happy'));
  v_out := v_out || ' | drive terminal=' || coalesce(v_dr->>'terminal','?')
        || ' dispatches_executed=' || coalesce(v_dr->>'dispatches_executed','?')
        || ' first_refusal=' || coalesce(v_dr->>'first_handler_refusal','(none)');
  raise exception '%', 'W12CHK ' || v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ const m=String(e.message); const i=m.indexOf('W12CHK'); console.log(i<0?m.slice(0,900):m.slice(i).split('\nCONTEXT')[0]); }
