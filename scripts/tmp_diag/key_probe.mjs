import { sql } from '../lib/db.mjs';
const P = `
do $emit$
declare v_fx jsonb; v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','key-probe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','key-probe','execution_context','test'));
  for r in
    select sc.object_id, coalesce(sc.canonical_ref->'physical_ref'->>'pk_value','(NO REF)') as scenario_key, sc.state as scenario_state,
           (select count(*) from public.phase_d_object_record o
             where o.object_id = sc.object_id and o.business_key = sc.canonical_ref->'physical_ref'->>'pk_value') as matching_object_records,
           (select string_agg(o2.business_key || '/' || coalesce(o2.state,'?'), ' ')
              from public.phase_d_object_record o2 where o2.object_id = sc.object_id) as object_record_keys
      from public.phase_d_scenario_record sc
     where sc.fixture_run_id = public.fn_phase_d_fixture_context()
       and sc.object_id in ('customer_terms_acceptance','supplier_safe_package','supplier_account',
                            'inquiry','payment_transaction','quotation_revision','ux_specification')
     order by sc.scenario_record_id
  loop
    v_out := v_out || chr(30) || r.object_id || ' scen=' || coalesce(r.scenario_key,'-')
          || '/' || coalesce(r.scenario_state,'-')
          || ' matching_object_records=' || r.matching_object_records
          || ' object_record=' || left(coalesce(r.object_record_keys,'(NONE)'), 60);
  end loop;
  raise exception 'KEYS%', left(v_out, 2200);
end $emit$;`;
try { await sql(P); } catch (err) {
  const msg = String(err?.message ?? err); const at = msg.indexOf('KEYS');
  if (at < 0) { console.log('RAW: ' + msg.slice(0, 1200)); process.exit(0); }
  let got = msg.slice(at + 4).replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const c = got.indexOf('\nCONTEXT:'); if (c >= 0) got = got.slice(0, c);
  got.split(String.fromCharCode(30)).filter((x) => x.trim()).forEach((x) => console.log('  ' + x));
}
