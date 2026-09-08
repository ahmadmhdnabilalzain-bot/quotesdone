// Diagnostic, FULLY ROLLED BACK: instrument fn_phase_d_dispatch_step AND fn_phase_d_step_context in
// the aborted transaction; run the W14 kernel start; see which one logs at kernel time.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const defOf = async (n) => (await sql(`select pg_get_functiondef(p.oid) as def, md5(p.prosrc) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='${n}'`))[0];
const sc = await defOf('fn_phase_d_step_context');
const ds = await defOf('fn_phase_d_dispatch_step');
let scDef = sc.def, dsDef = ds.def;
// step_context: log at entry
const a1 = `begin\n  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;`;
if (scDef.split(a1).length - 1 !== 1) throw new Error('sc anchor ' + (scDef.split(a1).length - 1));
scDef = scDef.replace(a1, `begin\n  insert into pg_temp.zz_diag(k, note) values ('sc_entry', 'step_run=' || p_step_run_id || ' ctx=' || coalesce(public.fn_phase_d_fixture_context()::text,'NULL'));\n  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;`);
// dispatch_step: log at entry and after ctx
const a2 = `  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;\n  if not found then\n    raise exception 'fn_phase_d_dispatch_step: no step run %'`;
if (dsDef.split(a2).length - 1 !== 1) throw new Error('ds anchor ' + (dsDef.split(a2).length - 1));
dsDef = dsDef.replace(a2, `  insert into pg_temp.zz_diag(k, note) values ('ds_entry', 'step_run=' || v_step_run || ' kind=' || v_kind);\n` + a2);
const a3 = `    v_cx := public.fn_phase_d_step_context(v_step_run);`;
if (dsDef.split(a3).length - 1 !== 1) throw new Error('ds anchor3 ' + (dsDef.split(a3).length - 1));
dsDef = dsDef.replace(a3, a3 + `\n    insert into pg_temp.zz_diag(k, note) values ('ds_ctx', 'step_run=' || v_step_run || ' unresolved=' || coalesce((v_cx->'unresolved')::text,'?'));`);
const q = `do $emit$
declare v_fx jsonb; v_start jsonb; v_out text := ''; v_sr bigint; v_boid text; rr record;
begin
  create temp table zz_diag(k text, note text);
  ${scDef};
  ${dsDef};
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','w14iso6'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w14iso6','execution_context','test'));
  v_out := v_out || 'after_factory: ' || coalesce((select string_agg(k || '[' || left(note,60) || ']', ' ; ') from pg_temp.zz_diag),'') || chr(10);
  delete from pg_temp.zz_diag;
  v_boid := 'quotation:' || (v_fx->'parent_refs'->>'quote_id');
  v_start := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W14','business_object_id', v_boid,'source_kind','autonomous','source_ref','zz-phase-d-w14iso6','requested_by','quote_evaluation','trigger_ctx', jsonb_build_object('driver','probe')));
  v_out := v_out || 'after_start: ' || coalesce((select string_agg(k || '[' || left(note,120) || ']', ' ; ') from pg_temp.zz_diag),'') || chr(10);
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id = (v_start->>'run_id')::bigint order by step_run_id limit 1;
  v_out := v_out || 'dispatch rows for sr: ' || coalesce((select string_agg(d.dispatch_id || ':' || d.outcome || ':' || coalesce(d.refusal_code,'') || ':' || d.opened_by_kind, ' ; ' order by d.dispatch_id) from public.phase_d_dispatch d where d.step_run_id = v_sr),'(none)') || chr(10);
  raise exception 'RP<<%>>', left(v_out, 1800);
end $emit$;`;
let out;
try { await sql(q); out = 'no raise'; }
catch (e) { const m = String(e.message); const a = m.indexOf('RP<<'); out = a < 0 ? 'RAW ' + m.slice(0, 1500) : m.slice(a + 4, m.lastIndexOf('>>')).replace(/\\n/g, '\n').replace(/\\"/g, '"'); }
const sc2 = await defOf('fn_phase_d_step_context'); const ds2 = await defOf('fn_phase_d_dispatch_step');
out += `\nlive routines unchanged after probe: ${sc2.h === sc.h && ds2.h === ds.h}`;
writeFileSync('scripts/tmp_diag/probe_iso_s6.out', out);
console.log(out);
