// Probe the step context of the FIRST step run of one workflow, in an aborted transaction.
//   node scripts/tmp_diag/probe_ctx.mjs W14
import { sql } from '../phase_c/lib/db.mjs';
const WF = process.argv[2] || 'W14';
const q = `
do $emit$
declare v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_ref_key text; v_boid text;
  v_sr bigint; v_cx jsonb; v_out text := '';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-ctx'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','diagctx-${WF.toLowerCase()}','execution_context','test'));
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')
         || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;
  select coalesce((select s.independent_reviewer_role_id from public.phase_b_workflow_step s
      where s.workflow_id='${WF}' and coalesce(btrim(s.independent_reviewer_role_id),'')<>''
      order by s.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','diagctx-${WF.toLowerCase()}','execution_context','production',
    'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
  select min(step_run_id) into v_sr from public.phase_c_workflow_step_run
   where step_id = '${WF}-S01';
  v_cx := public.fn_phase_d_step_context(v_sr);
  v_out := 'boid=' || coalesce(v_boid,'(null)') || chr(31)
        || 'business_object=' || coalesce(v_cx->>'business_object','?') || chr(31)
        || 'unresolved=' || coalesce(v_cx->>'unresolved','?') || chr(31)
        || 'context=' || left(coalesce(v_cx->>'context','?'), 1200) || chr(31)
        || 'scenario_objects=' || coalesce((select string_agg(sc.object_id || '=' ||
             coalesce(sc.canonical_ref->>'canonical_identity','(null)'), ', ' order by sc.object_id)
             from public.phase_d_scenario_record sc
            where sc.fixture_run_id = public.fn_phase_d_fixture_context()),'(none)');
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
