do $emit$
declare v_out text := ''; v_tr bigint; v_tr2 bigint; v_def text; v_p4 int; v_p5 int; v_plr int;
        v_task bigint; v_old bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-pt'));
  -- TRACE-003
  v_tr := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
    'subject_kind','task','subject_ref','zz-probe','actor_role_id','defect_probe','status','open'));
  begin
    update public.phase_c_trace set status='sealed' where trace_id=v_tr;
    v_out := v_out || 'T3INJ=accepted ';
  exception when others then
    v_out := v_out || format('T3INJ=%s ck=%s ', SQLSTATE, position('phase_c_trace_sealed_ck' in SQLERRM)>0);
  end;
  begin
    update public.phase_c_trace set status='sealed', sealed_at=now() where trace_id=v_tr;
    v_out := v_out || 'T3CTL=accepted ';
  exception when others then v_out := v_out || format('T3CTL=%s msg=%s ', SQLSTATE, left(SQLERRM,80)); end;
  -- TRACE-004(a) static ordering
  select pg_get_functiondef('public.fn_kernel_step_complete(jsonb)'::regprocedure) into v_def;
  v_p4  := position('4. CLAIM THE IDEMPOTENCY KEY' in v_def);
  v_p5  := position('fn_phase_c_trace_advance' in v_def);
  v_plr := position('idempotency key % is claimed and carries no result' in v_def);
  v_out := v_out || format('T4a claim@%s firsttrace@%s lostrace@%s tw@%s ', v_p4, v_p5, v_plr,
    position('fn_phase_c_trace_write' in v_def));
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
