import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint;
        v_ref_key text; v_boid text; v_srid bigint; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w05'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w05','execution_context','test','for_workflow', null));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W05' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W05') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W05')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v_out := 'fx_founder_authority_ref=' || coalesce(v_fx->'parent_refs'->>'founder_authority_ref','NULL')
        || ' | scen_rows=' || (select count(*)::text from public.phase_d_scenario_record l
              where l.fixture_run_id = public.fn_phase_d_fixture_context()
                and l.contributes_ref='founder_authority_ref');
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W05','label','dbg-w05',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  v_out := v_out || ' | run=' || coalesce(v_run::text,'-')
        || ' cmd=' || coalesce((select command_id::text from public.phase_c_workflow_run where run_id=v_run),'NULL')
        || ' link=' || (select count(*)::text from public.founder_command_workflow_link where run_id=v_run);
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
    where sr.run_id=v_run and sr.step_id='W05-S07' limit 1;
  v_out := v_out || ' | srid=' || coalesce(v_srid::text,'NULL');
  if v_srid is not null then
    v_out := v_out || ' | ctx=' || coalesce(left((public.fn_phase_d_step_context(v_srid))::text, 900),'-');
  end if;
  raise exception 'DBG<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,3000));
}
