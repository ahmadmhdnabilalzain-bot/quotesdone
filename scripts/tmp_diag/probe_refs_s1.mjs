// Diagnostic: (1) parent_refs and the non-CREATED manifest entries of one scenario; (2) leads
// unique indexes; (3) W14 first-step dispatch: unresolved keys and fixture_context at dispatch time.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const run = async (q, tag) => {
  try { await sql(q); return 'no raise'; }
  catch (e) { const m = String(e.message); const a = m.indexOf(tag + '<<'); return a < 0 ? m.slice(0, 2500) : m.slice(a + tag.length + 2, m.lastIndexOf('>>')).replace(/\\n/g, '\n').replace(/\\"/g, '"'); }
};
let out = '';
out += '#### parent_refs + manifest (non-CREATED)\n' + await run(`do $emit$
declare v_fx jsonb; v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','refsprobe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','refsprobe','execution_context','test'));
  v_out := v_out || 'parent_refs=' || left((v_fx->'parent_refs')::text, 900) || chr(10);
  for r in select e from jsonb_array_elements(coalesce(v_fx->'manifest', v_fx->'stages', '[]'::jsonb)) e loop
    if coalesce(r.e->>'status','') <> 'CREATED' then
      v_out := v_out || left(coalesce(r.e->>'stage_key','?') || ' ' || coalesce(r.e->>'status','?') || ' ' || coalesce(r.e->>'refused_with','') || ' ' || coalesce(r.e->>'detail', r.e->>'reason', ''), 260) || chr(10);
    end if;
  end loop;
  v_out := v_out || 'keys=' || left((select string_agg(k, ',') from jsonb_object_keys(v_fx) k), 400);
  raise exception 'RP<<%>>', v_out;
end $emit$;`, 'RP');
out += '\n#### leads unique indexes\n' + JSON.stringify(await sql(`select indexname, indexdef from pg_indexes where schemaname='public' and tablename='leads' and indexdef ilike '%unique%'`));
out += '\n#### W14 first dispatch isolation\n' + await run(`do $emit$
declare v_fx jsonb; v_start jsonb; v_out text := ''; v_sr bigint; v_cx jsonb; v_boid text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','w14iso'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w14iso','execution_context','test'));
  v_boid := 'quotation:' || (v_fx->'parent_refs'->>'quote_id');
  v_out := v_out || 'ctx_before_start=' || coalesce(public.fn_phase_d_fixture_context()::text,'NULL') || chr(10);
  v_start := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W14','business_object_id', v_boid,'source_kind','autonomous','source_ref','zz-phase-d-w14iso','requested_by','quote_evaluation','trigger_ctx', jsonb_build_object('driver','probe')));
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id = (v_start->>'run_id')::bigint order by step_run_id limit 1;
  v_out := v_out || 'dispatch=' || coalesce((select d.outcome || ':' || coalesce(d.refusal_code,'') || ' unresolved=' || coalesce(d.unresolved_keys::text,'{}') from public.phase_d_dispatch d where d.step_run_id = v_sr order by d.dispatch_id desc limit 1),'(none)') || chr(10);
  v_cx := public.fn_phase_d_step_context(v_sr);
  v_out := v_out || 'now_unresolved=' || coalesce((v_cx->'unresolved')::text,'?') || chr(10);
  v_out := v_out || 'ctx_now=' || coalesce(public.fn_phase_d_fixture_context()::text,'NULL') || chr(10);
  v_out := v_out || 'scn_qrev=' || coalesce((select sc.canonical_ref::text from public.phase_d_scenario_record sc where sc.fixture_run_id = public.fn_phase_d_fixture_context() and sc.object_id='quotation_revision' order by scenario_record_id desc limit 1),'(none)') || chr(10);
  v_out := v_out || 'scn_cmp=' || coalesce((select sc.canonical_ref::text from public.phase_d_scenario_record sc where sc.fixture_run_id = public.fn_phase_d_fixture_context() and sc.object_id='quotation_comparison' order by scenario_record_id desc limit 1),'(none)') || chr(10);
  v_out := v_out || 'prov_qrev=' || left(coalesce((v_cx->'provenance'->>'quote_revision_ref'),'(none)'),200) || chr(10);
  raise exception 'RP<<%>>', v_out;
end $emit$;`, 'RP');
writeFileSync('scripts/tmp_diag/probe_refs_s1.out', out);
console.log(out);
