// Full reason for pd_effect_payload_incomplete / value_malformed / identity_collision steps, per workflow.
import { writeFileSync, appendFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const only = (process.argv[2]||'').split(',').filter(Boolean);
const out='scripts/tmp_diag/probe_pi_s12.txt'; writeFileSync(out,'');
for (const id of only) {
  const q = `do $emit$
declare v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_out text := ''; v_ref_key text; v_boid text; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build', 'label','pi-${id}'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label', 'pi-${id}', 'execution_context','test', 'for_workflow', case when '${id}' = 'W12' then '${id}' else null end));
  select coalesce((select s.independent_reviewer_role_id from public.phase_b_workflow_step s where s.workflow_id = '${id}' and coalesce(btrim(s.independent_reviewer_role_id),'') <> '' order by s.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id = '${id}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> '' then (select primary_object from public.phase_b_workflow where workflow_id = '${id}') || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id', '${id}', 'label','pi-${id}', 'execution_context','production', 'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands) || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
  for r in select d.step_id, d.outcome, coalesce(d.refusal_code,'') rc, left(coalesce(d.reason,''),300) reason from public.phase_d_dispatch d where d.run_id=(v->>'run_id')::bigint and d.step_id in (select step_id from public.phase_d_dispatch where run_id=(v->>'run_id')::bigint group by step_id having bool_and(outcome<>'EXECUTED')) and d.outcome<>'EXECUTED' order by d.step_id, d.dispatch_id desc loop
    v_out := v_out || r.step_id || ' ' || r.rc || ' :: ' || r.reason || chr(10);
  end loop;
  raise exception 'PI<<%>>', left(v_out, 1900);
end $emit$;`;
  let got; try { await sql(q); got='no raise'; } catch(e){ const m=String(e.message); const a=m.indexOf('PI<<'); got=a<0?'ERR '+m.slice(0,400):m.slice(a+4,m.lastIndexOf('>>')).replace(/\n/g,'\n').replace(/\\"/g,'"'); }
  appendFileSync(out, `=== ${id}\n${got}\n`); process.stdout.write(id+' done\n');
}
