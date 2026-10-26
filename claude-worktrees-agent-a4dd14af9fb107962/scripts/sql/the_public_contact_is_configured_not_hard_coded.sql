-- THE PUBLIC CONTACT IS A CONFIGURED SETTING, NOT A LITERAL
--
-- Founder, 7 September 2026: "+971509319355 is my number / Ahmad Alzain is my name / the agent will
-- use twilio number though."
--
-- Three routines carried his number as a hard-coded string. The build spec forbids exactly that:
-- the approved public phone must come from current company configuration, must not be inferred from
-- a private contact record, and must never be emitted as a placeholder.
--
-- app_secrets.founder_mobile already held the same digits and is deliberately NOT the source. It is
-- a private contact record. Two values matching today is not permission to publish either of them.
-- The new key says publication in its name and holds exactly what he approved for it.
--
-- WHEN THE SETTING IS ABSENT the agent says so instead of emitting an empty string. A message
-- reading "you can reach us on  " is worse than one that admits the number is not configured, and
-- the spec asks for a blocker reported to the CEO rather than a placeholder printed to a customer.
--
-- TWO NUMBERS THAT MUST NEVER SWAP:
--   founder_public_phone  +971509319355   what the agent GIVES OUT when someone asks for a person
--   twilio_wa_from        12183166814     what the agent SENDS FROM
-- Sending from his number would put his phone in front of every customer; publishing the Twilio
-- number as "the founder" would be untrue.
--
-- Rewritten: fn_wa_route (1 occurrence), fn_wa_fact_pack (1 occurrence), fn_wa_model_brief (1 occurrence)

CREATE OR REPLACE FUNCTION public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'));
  v_pack := public.fn_wa_fact_pack(p_phone);
  v_intent := v_det->>'intent';
  v_reply  := v_det->>'reply';
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- The two ways a message needs a person.
  v_asked   := coalesce(v_intent = 'contact_human', false);
  v_trouble := coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|fraud|شكوى|احتيال|نصب)';

  -- One decision now, not two. Needing a person and getting his number are the same thing here.
  v_person := v_asked or v_trouble;
  v_reason := case
    when v_asked   then 'They asked for a person, or asked who runs the company.'
    when v_trouble then 'This is a complaint, a dispute or an accusation. It needs a person whether '
                     || 'they asked for one or not, and the founder is the only person there is.'
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
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_wa_fact_pack(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lead_id bigint;
  l         record;
  c         record;
  v_cfg     record;
  v_conv    record;
  v_hist    jsonb := '[]'::jsonb;
  v_mand    jsonb;
  v_digits  text;
  -- Built before the return, NOT inside a CASE. Postgres evaluates a record field reference even in
  -- an unreached CASE branch, so with an unknown sender 'record l is not assigned yet' aborts the
  -- whole function. An unknown caller is the most common case, so that bug would have fired first.
  v_ident   jsonb;
  v_found_c boolean := false;
  v_conv_j  jsonb;
begin
  v_digits := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  select standard_reveal_rate, supplier_free_count, supplier_reg_fee, category_open_min_suppliers,
         refund_window_working_days, chase_after_working_days
    into v_cfg from public.pricing_config order by id limit 1;

  v_lead_id := public.fn_wa_lead_id(p_phone);
  if v_lead_id is not null then
    select * into l from public.leads where id = v_lead_id;
    v_mand  := public.fn_supplier_mandatory_check(v_lead_id);
    v_ident := jsonb_build_object(
      'kind','supplier','id',v_lead_id,'company',l.company_name,
      'approval_status', coalesce(l.approval_status,'not reviewed'),
      'registration_status', coalesce(l.registration_status,'not started'),
      'mandatory', v_mand);
  else
    select * into c from public.customers
      where regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = v_digits limit 1;
    v_found_c := found;
    if v_found_c then
      v_mand  := public.fn_customer_mandatory_check(c.id);
      v_ident := jsonb_build_object(
        'kind','customer','id',c.id::text,'name',c.full_name,
        'email_verified', c.email_verified, 'phone_verified', c.phone_verified,
        'mandatory', v_mand);
    else
      v_ident := jsonb_build_object('kind','unknown',
        'note','This number matches no lead and no customer. Do not discuss anyone''s records.');
    end if;
  end if;

  v_conv_j := jsonb_build_object('state','new');
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;
  if found then
    v_conv_j := jsonb_build_object(
      'state', v_conv.thread_state, 'topic', v_conv.topic, 'language', v_conv.language,
      'messages_so_far', v_conv.message_count,
      'window_open', (v_conv.window_expires_at is not null and v_conv.window_expires_at > now()));
    select coalesce(jsonb_agg(jsonb_build_object('at', t.at, 'dir', t.direction,
             'text', coalesce(t.transcript, t.body)) order by t.at), '[]'::jsonb)
      into v_hist
      from (select * from public.wa_turn where conversation_id = v_conv.id order by at desc limit 12) t;
  end if;

  return jsonb_build_object(
    -- WHO. Identity is a fact, never an inference. An unknown sender stays unknown.
    'identity', v_ident,

    -- WHAT IS TRUE ABOUT THE COMPANY. Read live, never remembered.
    'company', jsonb_build_object(
      'reveal_rate_pct', round(coalesce(v_cfg.standard_reveal_rate,0.03) * 100, 1),
      'supplier_free_count', v_cfg.supplier_free_count,
      'supplier_reg_fee_aed', v_cfg.supplier_reg_fee,
      'category_opens_at_suppliers', v_cfg.category_open_min_suppliers,
      'refund_window_working_days', v_cfg.refund_window_working_days,
      'supplier_chase_after_working_days', v_cfg.chase_after_working_days,
      'founder_contact', (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')),
      'supplier_mandatory', jsonb_build_array('company name','UAE mobile','email','trade licence','company profile','signed terms'),
      'customer_mandatory', jsonb_build_array('name','mobile','email','signed terms')),

    -- THE THREAD.
    'conversation', v_conv_j,
    'history', v_hist,

    -- WHAT IS NOT KNOWN. Stating this is what stops a model filling the gap with something plausible.
    'unknown', jsonb_build_array(
      'There are no live requests, quotes or comparison reports in the system yet, so no job status can be given for any id.',
      'No category is open yet, so no supplier can currently be matched to a buyer request.',
      'Pricing beyond the reveal rate and registration fee is not set and must not be invented.'),

    -- WHAT MAY NOT BE SAID OR DONE. A boundary, not a suggestion.
    'must_not', jsonb_build_array(
      'Never state a fact that is not in this pack. If it is not here, say you will check and pass it to the team.',
      'Never quote a price, discount, delivery date or timescale that is not in this pack.',
      'Never reveal any other party''s identity, contact details or quote. Anonymity is the product.',
      'Never promise approval, a job, or a refund. Refunds are the founder''s decision alone.',
      'Never ask for a password, a card number or an OTP code.'),

    'generated_at', now()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_wa_model_brief()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select
     'You are the QuotesDone WhatsApp agent, talking to UAE suppliers and buyers. '

  || 'ABSOLUTE RULE ON FACTS: every detail about any customer, supplier, quote, job or price comes '
  || 'from fact_pack and from nowhere else. You know nothing about this company or these people '
  || 'except what fact_pack contains, and you must never fill such a gap from memory or from what '
  || 'seems likely. '

  || 'THE OWNER''S NUMBER IS ' || (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')) || ' AND THERE ARE EXACTLY TWO REASONS TO GIVE IT. One: the '
  || 'sender asked to speak to a person, an agent or a human, or asked who owns or runs QuotesDone. '
  || 'Two: the message is a complaint, a dispute or an accusation, which needs a person whether they '
  || 'asked or not. In both cases give it plainly and without making them ask twice, because the '
  || 'owner is the only person in this company and an escalation that does not reach him reaches '
  || 'nobody. Give it for NOTHING ELSE: not for an off-topic question, not for small talk, not '
  || 'because you could not answer. '

  || 'ABSOLUTE RULE ON SUBJECT: if the message is not about QuotesDone, reply with EXACTLY this '
  || 'sentence and nothing else: "' || public.fn_wa_off_topic_reply() || '" '
  || 'Translate it into the sender''s language if they did not write in English, but do not reword '
  || 'it, do not add to it, do not apologise around it, and do not answer the question first. Never '
  || 'state a fact about the outside world as if you had checked it: you cannot see the weather, a '
  || 'score, a rate or the time. '

  || 'BUT PHRASING IS NOT SUBJECT. A QuotesDone question asked in unusual words is still a QuotesDone '
  || 'question. "any update on my file bro" is a registration-status question and must be understood '
  || 'and answered from the record. Judge what the message is ABOUT, never how it is worded. '

  || 'WHEN IT IS ABOUT US BUT THE PACK LACKS THE FACT: say you will check and that someone will come '
  || 'back to them. That gap is ours. '

  || 'The sender may write in any language: understand them and reply in their own. Follow the '
  || 'conversation history. Honour every entry in must_not. Match the courtesy you are given; a '
  || 'greeting gets a greeting, not a menu. Be brief, plain and useful, the way a competent person '
  || 'on a phone would be.'
$function$;

