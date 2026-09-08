// What kernel-owned rows does the fixture scenario itself cause to exist? Aborted transaction.
import { sql } from '../lib/db.mjs';
const q = `
do $emit$
declare v_fx jsonb; v_out text := '';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-kernel'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','diagkern','execution_context','test'));
  v_out := 'stages_created=' || coalesce(v_fx->>'stages_created','?')
        || ' not_created=' || coalesce(v_fx->>'stages_not_created','?') || chr(31)
        || 'workflow_runs=' || (select count(*) from public.phase_c_workflow_run)::text
        || ' step_runs=' || (select count(*) from public.phase_c_workflow_step_run)::text
        || ' handoff_runs=' || (select count(*) from public.phase_c_handoff_run)::text || chr(31)
        || 'runs=' || coalesce((select string_agg(workflow_id || '#' || run_id::text, ', ' order by run_id)
                                  from public.phase_c_workflow_run),'(none)') || chr(31)
        || 'workstream_groups=' || (select count(*) from public.inquiry_workstream_group)::text || chr(31)
        || 'refused=' || coalesce((select string_agg(m->>'stage_key' || ':' || coalesce(m->>'refused_with','?')
             || ' ' || left(coalesce(m->>'reason',''),160), ' | ')
             from jsonb_array_elements(v_fx->'manifest') m where m->>'status' <> 'CREATED'),'(none)');
  raise exception 'DIAG%', v_out;
end $emit$;`;
try { await sql(q); console.error('no raise'); }
catch (err) {
  const m = String(err?.message ?? err); const at = m.indexOf('DIAG');
  let g = m.slice(at + 4).replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const c = g.indexOf('\nCONTEXT:'); if (c >= 0) g = g.slice(0, c);
  for (const l of g.split(String.fromCharCode(31))) if (l.trim()) console.log(l + '\n');
}
