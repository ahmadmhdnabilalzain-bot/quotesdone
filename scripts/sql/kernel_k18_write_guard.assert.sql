-- K18 rehearsal. Proves the guard REFUSES a direct write and still lets the whole kernel work —
-- both, in one aborted transaction. A guard that only refuses is an outage; a guard that only
-- permits is decoration.
do $k18r$
declare
  v_direct text := 'NOT REFUSED — THE GUARD DID NOT FIRE';
  v_maint  text := 'not attempted';
  v_walk   text := 'not attempted';
  v_run bigint; v_out jsonb; r record; v_i int := 0; v_path text := ''; v_state text;
  v_bad bigint; v_lines text; v_maint_rows bigint;
begin
  -- 1. a direct insert, exactly as a new Edge Function or a stray migration would write it
  begin
    insert into public.phase_c_workflow_run
      (workflow_id, business_object_id, object_version, start_event, accountable_role_id, state, dedupe_key)
    values ('W14','ZZ-K18-DIRECT',1,'x','quote_evaluation','active','ZZ-K18-DIRECT:1');
  exception when others then
    v_direct := left(sqlerrm, 150);
  end;

  -- 2. the audited maintenance door, which must work AND leave a row
  begin
    set local kernel.maintenance_reason = 'K18 rehearsal: proving the maintenance door is open to the table owner and recorded';
    insert into public.phase_c_workflow_run
      (workflow_id, business_object_id, object_version, start_event, accountable_role_id, state, dedupe_key)
    values ('W14','ZZ-K18-MAINT',1,'x','quote_evaluation','active','ZZ-K18-MAINT:1');
    v_maint := 'permitted';
  exception when others then
    v_maint := 'REFUSED: ' || left(sqlerrm, 120);
  end;
  select count(*) into v_maint_rows from public.kernel_maintenance_write;
  set local kernel.maintenance_reason = '';

  -- 3. the kernel itself must still run end to end, through the guard, untouched
  v_out := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id','W14','business_object_id','ZZ-K18-KERNEL','source_kind','autonomous',
    'source_ref','rehearsal:k18','requested_by','kernel:rehearsal'));
  v_run := (v_out->>'run_id')::bigint;
  loop
    v_i := v_i + 1; exit when v_i > 40;
    select hr.handoff_run_id, hr.receiving_role_id into r from public.phase_c_handoff_run hr
     where hr.run_id = v_run and hr.status = 'open' order by hr.handoff_run_id limit 1;
    if r.handoff_run_id is not null then
      perform public.fn_kernel_handoff_accept(jsonb_build_object(
        'handoff_run_id', r.handoff_run_id, 'actor_role_id', r.receiving_role_id, 'outcome','accept',
        'packet', jsonb_build_object('business_object_id','ZZ-K18-KERNEL','object_version',1,
          'output','k18','evidence_refs',jsonb_build_array('rehearsal:k18'),'requested_action','continue')));
      continue;
    end if;
    select sr.step_run_id, sr.step_id, sr.accountable_role_id, sr.reviewer_role_id into r
      from public.phase_c_workflow_step_run sr
     where sr.run_id = v_run and sr.state = 'active' order by sr.step_run_id limit 1;
    exit when r.step_run_id is null;
    v_path := v_path || case when v_path = '' then '' else '->' end || r.step_id;
    if r.reviewer_role_id is not null then
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', (select t.task_id from public.phase_c_task t
                     where t.run_id = v_run and t.step_id = r.step_id order by t.task_id desc limit 1),
        'reviewer_role_id', r.reviewer_role_id, 'decision','approved',
        'reason','K18 rehearsal: the review path must still work through the guard'));
    end if;
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', r.step_run_id, 'actor_role_id', r.accountable_role_id, 'outcome','pass',
      'idempotency_key','rehearsal:k18:'||r.step_id, 'reason','K18 rehearsal',
      'inputs', jsonb_build_object('a',1),
      'output', jsonb_build_object('status','ok','output','k18'), 'evidence_ref','rehearsal:k18'));
  end loop;
  select state into v_state from public.phase_c_workflow_run where run_id = v_run;
  v_walk := v_path || '  run=' || v_state;

  select count(*) into v_bad from public.fn_kernel_write_guard_state() where not ok;
  select string_agg(check_name || ' :: ' || actual, E'\n    ' order by check_name)
    into v_lines from public.fn_kernel_write_guard_state();

  raise exception E'REHEARSAL K18 (rolled back)\n'
    '  direct insert ........ %\n'
    '  maintenance door ..... %  (rows recorded: %)\n'
    '  kernel walk .......... %\n'
    '  failing checks ....... % (expect 0)\n    %',
    v_direct, v_maint, v_maint_rows, v_walk, v_bad, v_lines;
end
$k18r$;
