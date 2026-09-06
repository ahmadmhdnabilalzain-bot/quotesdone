do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := '';
        v_ref_key text; v_boid text; v_srid bigint; v_t0 timestamptz := clock_timestamp();
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-pa'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-pa','execution_context','test','for_workflow','W04'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W04' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W04') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W04')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  perform set_config('app.phase_d_hold_step','W04-S04', true);
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','label','m03-pa','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','W04-S04')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := format('ms=%s held_srid=%s held_step=%s run=%s stopped=%s',
      round(extract(epoch from clock_timestamp()-v_t0)*1000), v_srid, v->>'held_step_id', v->>'run_id',
      left(coalesce(v->'stopped'->>'refused_with','-'),40));
  if v_srid is not null then
    v_out := v_out || ' || ' || (select format('state=%s acct=%s task=%s', sr.state, sr.accountable_role_id,
        (select t.task_id from public.phase_c_task t where t.run_id=sr.run_id and t.step_id=sr.step_id order by t.task_id limit 1))
      from public.phase_c_workflow_step_run sr where sr.step_run_id=v_srid);
    v_out := v_out || format(' srcount=%s', (select count(*) from public.phase_c_workflow_step_run where run_id=(v->>'run_id')::bigint));
  end if;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
