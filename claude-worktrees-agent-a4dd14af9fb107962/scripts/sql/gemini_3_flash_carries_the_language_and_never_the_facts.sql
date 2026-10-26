-- GEMINI 3 FLASH CARRIES THE LANGUAGE AND NEVER THE FACTS
--
-- Founder ruling, 7 September 2026: "the customer might use different wording. you can answer purely
-- from database. the model should get the customer/supplier/job details only from the database.
-- anything else should be hybrid with gemini 3 flash"
--
-- Three instructions in one sentence, and they settle the architecture:
--
--   1. WORDING VARIES, SO UNDERSTANDING NEEDS A MODEL. A supplier does not write "what is my
--      registration status". He writes "any update on my file" or "شو صار بالطلب". Whole-token
--      matching cannot bridge that and never will.
--   2. PARTY AND JOB DETAIL COMES PURELY FROM THE DATABASE. The model is handed the fact pack and may
--      use nothing else for anyone's company name, status, documents, quote or job. It is not
--      permitted to recall, infer or complete those from anything it saw in training.
--   3. EVERYTHING ELSE IS HYBRID, ON GEMINI 3 FLASH. He named the model, so this replaces the
--      claude-fable-5 default I chose a commit ago.
--
-- WHAT CHANGED ABOUT ESCALATION, AND WHY IT IS BETTER. I had complaints and disputes routing to a
-- larger, more expensive model. That was the wrong instinct. A supplier saying "this is a scam" does
-- not need better prose, it needs a person. Those turns now hand to the founder on +971509319355,
-- which is a channel he already told me he answers. One model for language; a human for trouble.

begin;

-- The register is the governance record for which models may run at all. Gemini was not in it, so
-- adding it is a governance act with an authority, not a config edit.
insert into public.ai_model_register
  (model, provider, approved, approved_for, forbidden_for, approved_by, approved_at, review_due, note)
values (
  'google/gemini-3-flash', 'openrouter', true,
  array['whatsapp conversation','language understanding','translation','transcript reading','summarisation'],
  array['pricing decisions','supplier approval','refund decisions','legal text',
        'stating any party or job detail not present in the supplied fact pack'],
  'founder ruling 7 Sep 2026', now(), (now() + interval '90 days')::date,
  'The WhatsApp conversation model, named by the founder. Carries language only: understanding varied '
  || 'wording, following a thread, reading a transcript, and replying in the sender''s own tongue. '
  || 'Every party, job and price fact is supplied to it by fn_wa_fact_pack and it may use no other '
  || 'source for those. THE EXACT PROVIDER SLUG MUST BE CONFIRMED against the OpenRouter catalogue '
  || 'before the first live call; if it differs, update this row rather than hardcoding it elsewhere.'
)
on conflict (model) do update set
  approved = excluded.approved, approved_for = excluded.approved_for,
  forbidden_for = excluded.forbidden_for, approved_by = excluded.approved_by,
  note = excluded.note, review_due = excluded.review_due;

commit;

-- ---------------------------------------------------------------------------------------------
-- THE ROUTER, RE-POINTED
--   One model for every turn that needs one. Trouble goes to a person, not to a bigger model.
-- ---------------------------------------------------------------------------------------------

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
  v_model  text;
begin
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'));
  v_pack := public.fn_wa_fact_pack(p_phone);
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- Trouble is a person's job, not a bigger model's. The founder answers +971509319355 himself.
  v_trouble := coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|fraud|شكوى|احتيال|نصب)';

  -- WHEN A MODEL IS NEEDED. The founder's point is the first branch: wording varies, so a message
  -- that matched nothing is the normal case, not the exception.
  v_needs := false; v_why := 'A deterministic answer matched and the message is simple, so this turn costs nothing.';
  if p_has_audio then
    v_needs := true; v_why := 'The message is a voice note and must be transcribed before it can be answered.';
  elsif not v_latin then
    v_needs := true; v_why := 'The message is not in Latin script and the fixed answers exist only in English.';
  elsif coalesce((v_det->>'matched')::boolean, false) = false then
    v_needs := true; v_why := 'No fixed answer matched. Wording varies, so this is the normal case rather than an exception.';
  elsif coalesce(v_conv.message_count, 0) >= 2 then
    v_needs := true; v_why := 'This is a continuing conversation; a fixed answer would ignore what came before.';
  elsif length(coalesce(p_body,'')) > 160 then
    v_needs := true; v_why := 'The message is long enough to contain more than one question.';
  end if;

  v_model := case when v_needs then 'google/gemini-3-flash' else null end;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    'model', v_model,
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      else 'google/gemini-3-flash, named by the founder 7 Sep 2026. It carries language only; every '
        || 'party, job and price fact comes from fact_pack and it may use no other source for those.' end,

    -- Trouble hands to a person. This is an escalation, not a routing tier.
    'hand_to_human', v_trouble,
    'human_contact', case when v_trouble then '+971509319355' else null end,
    'hand_to_human_reason', case when v_trouble
      then 'The message reads as a complaint, a dispute or an accusation. That needs a person, not a '
        || 'better-worded reply, and the founder answers this number himself.'
      else null end,

    'action', case
      when v_trouble           then 'hand_to_human'
      when v_needs and v_held  then 'send_deterministic_and_log_shortfall'
      when v_needs             then 'call_model_with_fact_pack'
      else                          'send_deterministic' end,

    'transcription_gap', case when p_has_audio
      then 'Gemini 3 Flash reads text. Whether it can take the Twilio media URL directly, or whether a '
        || 'separate speech model must be added to ai_model_register first, is NOT yet established and '
        || 'must be checked before audio is enabled. Until then a voice note gets a reply asking the '
        || 'sender to type it.'
      else null end,

    'deterministic_reply', v_det->>'reply',
    'deterministic_intent', v_det->>'intent',
    'fact_pack', v_pack,

    'model_brief',
      'You are the QuotesDone WhatsApp agent. '
   || 'ABSOLUTE RULE: every detail about any customer, supplier, quote, job or price comes from '
   || 'fact_pack and from nowhere else. You do not know anything about this company or these people '
   || 'except what fact_pack contains. If it is not in the pack, say you will check and that the team '
   || 'will follow up. Never fill a gap from memory or from what seems likely. '
   || 'The sender may phrase things in any way and in any language: understand them, and reply in '
   || 'their own language. Follow the conversation history. Honour every entry in must_not. '
   || 'Be brief, plain and useful, the way a competent person on a phone would be.'
  );
end;
$$;

comment on function public.fn_wa_route(text, text, boolean) is
  'Routes a WhatsApp turn. Gemini 3 Flash carries language only; every party and job fact comes from fn_wa_fact_pack. Complaints and disputes hand to the founder rather than to a larger model.';
