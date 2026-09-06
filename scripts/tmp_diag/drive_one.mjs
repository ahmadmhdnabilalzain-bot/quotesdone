import { sql } from '../phase_c/lib/db.mjs';
const WF = process.argv[2]; const STEP = process.argv[3];
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint;
        v_ref_key text; v_boid text; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-${WF.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-${WF.toLowerCase()}','execution_context','test',
    'for_workflow', '${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','dbg-${WF.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  for r in
    select s.step_id, sr.step_run_id, sr.state st, d.outcome, d.refusal_code,
           left(coalesce(d.reason,'-'),400) detail,
           el.effect_type, el.result_reference
      from public.phase_b_workflow_step s
      left join lateral (select * from public.phase_c_workflow_step_run x
                          where x.run_id=v_run and x.step_id=s.step_id order by x.step_run_id limit 1) sr on true
      left join lateral (select * from public.phase_d_dispatch x where x.step_run_id=sr.step_run_id
                          order by x.dispatch_id desc limit 1) d on true
      left join lateral (select * from public.phase_d_effect_ledger x where x.step_run_id=sr.step_run_id
                          order by x.effect_id limit 1) el on true
     where s.workflow_id='${WF}' ${STEP ? `and s.step_id='${STEP}'` : ''}
     order by s.step_no
  loop
    v_out := v_out || r.step_id || ' st=' || coalesce(r.st,'-') || ' out=' || coalesce(r.outcome,'-')
          || ' rc=' || coalesce(r.refusal_code,'-') || ' eff=' || coalesce(r.effect_type,'-')
          || case when r.refusal_code is not null then ' DETAIL=' || r.detail else '' end || E'\n';
  end loop;
  raise exception 'DBG<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)).replace(/\n/g,'\n') : m.slice(0,4000));
}
