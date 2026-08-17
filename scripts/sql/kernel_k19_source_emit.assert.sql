-- K19 rehearsal. Every refusal path and both happy paths, against real registered sources.
do $k19r$
declare
  r_unreg text; r_monitor text; r_retired text; r_noref text; r_norun text;
  r_a jsonb; r_b jsonb; v_run bigint; v_out jsonb; v_bad bigint; v_lines text;
  v_runs_before bigint; v_runs_after bigint; v_fail bigint;
begin
  select count(*) into v_runs_before from public.phase_c_workflow_run;

  begin  perform public.fn_kernel_source_emit('no:such:source', '{"source_ref":"x"}'::jsonb);
         r_unreg := 'NOT REFUSED';
  exception when others then r_unreg := left(sqlerrm, 90); end;

  begin  perform public.fn_kernel_source_emit('cron:7', '{"source_ref":"x"}'::jsonb);
         r_monitor := 'NOT REFUSED';
  exception when others then r_monitor := left(sqlerrm, 90); end;

  begin  perform public.fn_kernel_source_emit('edge:voice_otp', '{"source_ref":"x"}'::jsonb);
         r_retired := 'NOT REFUSED';
  exception when others then r_retired := left(sqlerrm, 90); end;

  begin  perform public.fn_kernel_source_emit('edge:inquiry_intake', '{}'::jsonb);
         r_noref := 'NOT REFUSED';
  exception when others then r_noref := left(sqlerrm, 90); end;

  begin  perform public.fn_kernel_source_emit('edge:messages_api', '{"source_ref":"m1"}'::jsonb);
         r_norun := 'NOT REFUSED';
  exception when others then r_norun := left(sqlerrm, 110); end;

  -- class A, the whole way through: register -> trigger inbox -> workflow run
  r_a := public.fn_kernel_source_emit('edge:inquiry_intake', jsonb_build_object(
    'source_ref', 'ZZ-K19-INQ-1',
    'raw_payload', jsonb_build_object('inquiry_id','ZZ-K19-INQ-1','summary','K19 rehearsal')));

  -- class B, against the run class A just opened
  v_run := nullif(r_a->>'run_id','')::bigint;
  if v_run is not null then
    update public.kernel_signal_type set activation_state = 'active' where signal_type = 'clarification.response';
    r_b := public.fn_kernel_source_emit('edge:messages_api', jsonb_build_object(
      'source_ref', 'ZZ-K19-MSG-1', 'workflow_run_id', v_run,
      'raw_payload', jsonb_build_object('output', jsonb_build_object('status','ok','output','answered'))));
  end if;

  select count(*) into v_runs_after from public.phase_c_workflow_run;
  select count(*) into v_fail from public.kernel_adapter_failure;
  select count(*) into v_bad from public.fn_kernel_source_emit_state() where not ok;
  select string_agg(check_name || ' :: ' || actual, E'\n    ' order by check_name)
    into v_lines from public.fn_kernel_source_emit_state();

  raise exception E'REHEARSAL K19 (rolled back)\n'
    '  unregistered source .. %\n'
    '  read-only monitor .... %\n'
    '  retired source ....... %\n'
    '  no source_ref ........ %\n'
    '  signal with no run ... %\n'
    '  class A result ....... %\n'
    '  class B result ....... %\n'
    '  runs before / after .. % / %\n'
    '  adapter failures ..... %\n'
    '  failing checks ....... % (expect 0)\n    %',
    r_unreg, r_monitor, r_retired, r_noref, r_norun,
    left(coalesce(r_a::text,'(null)'), 420), left(coalesce(r_b::text,'(not attempted)'), 300),
    v_runs_before, v_runs_after, v_fail, v_bad, v_lines;
end
$k19r$;
