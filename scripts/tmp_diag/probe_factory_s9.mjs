import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v_fx jsonb; v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','factprobe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','factprobe','execution_context','test'));
  v_out := v_out || 'created=' || coalesce(v_fx->>'stages_created','?') || ' not_created=' || coalesce(v_fx->>'stages_not_created','?') || ' declared=' || coalesce(v_fx->>'stages_declared','?') || chr(10);
  for r in select e from jsonb_array_elements(v_fx->'manifest') e loop
    if coalesce(r.e->>'status','') <> 'CREATED' then
      v_out := v_out || left(coalesce(r.e->>'stage_key','?') || ' ' || coalesce(r.e->>'status','?') || ' ' || coalesce(r.e->>'refused_with','') || ' ' || coalesce(r.e->>'reason', r.e->>'detail',''), 230) || chr(10);
    end if;
  end loop;
  raise exception 'FP<<%>>', left(v_out, 1900);
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { const m = String(e.message); const a = m.indexOf('FP<<'); console.log(a < 0 ? m.slice(0, 1500) : m.slice(a + 4, m.lastIndexOf('>>')).replace(/\n/g, '\n').replace(/\\"/g,'"')); }
