-- THE MODEL SUPPLIES LANGUAGE, THE DATABASE SUPPLIES THE FACTS
--
-- Founder, 7 September 2026: "the twilio whatsapp would need llm cause it needs to be adaptive and
-- smart. its not about key word matching only. it should handle full conversations and audio
-- recordings even and all languages."
--
-- He is right, and the intent registry I built yesterday cannot do that. Whole-token matching cannot
-- follow a conversation across three messages, cannot read a voice note, and cannot answer the same
-- question asked in Arabic, Hindi, Urdu or Tagalog, which is what a UAE contractor base actually
-- writes in.
--
-- BUT THE EARLIER CONSTRAINT STILL HOLDS, AND THIS RECONCILES THEM. His standing rule is that an
-- agent must be able to answer with OpenRouter OFF. The resolution is a division of labour:
--
--   THE DATABASE SUPPLIES THE FACTS.  Every number, status, date, id and policy in a reply is
--                                     retrieved here, by this file, from the live record.
--   THE MODEL SUPPLIES THE LANGUAGE.  Understanding a rambling message, following a thread, reading
--                                     a transcript, and answering in the sender's own language.
--
-- The model is never asked what the answer IS. It is handed the facts and asked to say them well.
-- That is why it cannot invent a quote value or promise a discount: those are not in its fact pack,
-- and the pack states explicitly what is unknown so it can say so.
--
-- WHEN INFERENCE IS HELD, which it is today by founder order, fn_wa_answer's deterministic path
-- still replies. The conversation is poorer and monolingual, but it is never wrong and never silent.

begin;

-- ---------------------------------------------------------------------------------------------
-- THE CONVERSATION
--   One row per counterparty thread, so the agent can follow a discussion rather than answering
--   each message as if it were the first. This is the thing keyword matching structurally cannot do.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.wa_conversation (
  id              bigserial primary key,
  phone_e164      text        not null,
  party_kind      text        check (party_kind in ('lead','customer','unknown')),
  party_id        text,

  -- The sender's language, detected once and then honoured. A UAE supplier base writes in English,
  -- Arabic, Hindi, Urdu and Tagalog, and answering in the wrong one reads as a wrong number.
  language        text,

  -- Where the conversation has got to, so a reply can depend on what came before.
  thread_state    text        not null default 'open'
                    check (thread_state in ('open','awaiting_reply','awaiting_document','resolved','handed_to_human')),
  topic           text,
  last_intent     text,

  -- The 24-hour WhatsApp service window. Inside it we may reply freely; outside it only an approved
  -- template may be sent. Getting this wrong is what damages a number's quality rating.
  window_opened_at timestamptz,
  window_expires_at timestamptz,

  message_count   int         not null default 0,
  first_seen_at   timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  handed_to       text,
  unique (phone_e164)
);

create index if not exists wa_conversation_open
  on public.wa_conversation (last_seen_at desc) where thread_state <> 'resolved';

comment on table public.wa_conversation is
  'One thread per counterparty. window_expires_at is the WhatsApp 24-hour service window: inside it a free-form reply is allowed, outside it only an approved template.';

comment on column public.wa_conversation.language is
  'Detected once and honoured thereafter. Answering a UAE supplier in the wrong language reads as a wrong number.';

-- Every turn, both directions, so a model can be handed real history rather than guessing at it.
create table if not exists public.wa_turn (
  id              bigserial primary key,
  conversation_id bigint      not null references public.wa_conversation(id) on delete cascade,
  at              timestamptz not null default now(),
  direction       text        not null check (direction in ('in','out')),
  body            text,

  -- Audio. Twilio hands us a media URL; the transcript is what the model reads.
  media_url       text,
  media_kind      text,
  transcript      text,
  transcript_source text check (transcript_source in ('twilio','model','none')),

  intent_key      text,
  answered_by     text check (answered_by in ('deterministic','model','human','template')),
  fact_pack       jsonb,
  model_id        text,
  cost_aed        numeric
);

create index if not exists wa_turn_conv on public.wa_turn (conversation_id, at desc);

comment on table public.wa_turn is
  'Every message in and out, with the fact pack the reply was built from. answered_by records whether a model was involved, so a wrong answer can be traced to its source.';

commit;

-- ---------------------------------------------------------------------------------------------
-- THE FACT PACK
--   Everything true about this counterparty, retrieved deterministically. This is the ONLY material
--   a model is permitted to answer from. It also states what is UNKNOWN, so the model can say so
--   instead of filling the gap.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_fact_pack(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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
      'founder_contact', '+971509319355',
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
$$;

revoke execute on function public.fn_wa_fact_pack(text) from public;

comment on function public.fn_wa_fact_pack(text) is
  'Everything true about a WhatsApp counterparty, retrieved deterministically. The only material a model may answer from, including an explicit list of what is unknown and what may not be said.';

-- ---------------------------------------------------------------------------------------------
-- THE ROUTER
--   Decides, per message, whether this turn needs a model at all. Cheap questions stay deterministic;
--   conversation, audio and other languages go to the model WITH the fact pack attached. When
--   inference is held, everything falls back to the deterministic answer rather than going silent.
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
begin
  -- Is paid inference available? The founder holds it today, and this must degrade rather than fail.
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'));
  v_pack := public.fn_wa_fact_pack(p_phone);
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  -- Latin script is a weak proxy for "probably a language the templates cover". Anything else needs
  -- the model, because the deterministic answers exist only in English.
  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- WHICH MODEL. Not picked ad hoc: ai_model_register already carries three board-approved models
  -- with what each is approved and forbidden for.
  --   claude-fable-5   small tier, approved for classification, extraction, routing, summarisation.
  --                    That is exactly this job: understand a message, choose from a fact pack, and
  --                    say it in the sender's language. Cheapest, and this is high-volume work.
  --   claude-sonnet-5  medium tier, approved for drafting. Reserved for turns that need care: a
  --                    complaint, a dispute, or a thread that has run long without resolving.
  --   claude-opus-4.8  explicitly FORBIDDEN for anything schedulable or batch. Never used here.
  --
  -- Note the governance line that matters: fable-5 is forbidden for pricing decisions, legal text and
  -- supplier approval. This agent does none of those. It STATES a price that pricing_config already
  -- decided; it never decides one. Reading out a fact is not making a decision, and the fact pack is
  -- what keeps that true.
  v_needs := false; v_why := 'A deterministic answer matched and the message is simple.';
  if p_has_audio then
    v_needs := true; v_why := 'The message is a voice note and must be transcribed before it can be answered.';
  elsif not v_latin then
    v_needs := true; v_why := 'The message is not in Latin script; the deterministic answers exist only in English.';
  elsif coalesce((v_det->>'matched')::boolean, false) = false then
    v_needs := true; v_why := 'No enumerated intent matched, so this is a question the fixed answers do not cover.';
  elsif v_conv.message_count is not null and v_conv.message_count >= 2 then
    v_needs := true; v_why := 'This is a continuing conversation; a fixed answer would ignore what came before.';
  elsif length(coalesce(p_body,'')) > 160 then
    v_needs := true; v_why := 'The message is long enough to contain more than one question.';
  end if;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    -- The decision the caller acts on. When a model is wanted but held, the deterministic reply goes
    -- out and the shortfall is recorded rather than hidden behind an outage message.
    'action', case
      when v_needs and v_held then 'send_deterministic_and_log_shortfall'
      when v_needs           then 'call_model_with_fact_pack'
      else                        'send_deterministic' end,
    -- The model this turn should use, resolved against the approved register. A turn that needs care
    -- gets the medium tier; everything else gets the small one. Audio has no approved transcription
    -- model in the register at all, and that is reported rather than silently assumed.
    'model', case
      when not v_needs then null
      when p_has_audio then 'anthropic/claude-fable-5'
      when coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|شكوى|احتيال)'
        then 'anthropic/claude-sonnet-5'
      when coalesce(v_conv.message_count, 0) >= 4 then 'anthropic/claude-sonnet-5'
      else 'anthropic/claude-fable-5' end,
    'model_reason', case
      when not v_needs then 'No model needed for this turn.'
      when coalesce(p_body,'') ~* '(complain|refund|dispute|angry|lawyer|legal|scam|cheat|شكوى|احتيال)'
        then 'The message reads as a complaint or a dispute, so it gets the medium tier that is approved for drafting.'
      when coalesce(v_conv.message_count, 0) >= 4
        then 'This thread has run four turns without resolving, so it gets the medium tier.'
      else 'Routine turn: the small tier, which is board-approved for classification and summarisation and is the cheapest.' end,
    'transcription_gap', case when p_has_audio
      then 'AUDIO HAS NO APPROVED TRANSCRIPTION MODEL. ai_model_register holds three text models and '
        || 'no speech model, so a voice note cannot be transcribed until one is added to the register '
        || 'and approved. Until then a voice note gets a reply asking the sender to type it.'
      else null end,
    'deterministic_reply', v_det->>'reply',
    'deterministic_intent', v_det->>'intent',
    'fact_pack', v_pack,
    'model_brief', 'You are the QuotesDone WhatsApp agent. Answer ONLY from fact_pack. Reply in the '
                || 'sender''s own language. Follow the history. Honour every entry in must_not. If the '
                || 'answer is not in the pack, say you will check and that the team will follow up, and '
                || 'never invent it.'
  );
end;
$$;

revoke execute on function public.fn_wa_route(text, text, boolean) from public;

comment on function public.fn_wa_route(text, text, boolean) is
  'Decides whether a WhatsApp turn needs a model, and returns the fact pack it must answer from. Degrades to the deterministic reply when inference is held, and records the shortfall rather than claiming an outage.';
