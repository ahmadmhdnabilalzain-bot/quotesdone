-- THE WHATSAPP FALLBACK CHAIN NAMES THE FOUNDER'S MATRIX V2, AND EVERY MODEL A CHAIN NAMES IS IN THE REGISTRY.
-- Seat: customer_support (WhatsApp). 6 Oct 2026, final check (founder_instruction 1119) against matrix v2
-- (founder_instruction 1108, 5 Oct: "GPT 6 Luna replaces Gemini 3.8 Flash as the main model everywhere, with Gemini
-- 3.8 Flash as the backup. Exception: received audio stays on Gemini 3.8 Flash.").
--
-- MEASURED (production, 6 Oct 2026, read-only): model_fallback_chain 'whatsapp_conversation' still read
--   1 google/gemini-3-flash   (not in model_registry at all)
--   2 anthropic/claude-sonnet-5
--   3 deterministic
-- and fn_wa_route returned 'model' = google/gemini-3-flash as a literal. wa_inbound does not route on either (its
-- model call goes through ai_gateway -> fn_ai_route, which is already v2: CS wa_inbound = luna > Gemini, transcribe
-- with audio = Gemini, no fallback - PROBE OK in every_seat_runs_the_founders_model_matrix_probe.sql). So nothing
-- was answered by the wrong model; the table and the route's description were false, and a false description of
-- the route is what the next session would build on.
--
-- WHAT THIS CHANGES
--   1. whatsapp_conversation: 1 openai/gpt-6-luna, 2 google/gemini-3.8-flash, 3 deterministic (the third rung's
--      reason is unchanged: a chain of two models still ends in silence).
--   2. whatsapp_voice_note (new purpose): 1 google/gemini-3.8-flash, 2 deterministic. Received audio stays on Gemini
--      and has no second model (the only other active model that hears is the web-grounded :online variant).
--   3. fn_wa_route reads its 'model' from rung 1 of the purpose the message needs (voice note or not) instead of a
--      literal, so the table is the one place a model is named. Copied from
--      whatsapp_answers_the_intent_that_was_reasoned_not_the_words_it_matched.sql (canonical until this file);
--      only the lines marked "6 Oct" change. Same signature, so create or replace keeps the ACL.
-- Prevented by: scripts/checks/every_fallback_chain_model_is_in_the_registry.test.mjs (every model a chain row names
-- is registered and active; fails on the 6 Oct table).
-- Pending: scripts/sql/pending/the_whatsapp_fallback_chain_names_the_founders_matrix_v2.txt

-- Rungs 1 and 2 of whatsapp_conversation are the same keys (purpose, rung), so the upsert replaces them in place.
insert into public.model_fallback_chain (purpose, rung, model, kind, rationale, authority, active) values
  ('whatsapp_conversation', 1, 'openai/gpt-6-luna', 'model',
   'Matrix v2 main model for customer_support. Carries language only; facts come from the fact pack.',
   'Founder ruling 5 Oct 2026 (founder_instruction 1108)', true),
  ('whatsapp_conversation', 2, 'google/gemini-3.8-flash', 'model',
   'Matrix v2 backup. Same fact pack and the same boundaries: a fallback is not a relaxation.',
   'Founder ruling 5 Oct 2026 (founder_instruction 1108)', true),
  ('whatsapp_voice_note', 1, 'google/gemini-3.8-flash', 'model',
   'Received audio stays on Gemini 3.8 Flash. No second model hears it, so the next rung is the deterministic reply.',
   'Founder ruling 5 Oct 2026 (founder_instruction 1108): "received audio stays on Gemini 3.8 Flash"', true),
  ('whatsapp_voice_note', 2, 'deterministic', 'deterministic',
   'fn_wa_answer. A voice note that cannot be heard still gets a plain answer, never silence.',
   'Engineering judgement: a chain that ends in a model still ends in silence', true)
on conflict (purpose, rung) do update
   set model = excluded.model, kind = excluded.kind, rationale = excluded.rationale,
       authority = excluded.authority, active = true;

create or replace function public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean default false,
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
   -- 6 Oct: a voice note has its own chain (received audio stays on Gemini, matrix v2)
   where purpose = case when p_has_audio then 'whatsapp_voice_note' else 'whatsapp_conversation' end and active;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    -- 6 Oct: rung 1 of the chain, never a literal, so the table is the one place a model is named
    'model', case when v_needs then (select e ->> 'model' from jsonb_array_elements(v_chain) e
                                      where e ->> 'kind' = 'model' order by (e ->> 'rung')::int limit 1) else null end,
    'fallback_chain', case when v_needs then v_chain else null end,
    'on_model_failure',
      'Try each rung in order. Record model_wanted, model_used and fell_back on llm_calls for every '
   || 'attempt, so a fallback that becomes permanent is visible rather than quietly expensive. The '
   || 'final rung is the deterministic reply and it cannot fail.',
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      -- 6 Oct: matrix v2 (founder_instruction 1108)
      when p_has_audio then 'google/gemini-3.8-flash hears the voice note (received audio stays on Gemini). On failure '
        || 'the deterministic reply.'
      else 'openai/gpt-6-luna first, by the founder''s matrix v2. On failure google/gemini-3.8-flash. On failure the '
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
