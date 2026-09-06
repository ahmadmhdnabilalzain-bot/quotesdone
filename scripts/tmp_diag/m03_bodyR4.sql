  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_out := format('held=%s ', v_srid);
  declare v_run bigint := (v->>'run_id')::bigint; v_task bigint; v_r jsonb; v_s0 int; v_s1 int; v_s2 int;
          v_trace bigint;
  begin
    select t.task_id into v_task from public.phase_c_task t where t.run_id=v_run and t.step_id='W04-S04' order by t.task_id limit 1;
    select count(*) into v_s0 from public.phase_c_workflow_step_run where run_id=v_run and step_id='W04-S05';
    v_r := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
      'reviewer_role_id','compliance_and_privacy_officer','decision','rejected',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the output is rejected'));
    v_out := v_out || format('rej_ok=%s rej_trace=%s ', v_r->>'ok', v_r->>'trace_id');
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid,
        'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
        'outcome','pass','idempotency_key','m03:r4inj:'||v_srid,
        'inputs', jsonb_build_object('mode','rejected output pushed forward'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - rejected output'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','rejected')),
        'acceptance_criteria','a rejected output must not progress',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
      v_out := v_out || 'INJ=PROGRESSED ';
    exception when others then
      v_out := v_out || format('INJ=%s vm=%s ', SQLSTATE, position('k3_reviewer_verdict_missing' in SQLERRM)>0);
    end;
    select count(*) into v_s1 from public.phase_c_workflow_step_run where run_id=v_run and step_id='W04-S05';
    v_r := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
      'reviewer_role_id','compliance_and_privacy_officer','decision','approved',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the same output is approved'));
    v_trace := (v_r->>'trace_id')::bigint;
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid,
        'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_srid),
        'outcome','pass','idempotency_key','m03:r4ctl:'||v_srid,
        'inputs', jsonb_build_object('mode','approved output progresses'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH - approved output'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','approved')),
        'acceptance_criteria','an approved output progresses',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH','object_version',1));
      v_out := v_out || 'CTL=PROGRESSED ';
    exception when others then
      v_out := v_out || format('CTL=%s msg=%s ', SQLSTATE, left(SQLERRM,120));
    end;
    select count(*) into v_s2 from public.phase_c_workflow_step_run where run_id=v_run and step_id='W04-S05';
    v_out := v_out || format('succ %s/%s/%s trace=%s ', v_s0, v_s1, v_s2, v_trace);
    -- REV-005 on the sealed verdict trace
    begin
      update public.phase_c_trace set evidence_refs = evidence_refs || '[{"tampered":true}]'::jsonb where trace_id=v_trace;
      v_out := v_out || 'EDIT=accepted ';
    exception when others then
      v_out := v_out || format('EDIT=%s ao=%s ', SQLSTATE, position('append-only' in SQLERRM)>0);
    end;
    v_out := v_out || format('sealed_at_set=%s ', (select sealed_at is not null from public.phase_c_trace where trace_id=v_trace));
    declare v_sup bigint;
    begin
      v_sup := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task','subject_ref',v_task::text,'task_id',v_task,'actor_role_id','defect_probe','status','sealed'));
      update public.phase_c_trace set superseded_by = v_sup where trace_id=v_trace;
      v_out := v_out || format('SUPER=accepted->%s ', v_sup);
    exception when others then v_out := v_out || format('SUPER=%s msg=%s ', SQLSTATE, left(SQLERRM,90)); end;
  end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
