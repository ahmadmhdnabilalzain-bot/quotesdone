-- THE FOUNDER'S NUMBER IS GIVEN ONLY WHEN SOMEONE ASKS FOR A PERSON
--
-- Founder ruling, 7 September 2026: "my number only gets shared if someone typed something like
-- 'i wanna speak to an agent or real human, or who is the owner of quotesdone'"
--
-- WHAT WAS WRONG. Two paths were handing out +971509319355 without anyone asking for it:
--
--   1. The contact_human intent fired on 'complain' and 'call me', so a supplier expressing mild
--      frustration got the founder's mobile whether or not they wanted a person.
--   2. The trouble path attached the number to any message containing 'refund', 'scam' or 'dispute'.
--      That conflated two separate decisions: whether a HUMAN should take this over, and whether the
--      counterparty should be handed the founder's personal mobile. The first is often yes. The second
--      is his to grant, not the agent's to assume.
--
-- SO THEY ARE SEPARATED HERE. A complaint still escalates: it creates work for a person and marks the
-- thread as needing one. It simply does not publish the number. The number is released only when the
-- sender asks for a person or asks who runs the company, which is exactly what he specified.
--
-- WHY THIS MATTERS MORE THAN IT LOOKS. A phone number given out by a machine cannot be taken back. If
-- every annoyed supplier receives it, the founder's mobile becomes the company's support line, which
-- is the opposite of building a company that runs without him.

begin;

-- The intent that releases the number. Narrowed to an explicit ask, in his words.
update public.wa_reply_intent
   set label = 'Asking for a person, or who runs the company',
       match_patterns = array[
         'speak to a human','speak to human','real human','talk to a human','talk to human',
         'speak to an agent','talk to an agent','speak to someone','talk to someone',
         'speak to a person','talk to a person','customer service','support team',
         'who is the owner','who owns','who runs','the owner of quotesdone','your manager',
         'اكلم شخص','مسؤول','صاحب الشركة'],
       answer_template = 'Of course. You can reach us directly on +971 50 931 9355, which is answered '
                      || 'by the owner. I will also note that you asked for a person.',
       resolver_note = 'Founder ruling 7 Sep 2026: the number is released ONLY on an explicit request '
                    || 'for a person, or a question about who runs the company. Never on a complaint, '
                    || 'never on frustration, never unprompted.',
       sort = 7
 where intent_key = 'contact_human';

-- 'who is' and 'who was' were catching 'who is the owner of quotesdone' and answering it as off-topic.
-- A question about who runs the company is not off-topic, it is the most on-topic question there is.
update public.wa_reply_intent
   set match_patterns = array_remove(array_remove(match_patterns, 'who is'), 'who was')
 where intent_key = 'off_topic';

-- The off-topic and unmatched replies must not leak it either. Verified after this runs.
commit;

-- ---------------------------------------------------------------------------------------------
-- ESCALATION AND NUMBER-SHARING BECOME TWO DECISIONS
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
  v_asked_for_person boolean;
  v_chain  jsonb;
  v_intent text;
begin
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'));
  v_pack := public.fn_wa_fact_pack(p_phone);
  v_intent := v_det->>'intent';
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- DECISION ONE: does a person need to take this over? Complaints and disputes: yes.
  v_trouble := coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|fraud|شكوى|احتيال|نصب)';

  -- DECISION TWO, AND IT IS SEPARATE: did they ask for a person? Only this releases the number.
  -- coalesce, because v_intent is NULL when nothing matched and 'null = contact_human' is NULL,
  -- not false. A null here would reach the caller as an unanswered question about whether to publish
  -- the founder's number, which is the wrong default to leave to whoever reads it.
  v_asked_for_person := coalesce(v_intent = 'contact_human', false);

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

    -- A person takes it over. This is an internal routing decision and it does not publish anything.
    'hand_to_human', v_trouble,
    'hand_to_human_reason', case when v_trouble
      then 'The message reads as a complaint, a dispute or an accusation. A person should take this '
        || 'over. Note that this does NOT release the founder''s number; that is a separate decision.'
      else null end,

    -- The number. Released only on an explicit request for a person, per the founder's ruling.
    'share_founder_number', v_asked_for_person,
    'founder_number', case when v_asked_for_person then '+971509319355' else null end,
    'share_reason', case
      when v_asked_for_person then 'The sender explicitly asked for a person, or asked who runs the company.'
      else 'Not shared. Nobody asked for a person, and a number given out by a machine cannot be taken back.' end,

    'action', case
      when v_needs and v_held  then 'send_deterministic_and_log_shortfall'
      when v_needs             then 'walk_fallback_chain_with_fact_pack'
      else                          'send_deterministic' end,

    'transcription_gap', case when p_has_audio
      then 'Whether Gemini 3 Flash can take the Twilio media URL directly, or whether a speech model '
        || 'must be added to ai_model_register first, is NOT established and must be checked before '
        || 'audio is enabled.'
      else null end,

    'deterministic_reply', v_det->>'reply',
    'deterministic_intent', v_intent,
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$fn$;

comment on function public.fn_wa_route(text, text, boolean) is
  'Routes a WhatsApp turn. Escalating to a person and releasing the founder number are two separate decisions: a complaint does the first, only an explicit request for a person does the second.';

-- ---------------------------------------------------------------------------------------------
-- THE MODEL IS TOLD THE SAME RULE, BECAUSE IT COULD OTHERWISE VOLUNTEER THE NUMBER
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_model_brief()
returns text
language sql
stable
as $fn$
  select
     'You are the QuotesDone WhatsApp agent, talking to UAE suppliers and buyers. '

  || 'ABSOLUTE RULE ON FACTS: every detail about any customer, supplier, quote, job or price comes '
  || 'from fact_pack and from nowhere else. You know nothing about this company or these people '
  || 'except what fact_pack contains, and you must never fill such a gap from memory or from what '
  || 'seems likely. '

  || 'ABSOLUTE RULE ON THE OWNER''S NUMBER: never give out any phone number unless the sender has '
  || 'explicitly asked to speak to a person, an agent or a human, or has asked who owns or runs '
  || 'QuotesDone. Not when they are annoyed, not when you cannot answer, not to be helpful. A number '
  || 'given out cannot be taken back. If they have asked, the number is +971509319355. '

  || 'ABSOLUTE RULE ON SUBJECT: if the message is not about QuotesDone, reply with EXACTLY this '
  || 'sentence and nothing else: "' || public.fn_wa_off_topic_reply() || '" '
  || 'Translate it into the sender''s language if they did not write in English, but do not reword '
  || 'it, do not add to it, do not apologise around it, and do not answer the question first. Never '
  || 'state a fact about the outside world as if you had checked it: you cannot see the weather, a '
  || 'score, a rate or the time. '

  || 'BUT PHRASING IS NOT SUBJECT. A QuotesDone question asked in unusual words is still a QuotesDone '
  || 'question. "any update on my file bro" is a registration-status question and must be understood '
  || 'and answered from the record. Judge what the message is ABOUT, never how it is worded. '

  || 'WHEN IT IS ABOUT US BUT THE PACK LACKS THE FACT: say you will check and that the team will '
  || 'follow up. That gap is ours. '

  || 'The sender may write in any language: understand them and reply in their own. Follow the '
  || 'conversation history. Honour every entry in must_not. Match the courtesy you are given; a '
  || 'greeting gets a greeting, not a menu. Be brief, plain and useful, the way a competent person '
  || 'on a phone would be.'
$fn$;

comment on function public.fn_wa_model_brief() is
  'The instruction handed to whichever model answers a turn. Carries the rule that the owner number is released only on an explicit request for a person.';
