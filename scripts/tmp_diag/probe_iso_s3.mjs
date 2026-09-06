// Diagnostic: kernel-time dispatch provenance for W14-S01 — which doors answered at kernel time.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';
const run = async (q, tag) => {
  try { await sql(q); return 'no raise'; }
  catch (e) { const m = String(e.message); const a = m.indexOf(tag + '<<'); return a < 0 ? m.slice(0, 2500) : m.slice(a + tag.length + 2, m.lastIndexOf('>>')).replace(/\\n/g, '\n').replace(/\\"/g, '"'); }
};
const body = (sel) => `do $emit$
declare v_fx jsonb; v_start jsonb; v_out text := ''; v_sr bigint; v_boid text; v_prov jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','w14iso3'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w14iso3','execution_context','test'));
  v_boid := 'quotation:' || (v_fx->'parent_refs'->>'quote_id');
  v_start := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W14','business_object_id', v_boid,'source_kind','autonomous','source_ref','zz-phase-d-w14iso3','requested_by','quote_evaluation','trigger_ctx', jsonb_build_object('driver','probe')));
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id = (v_start->>'run_id')::bigint order by step_run_id limit 1;
  select d.inputs_provenance into v_prov from public.phase_d_dispatch d where d.step_run_id = v_sr order by d.dispatch_id limit 1;
  ${sel}
  raise exception 'RP<<%>>', v_out;
end $emit$;`;
let out = '';
out += await run(body(`v_out := left(coalesce((select string_agg(k || '=' || left(v_prov->>k, 70), chr(10) order by k) from jsonb_object_keys(v_prov) k),'(none)'), 1800);`), 'RP');
writeFileSync('scripts/tmp_diag/probe_iso_s3.out', out);
console.log(out);
