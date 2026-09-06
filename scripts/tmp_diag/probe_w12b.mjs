import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint;
        v_ref_key text; v_boid text; r record; v_srid bigint; v_ctx jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w12b'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w12b','execution_context','test','for_workflow','W12'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W12' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W12') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W12')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W12','label','dbg-w12b',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
    where sr.run_id=v_run and sr.step_id='W12-S06' limit 1;
  v_ctx := public.fn_phase_d_step_context(v_srid);
  v_out := 'parent_refs=' || left((v_fx->'parent_refs')::text, 500)
        || E'\nctx.context.inquiry_id=' || coalesce(v_ctx->'context'->>'inquiry_id','-')
        || ' owner_ref=' || coalesce(v_ctx->'context'->>'owner_ref','-')
        || ' supplier_id=' || coalesce(v_ctx->'context'->>'supplier_id','-');
  -- the state of the inquiry named in the context, and the supplier
  v_out := v_out || E'\ninq rfq_ready=' || coalesce((select rfq_ready::text from public.inquiries where id::text = v_ctx->'context'->>'inquiry_id'),'NO-ROW');
  for r in select l.id, l.company_name, l.banned, l.matching_blocked, l.permanently_closed, l.license_expiry
             from public.leads l where l.id::text = coalesce(v_ctx->'context'->>'owner_ref', v_ctx->'context'->>'supplier_id')
  loop
    v_out := v_out || E'\nsupplier ' || r.id || ' banned=' || coalesce(r.banned::text,'-')
          || ' blocked=' || coalesce(r.matching_blocked::text,'-')
          || ' closed=' || coalesce(r.permanently_closed::text,'-')
          || ' lic=' || coalesce(r.license_expiry::text,'-');
  end loop;
  v_out := v_out || E'\nexisting matches for inq=' || (select count(*)::text from public.inquiry_matches m where m.inquiry_id::text = v_ctx->'context'->>'inquiry_id');
  raise exception 'DBG<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)).replace(/\n/g,'\n') : m.slice(0,4000));
}
