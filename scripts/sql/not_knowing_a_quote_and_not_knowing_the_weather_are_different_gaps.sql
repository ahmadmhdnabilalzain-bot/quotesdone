-- NOT KNOWING A QUOTE AND NOT KNOWING THE WEATHER ARE DIFFERENT GAPS
--
-- The founder asked what the agent replies to "how is the weather today". Run against production, it
-- answered: "I do not have an answer for that one yet, so I have passed it to the team. You can also
-- reach us on +971 50 931 9355."
--
-- That is wrong twice over. Nothing is passed to any team about the weather, so it is a false
-- statement. And it hands the founder's phone number to someone making small talk, which trains people
-- to call him about nothing.
--
-- THE DEFECT IS A CONFLATION. My brief said: if it is not in the fact pack, say you will check and the
-- team will follow up. That is right for one kind of gap and absurd for the other:
--
--   A COMPANY QUESTION WE LACK THE FACT FOR   "what is my quote worth", "when does my category open"
--                                             -> genuinely check, genuinely tell the team. The gap is
--                                                ours and closing it is work someone should do.
--   A QUESTION THAT IS NOT ABOUT US AT ALL    "how is the weather", "did you watch the match"
--                                             -> do NOT promise to check, do NOT involve anyone. Say
--                                                plainly that we only see what is inside QuotesDone,
--                                                be warm about it, and offer what we can help with.
--
-- WHY WARMTH IS NOT A LUXURY HERE. This number talks to UAE contractors and traders, where a greeting
-- and a small courtesy are how business is conducted. An agent that answers "good morning" with a
-- capability list reads as a machine and gets ignored. Being brief and human costs nothing and is the
-- difference between a supplier replying and not.

begin;

-- Small talk gets a human answer, not a menu.
insert into public.wa_reply_intent
  (intent_key, label, sort, match_patterns, requires_identity, requires_number, scope, answer_template, resolver_note)
values

-- Thanks and acknowledgement only. Greetings belong to the greeting intent, because answering
-- 'good morning' with 'thank you' is the kind of small wrongness that makes an agent feel fake.
('small_talk', 'Courtesy and acknowledgement', 6,
 array['how are you','how r u','thank you','thanks','shukran','شكرا','ok','okay','noted','great','perfect'],
 false, false, 'company',
 'Thank you. If there is anything you need on your registration, your documents or a job, tell me and I will look it up.',
 'Warm and short. A capability list in answer to "thank you" reads as a machine.'),

('off_topic', 'Not a QuotesDone question', 8,
 array['weather','temperature','forecast','rain','football','match','cricket','news','prayer time',
       'exchange rate','gold price','joke','الطقس','الجو','مباراة'],
 false, false, 'company',
 'I could not tell you that one, I only see what is inside QuotesDone. If you need anything on your registration, your documents or a job, I can help with that right away.',
 'Does NOT promise to check and does NOT give out the founder number. The gap is not ours to close.')

on conflict (intent_key) do update set
  label = excluded.label, sort = excluded.sort, match_patterns = excluded.match_patterns,
  answer_template = excluded.answer_template, resolver_note = excluded.resolver_note;

-- Greetings, including the times of day and their Arabic forms, answer as a greeting.
update public.wa_reply_intent
   set match_patterns = array['hi','hello','hey','salam','salaam','good morning','good evening',
                              'good afternoon','مرحبا','السلام','صباح الخير','مساء الخير'],
       sort = 5
 where intent_key = 'greeting';

commit;

-- ---------------------------------------------------------------------------------------------
-- THE BRIEF LEARNS THE DIFFERENCE
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_model_brief()
returns text
language sql
stable
as $$
  select
     'You are the QuotesDone WhatsApp agent, talking to UAE suppliers and buyers. '
  || 'ABSOLUTE RULE: every detail about any customer, supplier, quote, job or price comes from '
  || 'fact_pack and from nowhere else. You do not know anything about this company or these people '
  || 'except what fact_pack contains, and you must never fill such a gap from memory or from what '
  || 'seems likely. '
  || 'THERE ARE TWO DIFFERENT KINDS OF THING YOU CANNOT ANSWER, AND THEY GET DIFFERENT REPLIES. '
  || '(a) A QuotesDone question where the pack lacks the fact, such as what a quote is worth or when '
  || 'a category opens: say you will check and that the team will follow up. That gap is ours and '
  || 'someone should close it. '
  || '(b) A question that is not about QuotesDone at all, such as the weather, football or the news: '
  || 'do NOT promise to check, do NOT say the team will follow up, and do NOT give out the founder''s '
  || 'number. Say plainly and warmly that you only see what is inside QuotesDone, then offer what you '
  || 'can help with. Never state a fact about the outside world as if you had checked it; you cannot '
  || 'see the weather, a score, a rate or the time. '
  || 'The sender may phrase things in any way and in any language: understand them and reply in their '
  || 'own language. Follow the conversation history. Honour every entry in must_not. '
  || 'Match the courtesy you are given. A greeting gets a greeting, not a menu. '
  || 'Be brief, plain and useful, the way a competent person on a phone would be.'
$$;

comment on function public.fn_wa_model_brief() is
  'The instruction handed to whichever model answers a turn. Kept as a routine so it is versioned with the rest of the estate rather than embedded in an edge function.';

create or replace function public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
  v_trouble := coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|fraud|شكوى|احتيال|نصب)';

  v_needs := false; v_why := 'A deterministic answer matched and the message is simple, so this turn costs nothing.';
  if p_has_audio then
    v_needs := true; v_why := 'The message is a voice note and must be transcribed before it can be answered.';
  elsif not v_latin then
    v_needs := true; v_why := 'The message is not in Latin script and the fixed answers exist only in English.';
  elsif v_intent in ('small_talk','off_topic') then
    -- These two are FULLY answered without a model. Spending a model call on "thank you" or on the
    -- weather is paying for language we already have.
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
   || 'final rung is the deterministic reply and it cannot fail, so this turn is never answered with '
   || 'silence and never with a claim that a service is unavailable.',
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      else 'google/gemini-3-flash first, by founder ruling. On failure claude-sonnet-5. On failure the '
        || 'deterministic reply. Every rung gets the same fact pack and the same boundaries.' end,

    'hand_to_human', v_trouble,
    'human_contact', case when v_trouble then '+971509319355' else null end,
    'hand_to_human_reason', case when v_trouble
      then 'The message reads as a complaint, a dispute or an accusation. That needs a person, not a '
        || 'better-worded reply, and the founder answers this number himself.'
      else null end,

    'action', case
      when v_trouble           then 'hand_to_human'
      when v_needs and v_held  then 'send_deterministic_and_log_shortfall'
      when v_needs             then 'walk_fallback_chain_with_fact_pack'
      else                          'send_deterministic' end,

    'transcription_gap', case when p_has_audio
      then 'Whether Gemini 3 Flash can take the Twilio media URL directly, or whether a speech model '
        || 'must be added to ai_model_register first, is NOT established and must be checked before '
        || 'audio is enabled. Until then a voice note gets a reply asking the sender to type it.'
      else null end,

    'deterministic_reply', v_det->>'reply',
    'deterministic_intent', v_intent,
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$$;

comment on function public.fn_wa_route(text, text, boolean) is
  'Routes a WhatsApp turn. Small talk and off-topic questions are answered without a model. A company question we lack the fact for goes to the team; a question that is not about us does not.';

-- The generic no-match reply must stop claiming things were passed to the team when they were not.
create or replace function public.fn_wa_unmatched_reply()
returns text
language sql
immutable
as $$
  select 'I can help with your registration, your documents, your quotes, and any job by its number. '
      || 'I am not sure about that one, so let me check and someone will come back to you.'
$$;

comment on function public.fn_wa_unmatched_reply() is
  'The reply when nothing matched. Says "let me check" without asserting a team hand-off that may not happen, and does not hand out the founder number unprompted.';
