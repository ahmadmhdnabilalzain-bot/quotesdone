-- WHATSAPP ANSWERS THE INTENT THAT WAS REASONED, NOT THE WORDS IT MATCHED — decision point 7
-- (wa_inbound.intent_table, supabase/functions/_shared/decision_points.json).
-- Seat: it_engineer (shared platform); the decision belongs to customer_support. 23 Sep 2026,
-- founder_instruction 886-903 (ledger 890): "NO word matching anywhere: decisions by reasoning, never
-- keyword/regex/ilike on meaning."
--
-- WHY. fn_wa_answer (canonical: the_contact_template_gets_slots_like_every_other_fact.sql, MANIFEST line 1185;
-- read from production 23 Sep 2026 with pg_get_functiondef) picked the answer by walking public.wa_reply_intent
-- in sort order and taking the FIRST row one of whose match_patterns appeared as whole tokens in the body. So:
--   * "i want to buy something" met the greeting pattern 'hi' until word boundaries were bolted on;
--   * 'register' sits on both how_to_register (sort 46) and how_to_register_generic (48), so a buyer asking how
--     to register was always told the SUPPLIER's six requirements — the generic row could never be reached;
--   * "is it free?" matched nothing (no 'fee', no 'price'), while "no rain in the forecast, can we pour?" was
--     off_topic because 'rain' is in the weather list;
--   * contact_human — the founder's number — was released on 21 phrases; "is anyone there?" was not one.
--
-- WHAT THIS CHANGES.
--   * fn_wa_answer(p_from, p_body, p_intent) takes the intent REASONED upstream (wa_inbound: think() over the
--     active wa_reply_intent rows' labels, _shared/reasoned_channels.ts whatsappOptions) and reads the row BY KEY.
--     It never reads the body for meaning. match_patterns stays on the table, unread, as the record of what the
--     old match said. The body is still parsed for FORMAT only: the first run of 2+ digits is the id a by_id
--     question names.
--       p_intent null            -> not reasoned yet (the model hold): the honest unmatched reply, logged as held;
--       p_intent 'none' / no row -> reasoned, and no row fits: the unmatched reply, logged as backlog.
--   * fn_wa_route gains p_intent and passes it through; everything else in it is unchanged from
--     meaning_is_decided_by_reasoning_not_by_word_lists.sql (whose p_needs_person it keeps). The 4-argument
--     overload is dropped so no caller can reach the route without the reasoned intent parameter existing;
--     every existing call (4 positional arguments) still resolves, p_intent defaulting to null = held.
--
-- UNDER THE HOLD. p_intent is null, fn_wa_answer returns matched:false, fn_wa_route says a model is needed and
-- the model is held, so wa_inbound takes the road that needs no meaning (the approved FAQ, then the courteous
-- line + menu with the question filed as a knowledge gap) and files the MEANING in customer_support's queue;
-- the replay calls fn_wa_answer with the reasoned intent and sends the answer on WhatsApp
-- (_shared/reasoned_delivery.ts, surface wa_inbound.intent_table). Nobody is answered on a guess.
--
-- MEASURED 23 Sep 2026 (production, read-only): 16 wa_reply_intent rows, all active; the two DROPs below remove
-- fn_wa_answer(text,text) and fn_wa_route(text,text,boolean,boolean) (the latter defined by the pending
-- meaning_is_decided_by_reasoning_not_by_word_lists.sql).
--
-- Pending: scripts/sql/pending/whatsapp_answers_the_intent_that_was_reasoned_not_the_words_it_matched.txt.
-- Applies AFTER a_reasoned_answer_is_applied_by_its_own_surface.sql. Proved in one aborted transaction:
-- scripts/checks/decision_points_are_reasoned.test.mjs.

-- ── 1. fn_wa_answer: the reasoned intent, read by key ─────────────────────────────────────────────
-- DROP + CREATE grants EXECUTE to PUBLIC; the revoke and the service_role grant below close it again.
drop function if exists public.fn_wa_answer(text, text);
create function public.fn_wa_answer(p_from text, p_body text, p_intent text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_body     text := lower(btrim(coalesce(p_body, '')));
  v_intent   public.wa_reply_intent;
  v_reply    text;
  v_lead     record;
  v_lead_id  bigint;
  v_ident_k  text := 'unknown';
  v_ident_id text := null;
  v_id       bigint;
  v_missing  text;
  v_cfg      record;
  v_log      bigint;
begin
  if v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'Empty message.');
  end if;

  select standard_reveal_rate, supplier_free_count, supplier_reg_fee into v_cfg
    from public.pricing_config order by id limit 1;

  -- WHO IS ASKING. Identity gates every 'own_records' answer, so one supplier can never be told
  -- another supplier's business by sending a lucky message.
  v_lead_id := public.fn_wa_lead_id(p_from);
  if v_lead_id is not null then
    select * into v_lead from public.leads where id = v_lead_id;
    v_ident_k := 'lead'; v_ident_id := v_lead_id::text;
  end if;

  -- THE INTENT, AS REASONED. Read by key from the active rows; the body is not read for meaning.
  select * into v_intent from public.wa_reply_intent where active and intent_key = p_intent;

  -- NOTHING TO ANSWER FROM. An honest refusal that names what it would need. Never a guess.
  if not found then
    v_reply := public.fn_wa_unmatched_reply();
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, false, v_reply,
            case when p_intent is null
                 then 'Not reasoned yet (the model hold). The meaning waits in customer_support''s queue and is answered on WhatsApp when it is reasoned.'
                 else 'Reasoned: no intent row fits. This row is the backlog: a real question with no resolver.' end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', false, 'reply', v_reply, 'log_id', v_log,
                              'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end);
  end if;

  -- IDENTITY REQUIRED BUT UNKNOWN.
  if v_intent.requires_identity and v_lead_id is null then
    v_reply := 'I do not recognise this number yet, so I cannot look up your records. Reply with the '
            || 'email address you registered with, or REGISTER to start a new registration.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            'Intent reasoned but the sender is not a known party.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key, 'reply', v_reply, 'log_id', v_log);
  end if;

  v_reply := v_intent.answer_template;

  -- COMPANY SLOTS, the same for everyone.
  v_reply := replace(v_reply, '{{reveal_rate}}', coalesce(round(v_cfg.standard_reveal_rate * 100, 1)::text || '%', '3%'));
  v_reply := replace(v_reply, '{{free_count}}',  coalesce(v_cfg.supplier_free_count::text, '1000'));
  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));

  -- THE APPROVED PUBLIC CONTACT, read from the settings that say publication in their names -- never from
  -- founder_mobile. Absent, the slot ADMITS it rather than rendering an empty string.
  v_reply := replace(v_reply, '{{founder_public_phone}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
             '(no approved public contact is configured yet)'));
  v_reply := replace(v_reply, '{{founder_public_name}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_name'),
             'the owner'));

  -- OWN-RECORD SLOTS, read from this sender's row only.
  if v_lead_id is not null then
    v_reply := replace(v_reply, '{{company_name}}', coalesce(v_lead.company_name, 'your company'));
    v_reply := replace(v_reply, '{{reg_status}}',   coalesce(v_lead.registration_status, 'not started'));
    v_reply := replace(v_reply, '{{approval_status}}', coalesce(v_lead.approval_status, 'not yet reviewed'));

    -- The founder's mandatory six, not the ten the scoring view happens to list.
    select string_agg(m, ', ') into v_missing from (
      select 'a UAE mobile number' as m where coalesce(btrim(v_lead.phone_e164), '') = ''
      union all select 'an email address' where coalesce(btrim(v_lead.email), '') = ''
      union all select 'your trade licence' where coalesce(btrim(v_lead.license_doc_path), '') = ''
      union all select 'your company profile' where coalesce(btrim(v_lead.company_profile_doc_path), '') = ''
      union all select 'a signed copy of our terms' where coalesce(btrim(v_lead.signed_terms_path), '') = ''
    ) x;
    v_reply := replace(v_reply, '{{missing_list}}', coalesce(v_missing, 'nothing, your file is complete'));
    v_reply := replace(v_reply, '{{missing_line}}',
      case when v_missing is null then 'Your file is complete.'
           else 'We still need: ' || v_missing || '.' end);

    v_reply := replace(v_reply, '{{quote_count}}', '0');
    v_reply := replace(v_reply, '{{quote_detail}}',
      'No quotes yet. Once a buyer posts a request in your category you will be invited to quote.');
    v_reply := replace(v_reply, '{{awarded_count}}', '0');
    v_reply := replace(v_reply, '{{awarded_detail}}',
      'No jobs awarded yet. You will get a message here the moment one is.');
  end if;

  -- BY-ID LOOKUP. A number in the body is resolved against the real records, and returned ONLY to a
  -- party who appears on that record. The digits are FORMAT: the first run of two or more.
  if v_intent.scope = 'by_id' then
    v_id := nullif((regexp_match(v_body, '([0-9]{2,})'))[1], '')::bigint;
    if v_id is null then
      v_reply := 'Send me the number and I will look it up. For example: quote 1234, or job 5678.';
    else
      v_reply := replace(v_reply, '{{id_answer}}',
        'I could not find a record numbered ' || v_id || ' that you are a party to. Check the number, '
        || 'or reply HUMAN and the team will look into it.');
    end if;
  end if;

  insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply)
  values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply)
  returning id into v_log;

  return jsonb_build_object(
    'ok', true, 'matched', true, 'intent', v_intent.intent_key,
    'identity_kind', v_ident_k, 'identity_id', v_ident_id,
    'reply', v_reply, 'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning'
  );
end;
$$;
revoke execute on function public.fn_wa_answer(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_wa_answer(text, text, text) to service_role;
comment on function public.fn_wa_answer(text, text, text) is
  'Answers an inbound WhatsApp message from the live record, for the intent REASONED upstream (wa_inbound, think()) and passed as p_intent; null = held, never guessed. The body is not read for meaning. scripts/sql/whatsapp_answers_the_intent_that_was_reasoned_not_the_words_it_matched.sql';

-- ── 2. fn_wa_route: the reasoned intent passes through ────────────────────────────────────────────
drop function if exists public.fn_wa_route(text, text, boolean, boolean);
create function public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean default false,
  p_needs_person boolean default null, p_intent text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_det    jsonb;
  v_pack   jsonb;
  v_conv   record;
  v_needs  boolean;
  v_why    text;
  v_held   boolean;
  v_latin  boolean;
  v_trouble boolean;
  v_asked  boolean;
  v_person boolean;
  v_reason text;
  v_chain  jsonb;
  v_intent text;
  v_reply  text;
begin
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'), p_intent);
  v_pack := public.fn_wa_fact_pack(p_phone);
  v_intent := v_det->>'intent';
  v_reply  := v_det->>'reply';
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  -- Script detection picks the reply language; it is a format test, not a reading of meaning.
  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- The two ways a message needs a person. The second is REASONED (think() in wa_inbound): a complaint,
  -- a dispute, a refund demand, an accusation or a legal threat, however it is worded. Null = not yet
  -- reasoned (the hold): nobody is escalated on a guess; the message waits in customer_support's queue.
  v_asked   := coalesce(v_intent = 'contact_human', false);
  v_trouble := coalesce(p_needs_person, false);

  -- One decision now, not two. Needing a person and getting his number are the same thing here.
  v_person := v_asked or v_trouble;
  v_reason := case
    when v_asked   then 'They asked for a person, or asked who runs the company.'
    when v_trouble then 'This is a complaint, a dispute or an accusation. It needs a person whether '
                     || 'they asked for one or not, and the founder is the only person there is.'
    when p_needs_person is null then 'Whether this needs a person has not been reasoned yet (the model hold); '
                     || 'it is waiting in customer_support''s queue and nobody was escalated on a guess.'
    else 'Nobody asked for a person and nothing here needs one. A number given out by a machine '
      || 'cannot be taken back.' end;

  -- A complaint gets the number appended, because the escalation and the contact are the same act.
  if v_trouble and not v_asked then
    v_reply := v_reply || ' If you would rather speak to someone directly, call or message '
            || '+971 50 931 9355, which is answered by the owner.';
  end if;

  v_needs := false; v_why := 'A deterministic answer matched and the message is simple, so this turn costs nothing.';
  if p_has_audio then
    v_needs := true; v_why := 'The message is a voice note and must be transcribed before it can be answered.';
  elsif not v_latin then
    v_needs := true; v_why := 'The message is not in Latin script and the fixed answers exist only in English.';
  elsif v_intent in ('small_talk','off_topic','greeting','contact_human') then
    v_needs := false;
    v_why := format('Matched %s, which is answered completely without a model.', v_intent);
  elsif coalesce((v_det->>'matched')::boolean, false) = false then
    v_needs := true; v_why := 'No fixed answer matched. Wording varies, so this is the normal case rather than an exception.';
  elsif coalesce(v_conv.message_count, 0) >= 2 then
    v_needs := true; v_why := 'This is a continuing conversation; a fixed answer would ignore what came before.';
  elsif length(coalesce(p_body,'')) > 160 then
    v_needs := true; v_why := 'The message is long enough to contain more than one question.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rung', rung, 'model', model, 'kind', kind, 'rationale', rationale) order by rung), '[]'::jsonb)
    into v_chain
    from public.model_fallback_chain
   where purpose = 'whatsapp_conversation' and active;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    'model', case when v_needs then 'google/gemini-3-flash' else null end,
    'fallback_chain', case when v_needs then v_chain else null end,
    'on_model_failure',
      'Try each rung in order. Record model_wanted, model_used and fell_back on llm_calls for every '
   || 'attempt, so a fallback that becomes permanent is visible rather than quietly expensive. The '
   || 'final rung is the deterministic reply and it cannot fail.',
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      else 'google/gemini-3-flash first, by founder ruling. On failure claude-sonnet-5. On failure the '
        || 'deterministic reply. Every rung gets the same fact pack and the same boundaries.' end,

    -- One decision. Handing to a person and giving the number are the same act.
    'needs_a_person', v_person,
    'person_decided_by', case when v_asked then 'intent'
                              when p_needs_person is null then 'held: not yet reasoned'
                              else 'reasoning' end,
    'founder_number', case when v_person then (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')) else null end,
    'person_reason', v_reason,
    'opened_by', case when v_asked then 'they asked'
                      when v_trouble then 'complaint or dispute'
                      else null end,

    'action', case
      when v_needs and v_held  then 'send_deterministic_and_log_shortfall'
      when v_needs             then 'walk_fallback_chain_with_fact_pack'
      else                          'send_deterministic' end,

    'transcription_gap', case when p_has_audio
      then 'Whether Gemini 3 Flash can take the Twilio media URL directly, or whether a speech model '
        || 'must be added to ai_model_register first, is NOT established and must be checked before '
        || 'audio is enabled.'
      else null end,

    'deterministic_reply', v_reply,
    'deterministic_intent', v_intent,
    'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end,
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$function$;
revoke execute on function public.fn_wa_route(text, text, boolean, boolean, text) from public, anon, authenticated;
grant execute on function public.fn_wa_route(text, text, boolean, boolean, text) to service_role;
comment on function public.fn_wa_route(text, text, boolean, boolean, text) is
  'The WhatsApp route. Whether a message needs a person (p_needs_person) and which intent it carries (p_intent) are REASONED by the caller (think(), wa_inbound) and passed in; null means held, and nothing is decided on a guess. scripts/sql/whatsapp_answers_the_intent_that_was_reasoned_not_the_words_it_matched.sql';
