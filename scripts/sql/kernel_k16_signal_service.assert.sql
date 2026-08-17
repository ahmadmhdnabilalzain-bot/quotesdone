-- K16 rehearsal. Exercises every disposition and every refusal path against a REAL run, inside the
-- aborted transaction — because a table and a function that have never been called prove nothing.
do $k16r$
declare
  v_run bigint; v_out jsonb; v_start jsonb;
  r_noreg jsonb; r_inactive jsonb; r_norun jsonb; r_norunid jsonb; r_wrongwf jsonb;
  r_attach jsonb; r_dup jsonb; r_nooutput jsonb; r_complete jsonb; r_terminal jsonb;
  v_runs_before bigint; v_runs_after bigint; v_step text; v_bad bigint;
begin
  select count(*) into v_runs_before from public.phase_c_workflow_run;

  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id','W14','business_object_id','ZZ-REHEARSAL-K16','source_kind','autonomous',
    'source_ref','rehearsal:k16','requested_by','kernel:rehearsal'));
  v_run := (v_start->>'run_id')::bigint;

  -- unregistered signal type
  r_noreg := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a1','workflow_run_id',v_run,
    'signal_type','no.such.signal','requested_by','kernel:rehearsal'));

  -- registered but inactive (every seeded row lands inactive on purpose)
  r_inactive := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a2','workflow_run_id',v_run,
    'signal_type','sla.breach','requested_by','kernel:rehearsal'));

  update public.kernel_signal_type set activation_state = 'active';

  -- no workflow_run_id at all
  r_norunid := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a3','signal_type','sla.breach',
    'requested_by','kernel:rehearsal'));

  -- a run that does not exist
  r_norun := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a4','workflow_run_id', 999999999,
    'signal_type','sla.breach','requested_by','kernel:rehearsal'));

  -- a signal declared for W14 sent to... this IS a W14 run, so send a W14-only signal to a run of
  -- another workflow instead. Use the wrong-workflow path by re-declaring the type.
  update public.kernel_signal_type set workflow_id = 'W05' where signal_type = 'sla.breach';
  r_wrongwf := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a5','workflow_run_id',v_run,
    'signal_type','sla.breach','requested_by','kernel:rehearsal'));
  update public.kernel_signal_type set workflow_id = null where signal_type = 'sla.breach';

  -- ATTACH_ONLY, the happy path
  r_attach := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a6','workflow_run_id',v_run,
    'signal_type','sla.breach','requested_by','kernel:rehearsal',
    'payload', jsonb_build_object('breached_at','2026-08-17T00:00:00Z')));

  -- the same signal again: must return the first decision and do nothing twice
  r_dup := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a6','workflow_run_id',v_run,
    'signal_type','sla.breach','requested_by','kernel:rehearsal',
    'payload', jsonb_build_object('breached_at','2026-08-17T00:00:00Z')));

  -- COMPLETE_STEP with no output — must be refused, never defaulted
  r_nooutput := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a7','workflow_run_id',v_run,
    'signal_type','clarification.response','requested_by','kernel:rehearsal',
    'payload', jsonb_build_object('note','I answered')));

  -- COMPLETE_STEP with a real output — must actually move the run
  select step_id into v_step from public.phase_c_workflow_step_run
   where run_id = v_run and state = 'active' order by step_run_id limit 1;
  r_complete := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a8','workflow_run_id',v_run,
    'signal_type','clarification.response','requested_by','kernel:rehearsal',
    'payload', jsonb_build_object(
      'inputs', jsonb_build_object('answer','yes'),
      'output', jsonb_build_object('status','ok','output','clarification answered'))));

  -- a cancelled run must refuse further signals
  perform public.fn_kernel_cancel(jsonb_build_object(
    'subject_kind','workflow_run','subject_ref', v_run::text, 'op','cancel',
    'reason','K16 rehearsal: proving a terminal run refuses signals','actor','kernel:rehearsal'));
  r_terminal := public.fn_kernel_signal_submit(jsonb_build_object(
    'source_type','probe','source_id','a9','workflow_run_id',v_run,
    'signal_type','sla.breach','requested_by','kernel:rehearsal'));

  select count(*) into v_runs_after from public.phase_c_workflow_run;
  select count(*) into v_bad from public.fn_kernel_signal_state() where not ok;

  raise exception E'REHEARSAL K16 (rolled back)\n'
    '  runs before / after ........ % / %   (signals must create 0 runs; 1 is the one this probe started)\n'
    '  step the signal completed .. %\n'
    '  unregistered type .......... %\n'
    '  inactive type .............. %\n'
    '  no workflow_run_id ......... %\n'
    '  run does not exist ......... %\n'
    '  wrong workflow ............. %\n'
    '  ATTACH_ONLY ................ %\n'
    '  same signal twice .......... %\n'
    '  COMPLETE_STEP no output .... %\n'
    '  COMPLETE_STEP with output .. %\n'
    '  signal to a cancelled run .. %\n'
    '  fn_kernel_signal_state failing checks % (expect 0)',
    v_runs_before, v_runs_after, v_step,
    r_noreg->>'reason', r_inactive->>'reason', r_norunid->>'reason', r_norun->>'reason',
    r_wrongwf->>'reason',
    (r_attach->>'status') || ' trace=' || coalesce(r_attach->>'trace_id','-'),
    (r_dup->>'status') || ' duplicate=' || coalesce(r_dup->>'duplicate','-'),
    r_nooutput->>'reason',
    (r_complete->>'status') || ' step=' || coalesce(r_complete->>'step_id','-')
      || ' ok=' || coalesce(r_complete->>'ok','-'),
    r_terminal->>'reason',
    v_bad;
end
$k16r$;
