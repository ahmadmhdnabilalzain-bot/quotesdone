// Diagnostic, FULLY ROLLED BACK: replace fn_phase_d_step_context inside the aborted transaction with
// an instrumented copy that writes what the scenario door saw into a temp table, run the W14 start,
// read the temp table, raise. DDL is transactional, so the live routine is untouched afterwards; the
// read-back at the end of this file asserts it.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';
const r = await sql(`select pg_get_functiondef(p.oid) as def, md5(p.prosrc) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
let def = r[0].def; const h0 = r[0].h;
const anchor = `        select sc.canonical_ref into v_scn_ref
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.object_id = v_key_obj
         order by sc.scenario_record_id desc limit 1;`;
if (def.split(anchor).length - 1 !== 1) throw new Error('anchor not found once: ' + (def.split(anchor).length - 1));
def = def.replace(anchor, anchor + `
        insert into pg_temp.zz_diag(k, note) values (v_k, format('ctx=%s keyobj=%s scn_null=%s ci=%s nrec=%s', public.fn_phase_d_fixture_context(), v_key_obj, (v_scn_ref is null), v_scn_ref->>'canonical_identity', (select count(*) from public.phase_d_scenario_record sc2 where sc2.object_id = v_key_obj)));`);
// ALSO instrument the G08 branch entry
const anchor2 = `      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;

      if v_found and v_key_obj is not null and v_key_obj = v_obj then`;
if (def.split(anchor2).length - 1 !== 1) throw new Error('anchor2 not found once');
def = def.replace(anchor2, `      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;
      insert into pg_temp.zz_diag(k, note) values (v_k, format('G08 found=%s keyobj=%s obj=%s', v_found, v_key_obj, v_obj));

      if v_found and v_key_obj is not null and v_key_obj = v_obj then`);
const esc = (s) => s.replace(/\$function\$/g, '$function$');
const q = `do $emit$
declare v_fx jsonb; v_start jsonb; v_out text := ''; v_sr bigint; v_boid text; rr record;
begin
  create temp table zz_diag(k text, note text);
  ${def};
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','w14iso5'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','w14iso5','execution_context','test'));
  v_out := v_out || 'after_factory_rows=' || (select count(*) from pg_temp.zz_diag) || chr(10); delete from pg_temp.zz_diag;
  v_boid := 'quotation:' || (v_fx->'parent_refs'->>'quote_id');
  v_start := public.fn_kernel_workflow_start(jsonb_build_object('workflow_id','W14','business_object_id', v_boid,'source_kind','autonomous','source_ref','zz-phase-d-w14iso5','requested_by','quote_evaluation','trigger_ctx', jsonb_build_object('driver','probe')));
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id = (v_start->>'run_id')::bigint order by step_run_id limit 1;
  perform public.fn_phase_d_step_context(v_sr); v_out := v_out || 'after_direct_call_rows=' || (select count(*) from pg_temp.zz_diag) || chr(10);
  v_out := v_out || 'total_diag_rows=' || (select count(*) from pg_temp.zz_diag) || ' distinct_keys=' || coalesce((select string_agg(distinct k, ',') from pg_temp.zz_diag),'') || chr(10);
  for rr in select k, note from pg_temp.zz_diag where k in ('comparison_id','quote_revision_ref','caller_customer_id') loop
    v_out := v_out || rr.k || ': ' || rr.note || chr(10);
  end loop;
  raise exception 'RP<<%>>', left(v_out, 1800);
end $emit$;`;
let out;
try { await sql(q); out = 'no raise'; }
catch (e) { const m = String(e.message); const a = m.indexOf('RP<<'); console.log('RAW', m.slice(0,1200)); out = a < 0 ? m.slice(0, 3000) : m.slice(a + 4, m.lastIndexOf('>>')).replace(/\\n/g, '\n').replace(/\\"/g, '"'); }
const r2 = await sql(`select md5(p.prosrc) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
out += `\nlive routine unchanged after probe: ${r2[0].h === h0}`;
writeFileSync('scripts/tmp_diag/probe_iso_s5.out', out);
console.log(out);
