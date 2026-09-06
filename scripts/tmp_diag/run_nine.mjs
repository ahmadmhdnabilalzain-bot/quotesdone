import { q } from './q.mjs';
const cat = process.argv[2];
const sql = `
do $emit$
declare v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','nine-check'));
  for r in select * from public.fn_phase_d_injected_defect_report() where category = '${cat}' order by defect_id loop
    v_out := v_out || chr(10) || r.defect_id || ' | ' || r.status || ' | ' || left(coalesce(r.observed, r.blocker, ''), 200);
  end loop;
  raise exception 'NINE%', v_out;
end $emit$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){
  const m = String(e.message);
  const i = m.indexOf('NINE');
  console.log((i<0?m:m.slice(i+4)).replace(/\n/g,'\n').split('\nCONTEXT')[0]);
}
