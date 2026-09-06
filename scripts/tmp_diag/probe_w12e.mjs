import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint;
        v_ref_key text; v_boid text; v_srid bigint; v_ctx jsonb; v_id bigint; v_owner text;
        v_own_rel text; v_own_ns text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','dbg-w12e'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','dbg-w12e','execution_context','test','for_workflow','W12'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W12' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W12') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W12')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W12','label','dbg-w12e',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  select sr.step_run_id into v_srid from public.phase_c_workflow_step_run sr
    where sr.run_id=v_run and sr.step_id='W12-S06' limit 1;
  v_ctx := public.fn_phase_d_step_context(v_srid);
  -- replicate the owner derivation
  select cl2.relname, ns2.nspname into v_own_rel, v_own_ns
    from public.phase_d_object_write_map wm2
    join pg_attribute a2 on a2.attrelid = to_regclass(wm2.target_relation)
                        and a2.attname = wm2.owner_column and a2.attnum > 0
    join pg_constraint c2 on c2.conrelid = a2.attrelid and c2.contype = 'f'
                         and a2.attnum = any (c2.conkey)
    join pg_class cl2 on cl2.oid = c2.confrelid
    join pg_namespace ns2 on ns2.oid = cl2.relnamespace
   where wm2.object_id = 'supplier_assignment' limit 1;
  v_out := 'ownerFK=' || coalesce(v_own_ns||'.'||v_own_rel,'NONE');
  select nullif(btrim(coalesce(sc.business_key,'')),'') into v_owner
    from public.phase_d_scenario_record sc
    join public.phase_d_business_object_binding bb on bb.object_id = sc.object_id
   where sc.fixture_run_id = public.fn_phase_d_fixture_context()
     and bb.canonical_relation = v_own_ns || '.' || v_own_rel
     and coalesce(btrim(sc.business_key),'') <> ''
   order by sc.scenario_record_id limit 1;
  v_out := v_out || ' owner=' || coalesce(v_owner,'NULL')
        || ' | payload_inquiry=' || coalesce(public.fn_phase_d_fixture_effect_payload(v_srid)->>'inquiry_id','-')
        || ' | fx_payload=' || left(public.fn_phase_d_fixture_effect_payload(v_srid)::text,300);
  begin
    insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
    values ((v_ctx->'context'->>'inquiry_id')::uuid, v_owner::bigint, 0.9, 'probe-replica')
    returning id into v_id;
    v_out := v_out || ' | replica_id=' || coalesce(v_id::text,'NULL-RETURNED');
  exception when others then v_out := v_out || ' | replica_raised=' || sqlerrm; end;
  raise exception 'DBG<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const a = m.indexOf('DBG<<');
  console.log(a>=0 ? m.slice(a+5, m.indexOf('>>', a)) : m.slice(0,4000));
}
