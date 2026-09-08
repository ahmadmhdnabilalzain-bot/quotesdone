import { sql } from '../lib/db.mjs';
const WF = process.argv[2] || 'W09';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;
        v_ref_key text; v_boid text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','probe-${WF.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','probe-${WF.toLowerCase()}','execution_context','test','for_workflow','${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v_out := v_out || 'SKIPPED=' || coalesce((select string_agg(m->>'stage_key',',') from jsonb_array_elements(v_fx->'manifest') m where m->>'status' like 'SKIPPED_PRODUCED%'),'-') || E'\n';
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','probe-${WF.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  for r in select sr.step_id, sr.state, left(coalesce(sr.failure_reason,''),200) res
             from public.phase_c_workflow_step_run sr where sr.run_id=v_run order by sr.step_run_id
  loop v_out := v_out || r.step_id||'|'||r.state||'|'||r.res||E'\n'; end loop;
  for r in select d.step_id, d.outcome as dispatch_state, left(coalesce(d.refusal_code,''),60) rc, left(coalesce(d.reason,''),240) dt
             from public.phase_d_dispatch d where d.run_id=v_run order by d.dispatch_id
  loop v_out := v_out || 'DISP '||r.step_id||'|'||r.dispatch_state||'|'||r.rc||'|'||r.dt||E'\n'; end loop;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const i = m.indexOf('PROBE<<');
  console.log(i >= 0 ? m.slice(i + 7, m.indexOf('>>', i)).replace(/\n/g, '\n') : m.slice(0, 3000));
}
