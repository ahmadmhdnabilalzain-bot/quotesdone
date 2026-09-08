// Aborted-transaction probe A: can each candidate injection be ATTEMPTED, and is there a control?
import { sql } from '../lib/db.mjs';

const body = `
do $emit$
declare v_out text := ''; v text; v_ok boolean; v_n bigint; v_w jsonb;
  v_overlay text := 'category_overlay_001_construction-materials-suppliers';
procedure_note text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','decide-thirteen-probeA'));

  -- A5 injection: overlay as accountable task owner
  begin
    insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
        acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    values ('probe','zz-a5', v_overlay, 'zz','zz','zz','routine','zz-a5-inj');
    v_out := v_out || 'A5inj=ACCEPTED|';
  exception when others then v_out := v_out || 'A5inj=' || left(SQLERRM,110) || '|'; end;

  -- A5 control: canonical role as accountable task owner
  begin
    insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
        acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    values ('probe','zz-a5c','compliance_and_privacy_officer','zz','zz','zz','routine','zz-a5-ctl');
    v_out := v_out || 'A5ctl=ACCEPTED|';
  exception when others then v_out := v_out || 'A5ctl=' || left(SQLERRM,110) || '|'; end;

  -- L3 injection: a non-refund subject into the founder approval path
  begin
    insert into public.founder_approval_request (command_id, action_class, subject_ref,
       prepared_by_role_id, amount_note, evidence, state)
    values (null,'policy_change','zz-l3','trust_and_safety_manager','','{}'::jsonb,'pending');
    v_out := v_out || 'L3inj=ACCEPTED|';
  exception when others then v_out := v_out || 'L3inj=' || left(SQLERRM,110) || '|'; end;
  begin
    insert into public.founder_approval_request (command_id, action_class, subject_ref,
       prepared_by_role_id, amount_note, evidence, state)
    values (null,'refund_decision','zz-l3c','trust_and_safety_manager','','{}'::jsonb,'pending');
    v_out := v_out || 'L3ctl=ACCEPTED|';
  exception when others then v_out := v_out || 'L3ctl=' || left(SQLERRM,110) || '|'; end;

  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;

try { await sql(body); console.log('did not raise'); }
catch (e) {
  const m = String(e.message); const a = m.indexOf('PROBE<<');
  console.log(a < 0 ? 'ERR: ' + m.slice(0, 1500) : m.slice(a + 7, m.indexOf('>>', a)).split('|').join('\n'));
}
