// Resolved context + provenance for the FIRST step of a workflow, inside a fixture scenario.
import { sql } from '../phase_c/lib/db.mjs';

const KEYS = process.argv[3] ? process.argv[3].split(',') : null;

const P = `
do $emit$
declare
  v_fx jsonb; v_run bigint; v_sr bigint; v_cx jsonb; v_out text := ''; k text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','ctx-__WF__'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','ctx-__WF__','execution_context','test',
    'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));
  v_run := (public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id','__WF__',
    'business_object_id',(select primary_object from public.phase_b_workflow where workflow_id='__WF__')||':ctx',
    'source_kind','autonomous','source_ref','zz-phase-d-ctx-__WF__',
    'requested_by',(select accountable_role_id from public.phase_b_workflow where workflow_id='__WF__'),
    'trigger_ctx', jsonb_build_object('driver','ctx_probe')))->>'run_id')::bigint;
  select step_run_id into v_sr from public.phase_c_workflow_step_run
   where run_id = v_run order by step_run_id limit 1;
  v_cx := public.fn_phase_d_step_context(v_sr);
  for k in select jsonb_object_keys(coalesce(v_cx->'context','{}'::jsonb)) loop
    v_out := v_out || chr(30) || k || ' = ' || left(coalesce(v_cx->'context'->>k,'(null)'), 90)
          || '   <- ' || left(coalesce(v_cx->'provenance'->>k,'(no provenance)'), 90);
  end loop;
  v_out := v_out || chr(30) || 'UNRESOLVED: ' || coalesce(v_cx->>'unresolved','[]');
  raise exception 'CTX%', left(v_out, 3000);
end $emit$;
`;

const id = process.argv[2];
try { await sql(P.replaceAll('__WF__', id)); }
catch (err) {
  const msg = String(err?.message ?? err);
  const at = msg.indexOf('CTX');
  if (at < 0) { console.log('RAW: '+msg.slice(0, 1500)); process.exit(0); }
  let got = msg.slice(at + 3)
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const ctx = got.indexOf('\nCONTEXT:'); if (ctx >= 0) got = got.slice(0, ctx);
  got.split(String.fromCharCode(30)).filter((x) => x.trim()).forEach((x) => {
    if (!KEYS || KEYS.some((k) => x.startsWith(k)) || x.startsWith('UNRESOLVED')) console.log('  ' + x);
  });
}
