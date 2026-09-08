import { sql } from '../lib/db.mjs';
const q = `do $emit$
declare v_fx jsonb; v_start jsonb; v_out text := ''; v_boid text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','w14dd'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w14dd','execution_context','test'));
  v_out := v_out || 'g12=' || coalesce((select e->>'result_reference' from jsonb_array_elements(v_fx->'manifest') e where e->>'stage_key'='kernel_objects'),'?') || chr(10);
  v_out := v_out || 'g12 wf=' || coalesce((select string_agg(r.workflow_id || ':' || r.run_id || ':' || r.business_object_id, ',') from public.phase_c_workflow_run r where r.opened_at > now() - interval '10 minutes'),'?') || chr(10);
  v_boid := 'quotation:' || (v_fx->'parent_refs'->>'quote_id');
  v_start := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W14','business_object_id', v_boid,'source_kind','autonomous','source_ref','zz-phase-d-w14dd','requested_by','quote_evaluation','trigger_ctx', jsonb_build_object('driver','probe')));
  v_out := v_out || 'start dup=' || coalesce(v_start->>'duplicate','?') || ' run=' || coalesce(v_start->>'run_id','?') || ' dedupe=' || coalesce(v_start->>'dedupe_key','?') || chr(10);
  v_out := v_out || 'runs in tx=' || coalesce((select string_agg(r.workflow_id || ':' || r.run_id || ':' || left(r.business_object_id,40), ' ; ') from public.phase_c_workflow_run r where r.opened_at > now() - interval '10 minutes'),'?') || chr(10);
  raise exception 'RP<<%>>', left(v_out, 1800);
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { const m = String(e.message); const a = m.indexOf('RP<<'); console.log(a < 0 ? m.slice(0, 1500) : m.slice(a + 4, m.lastIndexOf('>>')).replace(/\n/g, '\n')); }
