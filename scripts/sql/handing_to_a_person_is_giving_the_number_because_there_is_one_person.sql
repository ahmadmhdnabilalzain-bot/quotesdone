-- HANDING TO A PERSON IS GIVING THE NUMBER, BECAUSE THERE IS ONE PERSON
--
-- Founder, 7 September 2026: "hand to a person is basically share number"
--
-- He is right and my split was an abstraction with nothing behind it. I had separated "a human should
-- take this over" from "release the founder's number" as though there were a support desk to hand to.
-- There is not. Measured earlier today: 54 active seats, 7 of kind agent and 47 of kind brain, ZERO
-- humans. The only person in this company is the founder. So an escalation that does not give someone
-- his number is an escalation to nobody, which is worse than not escalating at all: the counterparty
-- is told a person will help and then nothing happens.
--
-- THE RULE THAT SURVIVES BOTH OF HIS INSTRUCTIONS. An hour ago he said the number is only shared when
-- someone asks for a person or asks who runs the company. Now he says handing to a person IS sharing
-- the number. Those are not in conflict once you see what each was protecting:
--
--   SHARE THE NUMBER when the message genuinely needs a person. That is either
--       (a) they asked for one, explicitly, or asked who owns QuotesDone, or
--       (b) it is a complaint, a dispute or an accusation, which needs him whether they asked or not.
--   DO NOT SHARE IT for anything else: off-topic questions, small talk, a greeting, an ordinary
--       question the agent could not match. Those were what he objected to, and they are still refused.
--
-- The distinction that matters is not "asked versus not asked". It is "needs a person versus does not".

begin;

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
    'founder_number', case when v_person then '+971509319355' else null end,
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
$fn$;

comment on function public.fn_wa_route(text, text, boolean) is
  'Routes a WhatsApp turn. Needing a person and receiving the founder number are ONE decision, because the founder is the only person in the company. Opened by an explicit request or by a complaint; never by an off-topic or unmatched message.';

commit;

-- The model is told the same thing, so it cannot hold the number back from someone who needs it.
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

  || 'THE OWNER''S NUMBER IS +971509319355 AND THERE ARE EXACTLY TWO REASONS TO GIVE IT. One: the '
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
$fn$;

comment on function public.fn_wa_model_brief() is
  'The instruction handed to whichever model answers a turn. Gives the owner number on an explicit request OR on a complaint, and on nothing else.';
