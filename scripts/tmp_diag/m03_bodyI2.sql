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
