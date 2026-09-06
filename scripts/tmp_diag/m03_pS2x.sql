do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := '';
        v_ref_key text; v_boid text; v_srid bigint; v_t0 timestamptz := clock_timestamp();
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-ps2x'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-ps2x','execution_context','test','for_workflow','W04'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W04' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='W04') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='W04')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  perform set_config('app.phase_d_hold_step','W04-S06', true);
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','label','m03-ps2x','execution_context','production',
    'reviewer_role_id',v_rev,'reviewer_candidates',v_cands,'hold_at_step_id','W04-S06')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := format('held=%s ', v_srid);
  declare v_run bigint := (v->>'run_id')::bigint; v_task bigint; v_r jsonb; v_s7 bigint; v_o jsonb;
          v_c bigint; v_nsr int; v_nsr2 int;
  begin
    perform set_config('app.phase_d_hold_step','W04-S07', true);
    select count(*) into v_nsr from public.phase_c_workflow_step_run where run_id=v_run;
    -- INJECTION arm, whole thing inside one subtransaction so the refusal unwinds it
    begin
      v_o := public.fn_kernel_open_step(jsonb_build_object(
        'run_id', v_run, 'step_id','W04-S07','owner_role_id','customer_onboarding',
        'opened_because','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure with a mandatory step open'));
      select t.task_id into v_task from public.phase_c_task t where t.run_id=v_run and t.step_id='W04-S07' order by t.task_id limit 1;
      perform public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
        'reviewer_role_id','customer_success_director','decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure probe'));
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id',(v_o->>'step_run_id')::bigint,'actor_role_id','customer_onboarding',
        'outcome','pass','idempotency_key','m03:s2inj:'||v_run,
        'inputs', jsonb_build_object('mode','closure with a blocker open'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','closure')),
        'acceptance_criteria','the closure blocker branch is exercised',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
      v_out := v_out || 'INJ=CLOSED ';
    exception when others then
      v_out := v_out || format('INJ=%s cb=%s mand=%s ', SQLSTATE,
        position('k3_closure_blocked' in SQLERRM)>0, position('mandatory_steps_never_executed' in SQLERRM)>0);
    end;
    select count(*) into v_nsr2 from public.phase_c_workflow_step_run where run_id=v_run;
    v_out := v_out || format('srs %s->%s closed_at=%s state=%s ', v_nsr, v_nsr2,
      (select closed_at is not null from public.phase_c_workflow_run where run_id=v_run),
      (select state from public.phase_c_workflow_run where run_id=v_run));
    -- CONTROL arm: the one thing that differs is that the mandatory step is completed first
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,'actor_role_id','customer_onboarding',
      'outcome','pass','idempotency_key','m03:s2c6:'||v_run,
      'inputs', jsonb_build_object('mode','control'),
      'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - handoff note'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
      'acceptance_criteria','every earlier mandatory step is executed',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
    select step_run_id into v_s7 from public.phase_c_workflow_step_run where run_id=v_run and step_id='W04-S07' order by step_run_id limit 1;
    select t.task_id into v_task from public.phase_c_task t where t.run_id=v_run and t.step_id='W04-S07' order by t.task_id limit 1;
    perform public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
      'reviewer_role_id','customer_success_director','decision','approved',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure control'));
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_s7,'actor_role_id','customer_onboarding',
        'outcome','pass','idempotency_key','m03:s2ctl:'||v_run,
        'inputs', jsonb_build_object('mode','control'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
        'acceptance_criteria','the run closes','reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
      v_out := v_out || 'CTL=CLOSED ';
    exception when others then v_out := v_out || format('CTL=%s msg=%s ', SQLSTATE, left(SQLERRM,150)); end;
    v_out := v_out || format('closed_at=%s state=%s s7=%s ',
      (select closed_at is not null from public.phase_c_workflow_run where run_id=v_run),
      (select state from public.phase_c_workflow_run where run_id=v_run), v_s7);
  end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
