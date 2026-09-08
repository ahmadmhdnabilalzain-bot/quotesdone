// Diagnostic: why is the scenario door silent at kernel dispatch time? Re-dispatch the same step
// run from the probe and compare; also print the manifest entries for the supplier stages.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const run = async (q, tag) => {
  try { await sql(q); return 'no raise'; }
  catch (e) { const m = String(e.message); const a = m.indexOf(tag + '<<'); return a < 0 ? m.slice(0, 2500) : m.slice(a + tag.length + 2, m.lastIndexOf('>>')).replace(/\\n/g, '\n').replace(/\\"/g, '"'); }
};
let out = '';
out += await run(`do $emit$
declare v_fx jsonb; v_start jsonb; v_out text := ''; v_sr bigint; v_cx jsonb; v_boid text; v_rd jsonb; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','w14iso2'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w14iso2','execution_context','test'));
  for r in select e from jsonb_array_elements(v_fx->'manifest') e loop
    if (r.e->>'stage_no')::int between 100 and 160 then
      v_out := v_out || left(coalesce(r.e->>'stage_key','?') || ' ' || coalesce(r.e->>'status','?') || ' ' || coalesce(r.e->>'result_reference','') || ' ' || coalesce(r.e->>'detail',''), 150) || chr(10);
    end if;
  end loop;
  v_out := v_out || 'refs.supplier_id=' || coalesce(v_fx->'parent_refs'->>'supplier_id','?') || ' leads_max=' || (select max(id) from public.leads) || chr(10);
  v_boid := 'quotation:' || (v_fx->'parent_refs'->>'quote_id');
  v_start := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W14','business_object_id', v_boid,'source_kind','autonomous','source_ref','zz-phase-d-w14iso2','requested_by','quote_evaluation','trigger_ctx', jsonb_build_object('driver','probe')));
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id = (v_start->>'run_id')::bigint order by step_run_id limit 1;
  v_out := v_out || 'kernel dispatch unresolved=' || coalesce((select d.unresolved_keys::text from public.phase_d_dispatch d where d.step_run_id = v_sr order by d.dispatch_id desc limit 1),'(none)') || chr(10);
  v_rd := public.fn_phase_d_dispatch_step(jsonb_build_object('step_run_id', v_sr, 'actor_role_id','quote_evaluation','opened_by_kind','probe','opened_by_ref','iso2','idempotency_key','kernel|' || (v_start->>'run_id') || '|W14-S01'));
  v_out := v_out || 'probe redispatch=' || coalesce(v_rd->>'outcome','?') || ':' || coalesce(v_rd->>'refusal_code','') || ' unresolved=' || coalesce((select d.unresolved_keys::text from public.phase_d_dispatch d where d.step_run_id = v_sr order by d.dispatch_id desc limit 1),'(none)') || chr(10);
  v_out := v_out || 'quotes.supplier_id=' || coalesce((select q.supplier_id::text from public.quotes q where q.id::text = (v_fx->'parent_refs'->>'quote_id')),'?') || ' scn supplier_account=' || coalesce((select sc.canonical_ref->>'canonical_identity' from public.phase_d_scenario_record sc where sc.fixture_run_id = public.fn_phase_d_fixture_context() and sc.object_id='supplier_account' order by scenario_record_id desc limit 1),'?') || chr(10);
  raise exception 'RP<<%>>', v_out;
end $emit$;`, 'RP');
writeFileSync('scripts/tmp_diag/probe_iso_s2.out', out);
console.log(out);
