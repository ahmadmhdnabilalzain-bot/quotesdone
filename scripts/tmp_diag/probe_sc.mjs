import { sql } from '../lib/db.mjs';
const q = `do $emit$
declare v_fx jsonb; v_out text:='';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','scenario-scope-probe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','scenario-scope-probe','execution_context','test'));
  v_out := coalesce((select string_agg(sc.object_id||'/'||coalesce(sc.ownership_scope,'-')||'/owner='||coalesce(sc.owner_ref,'-')||'/key='||coalesce(sc.business_key,'-'), ' ; ' order by sc.scenario_record_id)
    from public.phase_d_scenario_record sc where sc.fixture_run_id = public.fn_phase_d_fixture_context()
      and sc.ownership_scope in ('SUPPLIER','CUSTOMER')),'(none)');
  raise exception 'SC<<%>>', v_out;
end $emit$;`;
try { await sql(q); console.log('(no marker)'); }
catch (e) { const m = String(e.message); const a = m.indexOf('SC<<'); console.log(a<0 ? 'ERR:'+m.slice(0,600).replace(/\s+/g,' ') : m.slice(a+4, m.indexOf('>>',a))); }
