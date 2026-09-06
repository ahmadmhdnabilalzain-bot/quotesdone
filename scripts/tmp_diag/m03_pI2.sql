do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := '';
        v_ref_key text; v_boid text; v_srid bigint; v_t0 timestamptz := clock_timestamp();
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-pi2'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-pi2','execution_context','test','for_workflow','W04'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W04' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W04') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W04')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  perform set_config('app.phase_d_hold_step','W04-S03', true);
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','label','m03-pi2','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','W04-S03')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := format('held=%s ', v_srid);
  declare v_run bigint := (v->>'run_id')::bigint; v_r jsonb; v_c int; v_st text; v_key text;
  begin
    v_key := 'm03:i2:'||v_srid;
    v_r := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
      'outcome','pass','idempotency_key',v_key,
      'inputs', jsonb_build_object('mode','first completion'),
      'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','first')),
      'acceptance_criteria','the step completes once',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
    v_out := v_out || format('A_replay=%s ', v_r->>'replay');
    v_r := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
      'outcome','pass','idempotency_key',v_key,
      'inputs', jsonb_build_object('mode','duplicate completion'),
      'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','duplicate')),
      'acceptance_criteria','the duplicate returns the first result',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
    v_out := v_out || format('B_replay=%s same=%s ', v_r->>'replay',
      (v_r->>'step_run_id') is not distinct from v_srid::text);
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid,
        'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
        'outcome','pass','idempotency_key',v_key||':different',
        'inputs', jsonb_build_object('mode','control'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
        'acceptance_criteria','a different key on the same completed step run',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
      v_out := v_out || 'CTL=ACCEPTED ';
    exception when others then
      v_out := v_out || format('CTL=%s si=%s ', SQLSTATE, position('k3_step_state_invalid' in SQLERRM)>0);
    end;
    select count(*) into v_c from public.phase_c_step_completion where step_run_id=v_srid;
    select state into v_st from public.phase_c_workflow_step_run where step_run_id=v_srid;
    v_out := v_out || format('completions=%s state=%s ', v_c, v_st);
  end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
