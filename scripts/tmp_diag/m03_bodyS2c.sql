  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := format('held=%s at=%s ', v_srid, v->>'held_step_id');
  declare v_run bigint := (v->>'run_id')::bigint; v_c bigint; v_task bigint; v_r jsonb; v_s7 bigint;
  begin
    perform set_config('app.phase_d_hold_step','W04-S07', true);
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
      'outcome','pass','idempotency_key','m03:s2c6:'||v_run,
      'inputs', jsonb_build_object('mode','control'),
      'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - handoff note'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
      'acceptance_criteria','the last mandatory step before closure is completed',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
    select step_run_id into v_s7 from public.phase_c_workflow_step_run where run_id=v_run and step_id='W04-S07' order by step_run_id limit 1;
    v_out := v_out || format('s7=%s state=%s runstate=%s ', v_s7,
      (select state from public.phase_c_workflow_step_run where step_run_id=v_s7),
      (select state from public.phase_c_workflow_run where run_id=v_run));
    if v_s7 is null then
      v_out := v_out || 'no S07 opened ';
    else
      select t.task_id into v_task from public.phase_c_task t where t.run_id=v_run and t.step_id='W04-S07' order by t.task_id limit 1;
      v_r := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
        'reviewer_role_id','customer_success_director','decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure control'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
          'step_run_id', v_s7,
          'actor_role_id',(select accountable_role_id from public.phase_b_workflow_step where step_id='W04-S07'),
          'outcome','pass','idempotency_key','m03:s2c7:'||v_run,
          'inputs', jsonb_build_object('mode','control'),
          'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
          'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
          'acceptance_criteria','the closure step closes the run',
          'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
        v_out := v_out || 'CTL=CLOSED ';
      exception when others then
        v_out := v_out || format('CTL=%s msg=%s ', SQLSTATE, left(SQLERRM,200));
      end;
    end if;
    select count(*) into v_c from public.phase_c_workflow_run where run_id=v_run and closed_at is not null;
    v_out := v_out || format('closed_at_set=%s runstate=%s ', v_c,
      (select state from public.phase_c_workflow_run where run_id=v_run));
    v_out := v_out || format('succ_S06=%s succ_S07=%s ',
      (select kind from public.fn_kernel_step_successor('W04-S06')),
      (select kind from public.fn_kernel_step_successor('W04-S07')));
  end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
