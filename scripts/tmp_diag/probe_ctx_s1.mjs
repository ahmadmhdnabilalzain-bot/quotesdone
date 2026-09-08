// Diagnostic: drive one workflow (happy, real scenario object) and dump, for ONE named step, the
// dispatch provenance/unresolved keys, the recorded review and the resolved context; then, in two
// further aborted transactions, the scenario records in two halves. The management transport cuts a
// message at 2000 characters, so every probe here stays under it.
//   node scripts/tmp_diag/probe_ctx_s1.mjs W14 W14-S01
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const WF = process.argv[2];
const STEP = process.argv[3];

const PRE = `
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build', 'label','ctxprobe-${WF}'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label', 'ctxprobe-${WF}', 'execution_context','test', 'for_workflow', case when '${WF}' = 'W12' then '${WF}' else null end));
  select coalesce((select s.independent_reviewer_role_id from public.phase_b_workflow_step s where s.workflow_id = '${WF}' and coalesce(btrim(s.independent_reviewer_role_id),'') <> '' order by s.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id = '${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> '' then (select primary_object from public.phase_b_workflow where workflow_id = '${WF}') || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id', '${WF}', 'label','ctxprobe-${WF}', 'execution_context','production', 'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands) || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
`;
const wrap = (body) => `do $emit$
declare v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_out text := ''; v_ref_key text; v_boid text; r record;
begin
${PRE}
${body}
  raise exception 'CTXPROBE<<%>>', v_out;
end $emit$;`;

const run = async (body) => {
  try { await sql(wrap(body)); return 'no raise'; }
  catch (e) { const m = String(e.message); const a = m.indexOf('CTXPROBE<<'); return a < 0 ? m.slice(0, 3000) : m.slice(a + 10, m.lastIndexOf('>>')).replace(/\\n/g, '\n').replace(/\\"/g, '"'); }
};

const stepBody = `
  v_out := v_out || 'boid=' || coalesce(v_boid,'(null)') || ' run_state=' || (v->>'run_state') || ' exec=' || (v->>'dispatches_executed') || '/' || (v->>'dispatches_seen') || chr(10);
  for r in select d.step_id, d.outcome, coalesce(d.refusal_code,'') rc, left(coalesce(d.reason,''),260) reason, d.unresolved_keys, d.inputs_provenance, d.step_run_id
             from public.phase_d_dispatch d where d.run_id = (v->>'run_id')::bigint and d.step_id = '${STEP}' order by d.dispatch_id desc limit 1 loop
    v_out := v_out || '--- ' || r.step_id || ' ' || r.outcome || ' ' || r.rc || chr(10) || r.reason || chr(10)
          || 'unresolved=' || coalesce(r.unresolved_keys::text,'{}') || chr(10)
          || 'review=' || coalesce(public.fn_phase_d_recorded_review(r.step_run_id)::text,'(none)') || chr(10)
          || 'ctx=' || left(coalesce(((public.fn_phase_d_step_context(r.step_run_id))->'context')::text,'{}'), 700) || chr(10)
          || 'unres=' || left(coalesce(((public.fn_phase_d_step_context(r.step_run_id))->'unresolved')::text,'[]'), 300) || chr(10);
  end loop;`;
const scnBody = (lo, hi) => `
  for r in select sc.object_id, sc.business_key, sc.owner_ref, sc.ownership_scope, sc.contributes_ref, sc.contributed_value, sc.canonical_ref->>'canonical_identity' ci, sc.canonical_relation, row_number() over (order by sc.scenario_record_id) rn
             from public.phase_d_scenario_record sc where sc.fixture_run_id = public.fn_phase_d_fixture_context() order by sc.scenario_record_id loop
    if r.rn between ${lo} and ${hi} then
      v_out := v_out || r.object_id || '|' || left(coalesce(r.business_key,''),12) || '|' || left(coalesce(r.owner_ref,''),12) || '|' || coalesce(r.ownership_scope,'') || '|' || coalesce(r.contributes_ref,'') || '|' || left(coalesce(r.contributed_value,''),14) || '|' || left(coalesce(r.ci,''),14) || '|' || coalesce(r.canonical_relation,'') || chr(10);
    end if;
  end loop;`;

let out = '';
out += await run(stepBody);
out += '\n==== scenario records 1-20\n' + await run(scnBody(1, 20));
out += '\n==== scenario records 21-40\n' + await run(scnBody(21, 40));
out += '\n==== scenario records 41-60\n' + await run(scnBody(41, 60));
writeFileSync(`scripts/tmp_diag/ctxprobe_${WF}.txt`, out);
console.log(out);
