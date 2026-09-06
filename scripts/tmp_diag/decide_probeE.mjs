import { sql } from '../phase_b/lib/db.mjs';

const body = `
do $emit$
declare v_out text := ''; v_w jsonb; v_sub uuid; v text; v_n bigint; v_id bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-thirteen-probeE'));

  -- N5: does the outbound door screen a rendered body carrying a customer identity?
  begin
    v_w := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-n5-' || md5('pii'),'mock_case','success',
      'approved_payload_ref','zz-approved-v1',
      'approved_payload', jsonb_build_object('body','Dear supplier, contact Ahmad at zz.cust@example.invalid / 0501234567')));
    v_out := v_out || 'N5=' || left(v_w::text,120) || '|';
  exception when others then v_out := v_out || 'N5=REFUSED ' || left(SQLERRM,100) || '|'; end;

  -- PRIV-004 populations
  select count(*) into v_n from public.phase_c_system_execution; v_out := v_out || 'sysexec_rows=' || v_n || '|';
  select count(*) into v_n from public.phase_c_trace;            v_out := v_out || 'trace_rows=' || v_n || '|';
  select count(*) into v_n from public.inquiries;                v_out := v_out || 'inquiries=' || v_n || '|';
  select count(*) into v_n from public.phase_c_event_outbox;     v_out := v_out || 'outbox=' || v_n || '|';
  select count(*) into v_n from public.phase_c_workflow_step_run;v_out := v_out || 'steprun=' || v_n || '|';

  -- FIN-004: can this repository mint a real founder session without the founder acting?
  select f.auth_user_id into v_sub from public.phase_c_founder_identity f
   where f.identity='management@quotesdone.com' and f.active;
  begin
    v_w := public.fn_phase_c_founder_subject_bind(v_sub);
    v_out := v_out || 'bind=' || left(v_w::text,90) || '|';
  exception when others then v_out := v_out || 'bind=REFUSED ' || left(SQLERRM,90) || '|'; end;
  begin
    v := public.fn_phase_c_require_founder(null);
    v_out := v_out || 'require=' || left(v,60) || '|';
  exception when others then v_out := v_out || 'require=REFUSED ' || left(SQLERRM,80) || '|'; end;

  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;

try { await sql(body); console.log('did not raise'); }
catch (e) {
  const m = String(e.message); const a = m.indexOf('PROBE<<');
  console.log(a < 0 ? 'ERR: ' + m.slice(0, 2500) : m.slice(a + 7, m.indexOf('>>', a)).split('|').join('\n'));
}
