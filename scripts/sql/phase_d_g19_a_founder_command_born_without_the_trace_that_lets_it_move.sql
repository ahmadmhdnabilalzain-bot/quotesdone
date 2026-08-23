-- G19 — a founder command born without the trace that lets it ever move
--
-- G05 made a founder-gated run arise FROM the fixture founder command, which is how a
-- founder-instructed run really starts and is what let BR-003 resolve. What it did not do is give
-- that command the root trace the real router opens one statement later.
--
-- fn_founder_command_trace_guard is explicit about the deal: a command may be BORN at 'received'
-- with no trace, and 'received -> interpreting' is the single move allowed without one, "the
-- transition the router makes in order to open the trace, in the same transaction, on the very next
-- statement". Every state after that must carry it. TRACE-FOUNDER-COMMAND declares
-- trace_required=YES.
--
-- fn_phase_d_founder_authority_fixture inserted at 'received' and stopped. So the command existed,
-- satisfied "a founder command is behind this run", and could never legally leave the state it was
-- created in. MEASURED, driving W09's failure path with the step deliberately left open:
--
--     founder_command 11676: cannot leave received without a root trace   (23514)
--
-- and the same refusal on every founder-gated workflow's failure and cancellation arm. The four-mode
-- result reported failure path exercised 6 of 30 and cancellation 13 of 30 largely because of it.
--
-- THE GUARD IS RIGHT AND IS NOT TOUCHED. What was wrong is a fixture that created half of a founder
-- command: the row without the evidence root that makes it a command rather than a record. The
-- fixture now opens the root trace through fn_phase_c_trace_write under the TRACE-FOUNDER-COMMAND
-- policy and stamps it on the command, exactly as the router does, so the kernel can move it for
-- the same reasons it moves a real one.
--
-- IT STILL AUTHORISES NOTHING. founder_initiated_only false, refund_semantics false,
-- founder_identity resolving to nobody, and founder AUTHENTICATION remains fn_phase_c_require_founder
-- reading a verified auth subject. A trace is evidence of what happened, not permission.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_founder_authority_fixture. No DDL.
CREATE OR REPLACE FUNCTION public.fn_phase_d_founder_authority_fixture(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run   bigint := public.fn_phase_d_fixture_context();
  v_label text   := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_id    bigint;
  v_msg   bigint;
  v_text  text;
  v_trace bigint;   -- G19: the root trace the guard requires before the command may move
begin
  if v_run is null then
    raise exception 'fn_phase_d_founder_authority_fixture: no verified Phase D fixture context. A founder command fixture exists only inside an audited fixture run, inside a transaction that is aborted. (pd_fixture_no_test_context)'
      using errcode = '42501';
  end if;
  if v_label is null then
    raise exception 'fn_phase_d_founder_authority_fixture: label is required (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;

  v_text := format('PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D fixture command for run %s (%s). '
                || 'This is not an instruction from the founder. It exists so that the six rules '
                || 'which resolve founder_authority_ref against public.founder_command have a row '
                || 'to resolve, and it is created inside a transaction that is aborted.',
                   v_run, v_label);

  -- founder_identity is DELIBERATELY a string that resolves to nobody. E39's finding was that a
  -- guard authenticating a string is not authenticating an actor; writing the founder's real
  -- identity here would be the same mistake made on purpose.
  insert into public.founder_command_message
    (founder_identity, raw_text, raw_text_hash, client_idempotency_key, channel)
  values ('PHASE_D_FIXTURE_DO_NOT_PUBLISH',
          v_text,
          encode(sha256(convert_to(v_text,'UTF8')),'hex'),
          format('phase_d_fixture:%s:%s', v_run, v_label),
          'phase_d_fixture')
  returning message_id into v_msg;

  insert into public.founder_command
    (message_id, intent_id, outcome, command_owner_role_id, state, priority, primary_role_id,
     founder_initiated_only, refund_semantics)
  values (v_msg,
          format('PHASE_D_FIXTURE_DO_NOT_PUBLISH:%s', v_label),
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture founder command. It is not an instruction from the founder, it authorises nothing, and it is created inside a transaction that is aborted.',
          'chief_of_staff',
          'received',
          'low',
          'chief_of_staff',
          false,
          false)
  returning command_id into v_id;

  -- G19. THE ROOT TRACE, OPENED THE WAY THE ROUTER OPENS IT.
  -- Without this the command is stuck at 'received' for the rest of its life:
  -- fn_founder_command_trace_guard refuses every later transition with "cannot leave received
  -- without a root trace", and that refusal is correct. The command is created at received above
  -- (the one state the guard allows trace-less at birth) and the trace is stamped on it here, in
  -- the same transaction, which is the sequence the guard's own comment describes.
  v_trace := public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
    'subject_kind',   'founder_command',
    'subject_ref',    v_id::text,
    'command_id',     v_id,
    'actor_role_id',  'chief_of_staff',
    'system_actor_id','fn_phase_d_founder_authority_fixture',
    'state_before',   '',
    'state_after',    'received',
    'status',         'open',
    'evidence_refs',  jsonb_build_array(jsonb_build_object(
      'phase_d_fixture_run', v_run, 'label', v_label,
      'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — the root trace of a Phase D fixture founder command. It records that this command exists inside an aborted fixture transaction and authorises nothing.'))));

  update public.founder_command set trace_id = v_trace where command_id = v_id;

  perform public.fn_phase_d_scenario_record_write(jsonb_build_object(
    'fixture_id',        'PDS-founder_authority',
    'fixture_version',   1,
    'source_checksum',   encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'object_id',         'founder_command_fixture',
    'business_key',      v_id::text,
    'owner_ref',         'chief_of_staff',
    'ownership_scope',   'COMPANY',
    'state',             'received',
    'canonical_relation','public.founder_command',
    'canonical_service', 'fn_phase_d_founder_authority_fixture',
    'result_reference',  format('public.founder_command:command_id=%s', v_id),
    'contributes_ref',   'founder_authority_ref',
    'contributes_kind',  'RESULT_KEY',
    'contributed_value', format('founder_command:%s', v_id),
    'expected_effect',   'BR-003, BR-021..BR-024 and BR-043 resolve founder_authority_ref against public.founder_command and find this row. It authorises nothing: founder AUTHENTICATION is fn_phase_c_require_founder, which reads a verified auth subject and never this table.'));

  return jsonb_build_object('ok', true, 'command_id', v_id, 'message_id', v_msg,
    'founder_authority_ref', format('founder_command:%s', v_id),
    'founder_identity_on_the_message', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — resolves to nobody',
    'founder_initiated_only', false, 'refund_semantics', false,
    'note','a fixture command; it satisfies "a founder command exists" and nothing else');
end
$function$

