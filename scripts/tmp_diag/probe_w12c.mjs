import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint;
        v_ref_key text; v_boid text; r record; v_srid bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w12c'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w12c','execution_context','test','for_workflow','W12'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W12' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W12') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W12')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W12','label','dbg-w12c',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
    where sr.run_id=v_run and sr.step_id='W12-S06' limit 1;
  select d.inputs_provenance into v_out from public.phase_d_dispatch d
    where d.step_run_id=v_srid order by d.dispatch_id desc limit 1;
  v_out := 'prov=' || left(coalesce(v_out,'-'),700);
  for r in select ub.* from public.unsafe_block ub order by ub.id desc limit 3 loop
    v_out := v_out || E'\nUB ' || r.id || ' ' || coalesce(r.class_key,'-') || ' ' || left(coalesce(r.detail::text,'-'),200);
  end loop;
  raise exception 'DBG<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)).replace(/\n/g,'\n') : m.slice(0,4000));
}
