import { q } from './q.mjs';
const sql = `
do $p$
declare v_fx jsonb; v_out text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','pkgkeys'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','zz-pkgkeys','execution_context','test','for_workflow','W08'));
  select 'object rows: ' || coalesce(string_agg(o.record_id||'|'||o.business_key,' ; '),'(none)')
    into v_out from public.phase_d_object_record o where o.object_id='supplier_safe_package';
  v_out := v_out || ' || revisions: ' ||
    coalesce((select string_agg(fr.revision_ref||' -> '||fr.package_ref,' ; ')
                from public.phase_d_file_revision fr where fr.revision_ref like 'fxrev:%'),'(none)');
  v_out := v_out || ' || scenario_record: ' ||
    coalesce((select string_agg(sc.object_id||'='||coalesce(sc.canonical_ref->>'canonical_identity','?'),' ; ')
                from public.phase_d_scenario_record sc
               where sc.fixture_run_id = public.fn_phase_d_fixture_context()
                 and sc.object_id in ('supplier_safe_package','quotation_revision')),'(none)');
  raise exception '%', 'PKG ' || v_out;
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ const m=String(e.message); const i=m.indexOf('PKG '); console.log((i<0?m.slice(0,700):m.slice(i)).split('\nCONTEXT')[0].slice(0,900)); }
