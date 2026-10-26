-- THE AGENT REMEMBERS, AND IT CAN TAKE YOUR TRADE LICENCE
--
-- Founder, 7 September 2026: "so is the whatsapp agent now as smart as amazon customer support agent
-- for example? if not then upgrade it"
--
-- No, it was not, and measuring it showed the gap is not conversational polish:
--
--   wa_conversation rows   0    I built the memory tables and wired nothing to them. Every message
--   wa_turn rows           0    was turn one, forever, no matter what the schema implied.
--   routines that ACT      0    It could only speak. Amazon's agent cancels an order, reships, and
--                               changes an address. Mine could describe a policy.
--   leads blocked on a document  19,896
--
-- THAT LAST NUMBER DECIDES WHICH UPGRADE COMES FIRST. The binding constraint in this company is that
-- not one lead of 22,265 meets the founder's mandatory six, and what they are missing is documents. A
-- supplier who can photograph a trade licence into WhatsApp and have it land on his file is worth more
-- than any amount of conversational finesse. So this builds two things: the memory that was missing,
-- and the one action that moves the constraint.
--
-- WHAT THIS STILL DOES NOT DO, stated so nobody reads more into it. It cannot cancel, refund or price
-- anything, and it should not: refunds are the founder's alone. It is not proactive yet. And the edge
-- function must still fetch the media bytes from Twilio and put them in storage; this is the database
-- half, which decides WHAT a file is, WHOSE it is, and what changes when it arrives.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. MEMORY. Recording a turn is what makes a conversation exist.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_wa_record_turn(
  p_phone      text,
  p_direction  text,
  p_body       text        default null,
  p_media_url  text        default null,
  p_media_kind text        default null,
  p_transcript text        default null,
  p_intent     text        default null,
  p_answered_by text       default null,
  p_fact_pack  jsonb       default null,
  p_model      text        default null,
  p_cost_aed   numeric     default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_conv   record;
  v_lead   bigint;
  v_cust   uuid;
  v_kind   text := 'unknown';
  v_pid    text;
  v_turn   bigint;
begin
  if v_digits = '' then
    return jsonb_build_object('ok', false, 'reason', 'No usable phone number on the message.');
  end if;

  v_lead := public.fn_wa_lead_id(p_phone);
  if v_lead is not null then
    v_kind := 'lead'; v_pid := v_lead::text;
  else
    select id into v_cust from public.customers
     where regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = v_digits limit 1;
    if v_cust is not null then v_kind := 'customer'; v_pid := v_cust::text; end if;
  end if;

  insert into public.wa_conversation (phone_e164, party_kind, party_id, message_count,
                                      window_opened_at, window_expires_at)
  values (v_digits, v_kind, v_pid, 0,
          case when p_direction = 'in' then now() else null end,
          case when p_direction = 'in' then now() + interval '24 hours' else null end)
  on conflict (phone_e164) do update set
      last_seen_at   = now(),
      party_kind     = coalesce(excluded.party_kind, wa_conversation.party_kind),
      party_id       = coalesce(excluded.party_id,   wa_conversation.party_id),
      -- An INBOUND message opens or re-opens the 24-hour service window. An outbound one never does,
      -- which is the whole point of the rule: we cannot extend our own permission to keep talking.
      window_opened_at  = case when p_direction = 'in' then now() else wa_conversation.window_opened_at end,
      window_expires_at = case when p_direction = 'in' then now() + interval '24 hours'
                               else wa_conversation.window_expires_at end
  returning * into v_conv;

  update public.wa_conversation
     set message_count = message_count + 1,
         last_intent   = coalesce(p_intent, last_intent)
   where id = v_conv.id
  returning * into v_conv;

  insert into public.wa_turn (conversation_id, direction, body, media_url, media_kind, transcript,
                              transcript_source, intent_key, answered_by, fact_pack, model_id, cost_aed)
  values (v_conv.id, p_direction, p_body, p_media_url, p_media_kind, p_transcript,
          case when p_transcript is not null then 'model' else 'none' end,
          p_intent, p_answered_by, p_fact_pack, p_model, p_cost_aed)
  returning id into v_turn;

  return jsonb_build_object(
    'ok', true, 'conversation_id', v_conv.id, 'turn_id', v_turn,
    'party_kind', v_conv.party_kind, 'party_id', v_conv.party_id,
    'message_count', v_conv.message_count,
    'window_expires_at', v_conv.window_expires_at,
    'window_open', (v_conv.window_expires_at is not null and v_conv.window_expires_at > now())
  );
end;
$fn$;

revoke execute on function public.fn_wa_record_turn(text,text,text,text,text,text,text,text,jsonb,text,numeric) from public;

comment on function public.fn_wa_record_turn is
  'Records one WhatsApp turn and maintains the conversation. Only an INBOUND message opens the 24-hour service window, because we cannot extend our own permission to keep talking.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE ACTION THAT MOVES THE CONSTRAINT. A document arrives and lands on a file.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.wa_document_intake (
  id             bigserial primary key,
  received_at    timestamptz not null default now(),
  phone_e164     text        not null,
  lead_id        bigint      references public.leads(id),
  turn_id        bigint      references public.wa_turn(id),

  media_url      text,
  storage_path   text,
  media_kind     text,
  caption        text,

  -- What we think it is, and how sure. A guess recorded as a guess can be corrected; a guess recorded
  -- as a fact becomes a trade licence that is actually a photo of a van.
  classified_as  text        check (classified_as in ('licence','profile','signed_terms','unknown')),
  classified_by  text        check (classified_by in ('caption','filename','model','human')),
  confidence     text        check (confidence in ('high','low')),

  attached       boolean     not null default false,
  attach_note    text
);

create index if not exists wa_document_intake_lead on public.wa_document_intake (lead_id, received_at desc);

comment on table public.wa_document_intake is
  'Every file a counterparty sends on WhatsApp, what we classified it as and on what evidence. An unattached row is a document waiting for a human decision, not a lost one.';

commit;

create or replace function public.fn_wa_attach_document(
  p_phone        text,
  p_storage_path text,
  p_caption      text default null,
  p_media_kind   text default null,
  p_turn_id      bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_lead   bigint;
  v_cap    text := lower(coalesce(p_caption, '') || ' ' || coalesce(p_storage_path, ''));
  v_kind   text := 'unknown';
  v_by     text := 'caption';
  v_conf   text := 'low';
  v_intake bigint;
  v_before jsonb;
  v_after  jsonb;
  v_reply  text;
begin
  v_lead := public.fn_wa_lead_id(p_phone);

  -- Classify from the caption and the filename. Deliberately conservative: an unrecognised document
  -- is recorded as unknown and waits, rather than being filed as a trade licence on a guess.
  if v_cap ~ '(trade|licence|license|رخصة|رخصه)' then
    v_kind := 'licence'; v_conf := 'high';
  elsif v_cap ~ '(profile|company profile|brochure|ملف|بروفايل)' then
    v_kind := 'profile'; v_conf := 'high';
  elsif v_cap ~ '(terms|t&c|agreement|signed|شروط|اتفاقية)' then
    v_kind := 'signed_terms'; v_conf := 'high';
  end if;

  if v_lead is not null then
    v_before := public.fn_supplier_mandatory_check(v_lead);
  end if;

  insert into public.wa_document_intake
    (phone_e164, lead_id, turn_id, storage_path, media_kind, caption,
     classified_as, classified_by, confidence, attached, attach_note)
  values (regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'), v_lead, p_turn_id,
          p_storage_path, p_media_kind, p_caption, v_kind, v_by, v_conf, false, null)
  returning id into v_intake;

  -- Attach ONLY when we know whose file it is and what it is. Anything else waits for a person.
  if v_lead is null then
    v_reply := 'Thank you. I could not match this number to a registered company yet, so I have kept '
            || 'your file and someone will match it to your account. If you reply with the email '
            || 'address you registered with, I can do it straight away.';
    update public.wa_document_intake set attach_note = 'No lead matches this number.' where id = v_intake;

  elsif v_kind = 'unknown' then
    v_reply := 'Thank you, I have saved that to your file. I could not tell which document it is, so '
            || 'to file it correctly please tell me: is it your trade licence, your company profile, '
            || 'or the signed terms?';
    update public.wa_document_intake set attach_note = 'Received but unclassified; asked the sender.' where id = v_intake;

  else
    if v_kind = 'licence' then
      update public.leads set license_doc_path = p_storage_path where id = v_lead;
    elsif v_kind = 'profile' then
      update public.leads set company_profile_doc_path = p_storage_path where id = v_lead;
    elsif v_kind = 'signed_terms' then
      update public.leads set signed_terms_path = p_storage_path where id = v_lead;
    end if;

    update public.wa_document_intake
       set attached = true,
           attach_note = format('Attached as %s to lead %s.', v_kind, v_lead)
     where id = v_intake;

    v_after := public.fn_supplier_mandatory_check(v_lead);

    -- Tell them what changed and what is left. This is the difference between a receipt and a service.
    if coalesce((v_after->>'complete')::boolean, false) then
      v_reply := 'Got it, that is your ' || replace(v_kind,'_',' ') || ' saved. Your file is now '
              || 'complete and it goes to our team for verification. I will message you here when it '
              || 'is approved.';
    else
      v_reply := 'Got it, that is your ' || replace(v_kind,'_',' ') || ' saved. Still needed: '
              || (select string_agg(value #>> '{}', ', ') from jsonb_array_elements(v_after->'missing'))
              || '. You can send them here the same way.';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'intake_id', v_intake,
    'lead_id', v_lead,
    'classified_as', v_kind,
    'confidence', v_conf,
    'attached', (v_lead is not null and v_kind <> 'unknown'),
    'mandatory_before', v_before,
    'mandatory_after', v_after,
    'reply', v_reply
  );
end;
$fn$;

revoke execute on function public.fn_wa_attach_document(text,text,text,text,bigint) from public;

comment on function public.fn_wa_attach_document is
  'A document sent on WhatsApp is classified, attached to the sender''s lead, and answered with what is now missing. Attaches only when both the owner and the document type are known; anything else is kept and escalated rather than filed on a guess.';
