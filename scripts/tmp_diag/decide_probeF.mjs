import { sql } from '../lib/db.mjs';
const body = `
do $emit$
declare v_out text := ''; v_id bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-thirteen-probeF'));
  select trace_id into v_id from public.phase_c_system_execution order by trace_id limit 1;
  v_out := v_out || 'pick=' || coalesce(v_id::text,'(none)') || '|';
  begin
    delete from public.phase_c_system_execution where trace_id = v_id;
    v_out := v_out || 'DELsysexec=ACCEPTED|';
  exception when others then v_out := v_out || 'DELsysexec=' || left(SQLERRM,170) || '|'; end;
  begin
    perform set_config('kernel.maintenance_reason','decide probe: does a maintenance door exist here', true);
    delete from public.phase_c_system_execution where trace_id = v_id;
    v_out := v_out || 'DELsysexec_withreason=ACCEPTED|';
  exception when others then v_out := v_out || 'DELsysexec_withreason=' || left(SQLERRM,110) || '|'; end;
  select trace_id into v_id from public.phase_c_trace order by trace_id limit 1;
  begin
    delete from public.phase_c_trace where trace_id = v_id;
    v_out := v_out || 'DELtrace=ACCEPTED|';
  exception when others then v_out := v_out || 'DELtrace=' || left(SQLERRM,140) || '|'; end;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(body); console.log('did not raise'); }
catch (e) { const m=String(e.message); const a=m.indexOf('PROBE<<');
  console.log(a<0 ? 'ERR: '+m.slice(0,2500) : m.slice(a+7, m.indexOf('>>',a)).split('|').join('\n')); }
