-- WHEN GEMINI IS DOWN, SONNET ANSWERS, AND THE FALLBACK IS NEVER SILENT
--
-- Founder ruling, 7 September 2026: "if gemini 3 flash went down suddenly then it routes to sonnet 5"
--
-- THE CHAIN, AND WHY IT HAS THREE RUNGS RATHER THAN TWO.
--
--   1. google/gemini-3-flash    the founder's choice. Carries language for every turn that needs one.
--   2. anthropic/claude-sonnet-5 his named fallback. Already board-approved for drafting, so no new
--                               governance is required to use it this way.
--   3. the deterministic reply  because a chain of two models still ends in silence when both are
--                               down, and silence to a supplier who asked a question is worse than a
--                               plainer answer. The last rung cannot fail: it is a SQL query.
--
-- THE SAME CONSTRAINTS TRAVEL DOWN THE CHAIN. A fallback is not a relaxation. Sonnet gets the identical
-- fact pack and the identical brief: every party, job and price detail comes from the pack and from
-- nowhere else. A model substituted under pressure is exactly when an invented fact would slip through,
-- so the boundary is attached to the turn rather than to the model.
--
-- AND A FALLBACK THAT NOBODY NOTICES IS AN OUTAGE THAT NOBODY FIXES. The estate's llm_calls table
-- already carries model_wanted, model_used and fell_back, which is the right shape. This adds a watch
-- so that a fallback which stops being occasional and becomes permanent raises a task, rather than the
-- company quietly paying Sonnet prices for months because nobody read a column.

begin;

create table if not exists public.model_fallback_chain (
  purpose       text        not null,
  rung          int         not null,
  model         text        not null,
  kind          text        not null check (kind in ('model','deterministic')),
  rationale     text        not null,
  authority     text        not null,
  active        boolean     not null default true,
  primary key (purpose, rung)
);

comment on table public.model_fallback_chain is
  'Ordered fallback per purpose. The last rung must be deterministic, because a chain of models still ends in silence when they are all down.';

insert into public.model_fallback_chain (purpose, rung, model, kind, rationale, authority) values
  ('whatsapp_conversation', 1, 'google/gemini-3-flash', 'model',
   'The founder''s choice for the conversation layer. Carries language only.',
   'Founder ruling 7 Sep 2026'),
  ('whatsapp_conversation', 2, 'anthropic/claude-sonnet-5', 'model',
   'The founder''s named fallback. Already board-approved for drafting, so using it this way needs no '
   || 'new governance. It receives the identical fact pack and the identical boundaries: a fallback is '
   || 'not a relaxation.',
   'Founder ruling 7 Sep 2026: "if gemini 3 flash went down suddenly then it routes to sonnet 5"'),
  ('whatsapp_conversation', 3, 'deterministic', 'deterministic',
   'fn_wa_answer. Plainer and English-only, but it is a SQL query and therefore cannot be down. A '
   || 'supplier who asked a question gets an answer even when every provider is unreachable.',
   'Engineering judgement: a chain of two models still ends in silence')
on conflict (purpose, rung) do update set
  model = excluded.model, kind = excluded.kind,
  rationale = excluded.rationale, authority = excluded.authority;

commit;

-- ---------------------------------------------------------------------------------------------
-- THE ROUTER RETURNS THE WHOLE CHAIN
--   The caller walks it in order rather than holding the policy in its own code, so changing the
--   chain is a row edit and never a redeploy.
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
  v_chain  jsonb;
begin
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'));
  v_pack := public.fn_wa_fact_pack(p_phone);
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';
  v_trouble := coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|fraud|شكوى|احتيال|نصب)';

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

  -- The chain, read from the table. The caller tries rung 1, and on failure rung 2, and on failure
  -- rung 3, which cannot fail.
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
      else 'google/gemini-3-flash first, by founder ruling. On failure claude-sonnet-5, his named '
        || 'fallback. On failure the deterministic reply. Every rung gets the same fact pack and the '
        || 'same boundaries: a fallback is not a relaxation.' end,

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
  'Routes a WhatsApp turn and returns the whole fallback chain: Gemini 3 Flash, then Sonnet 5, then the deterministic reply, which cannot fail. Every rung receives the same fact pack and the same boundaries.';

-- ---------------------------------------------------------------------------------------------
-- A FALLBACK THAT BECOMES PERMANENT IS AN OUTAGE NOBODY FIXED
-- ---------------------------------------------------------------------------------------------

-- ROUTINE REMOVED 7 September 2026. public.fn_model_fallback_watch was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke execute on function public.fn_model_fallback_watch(int) from public;

comment on function public.fn_model_fallback_watch(int) is
  'Measures how often the primary model is being fallen back from. Distinguishes a healthy primary from an idle channel, because zero calls proves neither.';
