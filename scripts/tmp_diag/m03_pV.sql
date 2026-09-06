do $emit$
declare v_out text := ''; v_tr bigint; v_n0 bigint; v_n1 bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-pv'));
  select count(*) into v_n0 from public.phase_c_trace;
  -- CONTROL: an OPEN system-execution trace with no execution row is an execution in flight
  begin
    v_tr := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution','subject_ref','zz.probe.component',
      'component_id','zz.probe.component','actor_role_id','defect_probe','status','open'));
    set constraints all immediate;
    v_out := v_out || format('CTL=silent trace=%s ', v_tr);
    set constraints all deferred;
  exception when others then
    v_out := v_out || format('CTL=%s msg=%s ', SQLSTATE, left(SQLERRM,110));
  end;
  -- INJECTION: the same trace SEALED, with no phase_c_system_execution row
  begin
    v_tr := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution','subject_ref','zz.probe.component',
      'component_id','zz.probe.component','actor_role_id','defect_probe','status','sealed'));
    set constraints all immediate;
    v_out := v_out || format('INJ=silent trace=%s ', v_tr);
    set constraints all deferred;
  exception when others then
    v_out := v_out || format('INJ=%s msg=%s ', SQLSTATE, left(SQLERRM,140));
  end;
  select count(*) into v_n1 from public.phase_c_trace;
  v_out := v_out || format('traces %s->%s ', v_n0, v_n1);
  raise exception 'PROBE<<%>>', v_out;
end $emit$;
