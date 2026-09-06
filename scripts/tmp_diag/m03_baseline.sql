do $emit$
declare v_out text; v_n int;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','m03-baseline'));
  create temp table _b on commit drop as
    select * from public.fn_phase_d_run_injected_defects();
  select count(*) into v_n from _b;
  select string_agg(replace(defect_id,'PD-','') || ':' ||
      case status when 'REFUSED_AS_REQUIRED' then 'R' when 'NOT_REFUSED' then 'F'
                  when 'NOT_RUN' then 'N' when 'NOT_DISCRIMINATED' then 'D'
                  when 'EXEMPT' then 'X' else '?'||status end, ',' order by defect_id)
    into v_out from _b;
  raise exception 'PROBE<<n=% | %>>', v_n, v_out;
end $emit$;
