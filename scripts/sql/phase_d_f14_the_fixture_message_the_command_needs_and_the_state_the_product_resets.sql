-- F14 - the fixture message the command needs, and the state the product resets
--
-- Two measured failures from the first drive with F12 and F13 on, and one generated catalogue.
--
-- (1) THE FOUNDER COMMAND FIXTURE HAD NO MESSAGE. public.founder_command.message_id carries a
--     foreign key to public.founder_command_message, which F12 did not know about; the fixture
--     refused with founder_command_message_id_fkey on every build and the six rules that resolve
--     founder_authority_ref went on refusing. The message row is created first, and its
--     founder_identity is the literal PHASE_D_FIXTURE_DO_NOT_PUBLISH -- deliberately a string that
--     resolves to nobody in public.phase_c_founder_identity, so no reader can mistake the fixture
--     for something the founder sent.
--
-- (2) THE PRODUCT RESETS THE STATE THE FACTORY ASKED FOR. The inquiry stage declares quote_ready,
--     public.phase_d_object_write_map maps inquiries.status <- state, and the row came out with
--     status 'open' -- because public.trg_inquiry_enrich is a BEFORE INSERT trigger and it sets the
--     status a NEW inquiry has. That is the product being right: a real inquiry IS created open and
--     BECOMES quote-ready. GATE-011 and BR-013 then refused, correctly, an inquiry that was not
--     quote-ready.
--
--     So the factory now does what reality does: creates the row, reads back the column the write
--     map points at the state, and if the product moved it, writes again through the SAME canonical
--     service to settle it. Two writes in the order real business activity uses them, not one write
--     that argues with a trigger. The second write is skipped when the readback already agrees, so
--     nothing is written twice for its own sake, and any refusal on the settle pass is recorded in
--     the manifest rather than swallowed.
--
-- (3) EVERY DECLARED INPUT KEY IS AN OBJECT. All 20 distinct required input keys across the 514
--     typed contracts are typed `object`; the first catalogue draft supplied founder_instruction as
--     a string and the step's own input contract rejected it for "wrong types" -- the contract
--     working. The catalogue rows below are generated FROM the schema table, so their type is the
--     declared one by construction rather than by my agreeing with it.

-- ================================================================================================
-- 1. THE MESSAGE, THEN THE COMMAND
-- ================================================================================================
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
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_founder_authority_fixture(jsonb) TO service_role;

INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('founder_command_message', 'fn_phase_d_founder_authority_fixture',
   'Creates the message row the Phase D fixture founder command needs, with founder_identity set to a literal that resolves to nobody, inside an audited fixture run and inside a transaction that is aborted.')
ON CONFLICT DO NOTHING;

-- ================================================================================================
-- 2. EVERY DECLARED INPUT KEY, TYPED BY ITS OWN CONTRACT
-- ================================================================================================
INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
SELECT
  'PDF-2' || lpad((row_number() over (order by k.key))::text, 3, '0'),
  1, null, null, 'CONTEXT_KEY', k.key,
  jsonb_build_object(
    'marker', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH',
    'note',   format('PHASE_D_FIXTURE_DO_NOT_PUBLISH — a fixture value for the declared input key "%s". It states nothing about the business.', k.key),
    'supplied_by', 'the committed Phase D fixture catalogue, through fn_phase_d_fixture_input, only inside a verified fixture context'),
  'object', null,
  format('object; %s of the 257 typed input contracts declare "%s" and every one of them types it as object', k.n, k.key),
  format('the step resolves "%s" instead of refusing with pd_input_unresolved, and its own input contract accepts the type', k.key),
  'Never treat any value in this object as a fact about the company, a customer, a supplier or the founder.',
  null
FROM (
  select x.key, count(*) n
    from public.phase_d_handler_schema s, lateral unnest(s.required_keys) x(key)
   where s.schema_kind = 'input' and s.field_types->>x.key = 'object'
   group by x.key
) k
ON CONFLICT (fixture_id) DO NOTHING;

-- The string draft of founder_instruction is retired: its own step's input contract types it as an
-- object and rejected the string for "wrong types", which is the contract working.
DELETE FROM public.phase_d_fixture_catalogue
 WHERE fixture_id = 'PDF-0063'
   AND exists (select 1 from public.phase_d_fixture_catalogue c2
                where c2.field_key = 'founder_instruction' and c2.value_kind = 'object');
