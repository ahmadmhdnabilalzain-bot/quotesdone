-- F12 - a founder authority fixture that cannot authorise anything
--
-- BR-003, BR-021, BR-022, BR-023, BR-024 and BR-043 all resolve `founder_authority_ref` the same
-- way: `exists (select 1 from public.founder_command fc where 'founder_command:' || fc.command_id
-- = v_txt)`. E28 and E29 made them do that precisely so that a founder-reserved decision needs the
-- founder's actual decision "and not a string in its shape". A Phase D run has no founder command
-- behind it, so those six rules refuse -- correctly, and on every founder-gated step in the estate.
--
-- The founder's ruling of 21 Aug 2026 lists, among the objects the scenario factory must support,
-- "founder refund decision fixture where required". This file is the narrowest thing that satisfies
-- that sentence, and the rest of this comment is about what it deliberately cannot do.
--
-- WHAT IT IS. A row in public.founder_command, created at state 'received' -- the one state the
-- trace guard allows a command to be born in with no trace -- with intent_id, outcome and priority
-- all carrying PHASE_D_FIXTURE_DO_NOT_PUBLISH, inside a transaction that is aborted.
--
-- WHAT IT IS NOT, AND THIS IS THE PART THAT MATTERS.
--
--   * It is NOT founder authentication. E39 recorded the open finding that
--     fn_phase_c_require_founder resolves a caller-supplied string; F14 closes that with a verified
--     Supabase Auth subject. A fixture command satisfies "a founder command exists"; it does not
--     and cannot satisfy "the founder is on this call". The two are different questions and after
--     F14 they are answered by different mechanisms.
--
--   * It CANNOT authorise a refund. fn_refund_decide goes through fn_phase_c_require_founder, which
--     after F14 needs a verified auth subject that resolves to an enabled founder identity. No
--     fixture can produce one. The founder's standing rule -- every refund needs him, at any amount
--     -- is untouched by this file, and the control that enforces it does not read founder_command.
--
--   * It CANNOT exist in production. fn_phase_d_founder_authority_fixture refuses unless
--     fn_phase_d_fixture_context() verifies an hmac over the current txid keyed by a secret no role
--     can SELECT (F01). Outside an audited fixture run it raises 42501 before it reads anything.
--
--   * It CANNOT be committed. It is created by the scenario factory, which runs only inside a
--     transaction that ends in a raise, and fn_phase_d_fixture_residue() counts what is left.
--
-- WHY A DEDICATED SERVICE RATHER THAN fn_phase_d_object_write. public.founder_command is not one of
-- the 56 registered Phase D business objects -- the Phase B baseline is frozen and this file does
-- not add a 57th. So the write needs its own canonical service, and it gets one, with the same
-- three properties every canonical service here has: it is the only routine with write authority
-- for the table it writes, it refuses without the protected context, and it records what it did in
-- the evidence manifest.

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
begin
  if v_run is null then
    raise exception 'fn_phase_d_founder_authority_fixture: no verified Phase D fixture context. A founder command fixture exists only inside an audited fixture run, inside a transaction that is aborted. (pd_fixture_no_test_context)'
      using errcode = '42501';
  end if;
  if v_label is null then
    raise exception 'fn_phase_d_founder_authority_fixture: label is required (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;

  -- message_id is NOT NULL and carries no foreign key; the fixture uses the fixture run so the row
  -- points at its own audit trail rather than at a message that does not exist.
  v_msg := v_run;

  insert into public.founder_command
    (message_id, intent_id, outcome, command_owner_role_id, state, priority, primary_role_id,
     founder_initiated_only, refund_semantics)
  values (v_msg,
          format('PHASE_D_FIXTURE_DO_NOT_PUBLISH:%s', v_label),
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture founder command. It is not an instruction from the founder, it authorises nothing, and it is created inside a transaction that is aborted.',
          'chief_of_staff',                         -- founder_command_owner_ck allows only this
          'received',                               -- the one state a command may be born in trace-less
          'low',
          'chief_of_staff',
          false,                                    -- NOT founder-initiated: it did not come from him
          false)                                    -- NOT refund semantics: it can never touch money
  returning command_id into v_id;

  perform public.fn_phase_d_scenario_record_write(jsonb_build_object(
    'fixture_id',        'PDS-founder_authority',
    'fixture_version',   1,
    'source_checksum',   encode(sha256(convert_to(format('founder_command:%s:%s', v_label, v_id),'UTF8')),'hex'),
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

  return jsonb_build_object('ok', true, 'command_id', v_id,
    'founder_authority_ref', format('founder_command:%s', v_id),
    'founder_initiated_only', false, 'refund_semantics', false,
    'note','a fixture command; it satisfies "a founder command exists" and nothing else');
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) IS
  'THE ONLY ROUTINE THAT CREATES A PHASE D FIXTURE FOUNDER COMMAND. Refuses without a verified '
  'Phase D fixture context, writes the row at state received with founder_initiated_only false and '
  'refund_semantics false, and records it in the evidence manifest. It satisfies the six rules that '
  'ask whether a founder command EXISTS. It cannot authenticate the founder and it cannot authorise '
  'a refund: those go through fn_phase_c_require_founder, which reads a verified auth subject (F12).';

INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('founder_command', 'fn_phase_d_founder_authority_fixture',
   'Creates the Phase D fixture founder command inside an audited fixture run and inside a transaction that is aborted. Marked PHASE_D_FIXTURE_DO_NOT_PUBLISH, founder_initiated_only false, refund_semantics false.')
ON CONFLICT DO NOTHING;

-- ---- the input key W01-S01 declares and nothing in the estate holds ----------------------------
INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
VALUES
('PDF-0063',1,null,null,'CONTEXT_KEY','founder_instruction',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — a fixture instruction standing in for the founder''s. It says nothing about the business and directs nothing."','text',null,
 'free text; the step declares founder_instruction as an input and no relation in this estate holds one',
 'the step resolves its declared input instead of refusing with pd_input_unresolved',
 'Never act on. It is not an instruction from the founder and never was.',null),
('PDF-0064',1,null,null,'CONTEXT_KEY','commercial_policy_change',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — no commercial term is changed by this fixture."','text',null,
 'free text naming the proposed commercial policy change, or stating that there is none',
 'BR-021..BR-024 become applicable and are then judged on the founder authority, not skipped',
 'Never treat as a pricing, fee or commercial term change.',null),
('PDF-0065',1,null,null,'CONTEXT_KEY','policy_exception',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — a fixture policy exception that touches no founder-reserved decision."','text',null,
 'free text naming the proposed policy exception',
 'BR-043 becomes applicable on the delegated arm and resolves the employee authority',
 'Never treat as an approved exception to any policy.',null)
ON CONFLICT (fixture_id) DO NOTHING;
