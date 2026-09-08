// Like dispatch_census but with the FULL reason (up to 900 chars) per non-EXECUTED dispatch, one probe per workflow,
// one message per dispatch row to dodge the 2000-char transport cap.
import { writeFileSync, appendFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const ids = (await sql('select workflow_id from public.phase_b_workflow order by workflow_id')).map((r) => r.workflow_id);
const only = process.argv[2] ? process.argv[2].split(',') : ids;
const out = process.argv[3] || 'scripts/tmp_diag/reason_census.txt';
writeFileSync(out, '');
for (const id of only) {
  // first probe: count and list of step_ids that did not execute, with row numbers
  const DRIVE = (sel) => `
do $emit$
declare v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_out text := ''; v_ref_key text; v_boid text; r record; i int := 0;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build', 'label','rcensus-${id}'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label', 'rcensus-${id}', 'execution_context','test', 'for_workflow', case when '${id}' = 'W12' then '${id}' else null end));
  select coalesce((select s.independent_reviewer_role_id from public.phase_b_workflow_step s where s.workflow_id = '${id}' and coalesce(btrim(s.independent_reviewer_role_id),'') <> '' order by s.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id = '${id}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> '' then (select primary_object from public.phase_b_workflow where workflow_id = '${id}') || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id', '${id}', 'label','rcensus-${id}', 'execution_context','production', 'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands) || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
  ${sel}
  raise exception 'RC%', v_out;
end $emit$;`;
  const run = async (sel) => {
    try { await sql(DRIVE(sel)); return null; }
    catch (err) { const msg = String(err?.message ?? err); const at = msg.indexOf('RC'); if (at < 0) return 'ERR ' + msg.slice(0, 300);
      let got = msg.slice(at + 2).replace(/\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16))).replace(/\\"/g, '"').replace(/\n/g, '\n');
      const ctx = got.indexOf('\nCONTEXT:'); if (ctx >= 0) got = got.slice(0, ctx); return got; }
  };
  // summary line: run state, per-step last outcome
  const summary = await run(`
  v_out := v_out || 'run_state=' || (v->>'run_state') || ' terminal=' || (v->>'terminal') || ' exec=' || (v->>'dispatches_executed') || '/' || (v->>'dispatches_seen') || ' stop=' || coalesce(v->'stopped'->>'refused_with','-') || '@' || coalesce(v->'stopped'->>'at','-') || chr(10);
  for r in select d.step_id, d.outcome, coalesce(d.refusal_code,'') rc from public.phase_d_dispatch d where d.run_id = (v->>'run_id')::bigint order by d.dispatch_id loop
    v_out := v_out || r.step_id || ' ' || r.outcome || ' ' || r.rc || chr(10);
  end loop;`);
  appendFileSync(out, `\n=============== ${id}\n${summary}\n`);
  // count non-executed dispatches that are the LAST for their step and not executed anywhere
  const list = await run(`
  for r in select d.step_id from public.phase_d_dispatch d where d.run_id=(v->>'run_id')::bigint group by d.step_id having bool_and(d.outcome <> 'EXECUTED') order by 1 loop
    v_out := v_out || r.step_id || ',';
  end loop;`);
  const steps = (list || '').split(',').map(s => s.trim()).filter(Boolean);
  for (const st of steps) {
    const reason = await run(`
  select d.step_id || ' ' || d.outcome || ' ' || coalesce(d.refusal_code,'') || chr(10) || left(coalesce(d.reason,''), 1200) into v_out
    from public.phase_d_dispatch d where d.run_id=(v->>'run_id')::bigint and d.step_id='${st}' order by d.dispatch_id desc limit 1;`);
    appendFileSync(out, `--- ${reason}\n`);
  }
  process.stdout.write(`${id}: ${steps.length} never-executed steps\n`);
}
