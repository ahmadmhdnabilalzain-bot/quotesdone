-- EVERY SUPPLIER INVITATION OFFERS WHATSAPP, A MODEL READS THE YES, THE NUMBER CONFIRMS ITSELF, AND ONLY THEN DO JOB
-- REQUESTS GO THERE.
--
-- Seat: marketing (the offer and the opt-in), with sales_engineer (the supplier's reply is answered on his desk). Agent:
-- L2_OPTIN. 16 Nov 2026. Founder ledger 1184 (12 Oct): "supplier acquisition must use every safe channel beyond email
-- (WhatsApp, LinkedIn, others) ... nothing that risks bans"; 1373 (27 Oct): "if whatsapp invitations are safe of course
-- proceed"; 1301: "safer to not send links"; 1341: an opt-in is the button or a yes to a question that asks for consent;
-- 1663/1664 (12 Nov): what a person wrote is understood by the model, never by a keyword rule.
--
-- MEASURED BEFORE WRITING (16 Nov 2026, production, SELECT on tables and the catalogue only):
--   * supplier_whatsapp_optin 0 rows, supplier_whatsapp_consent_ask 0 rows: nobody has ever been asked, so nobody has
--     said yes. The campaign mail (send_outbox/m365_lane.ts, variants A/B/C and the last note) offers no WhatsApp at all.
--   * fn_wa_optin_rule decided a "yes" by keyword (fn_wa_is_affirmative: a whole reply of yes words and courtesy words).
--     "Yes, put me on WhatsApp" is NOT a yes to it ("put", "on", "whatsapp" are neither), nor is "نعم أرسلوها على الواتساب".
--   * A job request reaches WhatsApp only as a twin of its e-mail (trg_wa_fanout) addressed by a03
--     (fn_notifications_whatsapp_goes_to_a_confirmed_number), both reading fn_whatsapp_destination: the portal's own
--     "Is this number on WhatsApp?" answer ("We can send your updates on WhatsApp as well as by email") with the number
--     confirmed by code. Nothing else can address a supplier's WhatsApp row. An opt-in recorded by any other door was
--     read by nobody when a job request was sent.
--
-- WHAT THIS CHANGES
--   1. fn_wa_job_request_offer(): the offer sentence, word for word, that every invitation and every e-mail reply to a
--      supplier now carries (_shared/whatsapp_offer.ts WHATSAPP_OFFER is the same text; whatsapp_offer.test.ts compares).
--      English only: suppliers are written to in English (founder, 28 Sep 2026); they may answer in Arabic.
--   2. supplier_whatsapp_optin gains answer_read_by (the model that read the yes), phone_confirmed_at and
--      phone_confirmed_how. A WhatsApp-sourced row is confirmed by its origin (the number wrote to us); an e-mail or call
--      row is confirmed only when the supplier sends its code from that WhatsApp (5 below).
--   3. fn_wa_optin_rule(source, payload, question, answer, read_by): the 4-argument rule is DROPPED (DROPPED.txt) and
--      replaced. The button is unchanged. For a consent reply the message answered must carry the consent question
--      (fn_wa_consent_question) or the offer (fn_wa_job_request_offer) - a fact code checks - and the ANSWER counts only
--      when a model read it as a yes (read_by names it). No keyword decides consent any more; fn_wa_is_affirmative has
--      no caller after this file. The trigger and the three writers pass read_by.
--   4. fn_supplier_whatsapp_offer_state(email): what the reply to this supplier must say about WhatsApp (offer, pending,
--      consented, declined). fn_supplier_whatsapp_optin_from_mail(inbound_id, answer, read_by): the mailbox reading
--      model said this e-mail agrees; code checks the sender is a lead by his exact address, that one of our mails to
--      that address carried the offer, and that he has not said no to WhatsApp; it records a PENDING consent and issues
--      an 8-digit code (sha256 only is kept) for the reply to carry.
--   5. fn_supplier_whatsapp_optin_confirm(phone, code): the supplier sends the code from his WhatsApp (wa_inbound
--      optin_code.ts, the same proof as a company member's number, fn_supplier_member_confirm_phone). The number that sent
--      it is the number recorded: consent with source email_consent_reply, the question and his answer, the model that
--      read it, opted_in_at and phone_confirmed_at. Five wrong codes from a number in 24 hours stop that number for the
--      day; a number that already names another party is refused (a phone tail never joins two people).
--   6. fn_supplier_job_request_whatsapp(lead, email): THE CHANNEL GATE for job requests (new_inquiry, rfq_invite,
--      rfq_addendum). WhatsApp only to a number the supplier agreed to and confirmed: the portal answer (as before), else
--      his latest confirmed opt-in. 'none' (he said no, or STOP) wins over both. a03 and fn_wa_fanout read it for those
--      types; every other type is exactly as before.
-- NOT CHANGED: the WhatsApp marketing invitation and its switches (fn_wa_supplier_invite_queue still needs
-- wa_supplier_invite_golive); fn_whatsapp_destination and every non-job notice; the STOP path.
-- Apply AFTER send_outbox, email_triage and wa_inbound are deployed (the 'since' below is the apply time: a campaign mail
-- sent after it carried the offer). Prevented by: every_supplier_invitation_offers_whatsapp_and_a_model_read_yes_opens_job_requests_there_probe.sql
-- (local Postgres 16), _shared/whatsapp_offer.test.ts, send_outbox/m365_lane.test.ts, email_triage/supplier_mailbox_reading.test.ts,
-- wa_inbound/optin_code.test.ts.
-- Redefined from PRODUCTION bodies read 16 Nov 2026: fn_wa_fanout 140cbbe5c883b49793fc08eff57a42bc,
-- fn_notifications_whatsapp_goes_to_a_confirmed_number be095b2d9ea5c39dbde4543eb2b924a7, fn_wa_optin_rule
-- cdaf4e769d1cb8b43d883ca61ce60391, fn_supplier_whatsapp_optin_obeys_the_rule 2ed3d67f6f99584d0e3150a518ac544b,
-- fn_supplier_whatsapp_optin_record 1dd566723df3962a35759506cd7c94f3, fn_marketing_files_wa_invite_reply
-- e3ac3e042881548466599b72c03b6667.

set local lock_timeout = '3s';

-- 1. the offer
create or replace function public.fn_wa_job_request_offer()
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select 'Want job requests on WhatsApp too? Reply "WhatsApp" and we will send you a code to confirm your number.'::text
$fn$;
revoke execute on function public.fn_wa_job_request_offer() from public, anon, authenticated;

-- When the offer went live in the campaign mail: send_outbox builds the campaign text in code (campaignMail) and stores the
-- row's old body, so a campaign row SENT after this time carried the offer. Set once, at apply.
insert into public.decision_policy (key, value, description)
values ('wa_job_request_offer', jsonb_build_object('since', now()),
        'When every supplier invitation began to carry fn_wa_job_request_offer (every_supplier_invitation_offers_whatsapp_and_a_model_read_yes_opens_job_requests_there.sql).')
on conflict (key) do nothing;

-- 2. who read the yes, and whether the number is confirmed
alter table public.supplier_whatsapp_optin add column if not exists answer_read_by text;
alter table public.supplier_whatsapp_optin add column if not exists phone_confirmed_at timestamptz;
alter table public.supplier_whatsapp_optin add column if not exists phone_confirmed_how text;
update public.supplier_whatsapp_optin set phone_confirmed_at = opted_in_at, phone_confirmed_how = 'the number wrote to us on WhatsApp'
 where source in ('wa_button', 'wa_consent_reply') and phone_confirmed_at is null;

-- 4b. a yes by e-mail waiting for its number; and wrong codes per number (the brake on guessing)
create table if not exists public.supplier_whatsapp_optin_pending (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.leads(id) on delete cascade,
  inbound_id bigint,
  consent_question text not null,
  consent_answer text not null,
  answer_read_by text not null check (btrim(answer_read_by) <> ''),
  code_sha text not null,
  code_expires timestamptz not null,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_why text,
  optin_id bigint
);
create index if not exists supplier_whatsapp_optin_pending_open_idx on public.supplier_whatsapp_optin_pending (code_sha) where closed_at is null;
create index if not exists supplier_whatsapp_optin_pending_lead_idx on public.supplier_whatsapp_optin_pending (lead_id, created_at desc);
alter table public.supplier_whatsapp_optin_pending enable row level security;
drop policy if exists supplier_whatsapp_optin_pending_service_role_only on public.supplier_whatsapp_optin_pending;
create policy supplier_whatsapp_optin_pending_service_role_only on public.supplier_whatsapp_optin_pending
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_whatsapp_optin_pending from anon, authenticated;

create table if not exists public.supplier_whatsapp_optin_code_miss (
  id bigint generated always as identity primary key,
  phone text not null,
  at timestamptz not null default now()
);
create index if not exists supplier_whatsapp_optin_code_miss_phone_idx on public.supplier_whatsapp_optin_code_miss (phone, at desc);
alter table public.supplier_whatsapp_optin_code_miss enable row level security;
drop policy if exists supplier_whatsapp_optin_code_miss_service_role_only on public.supplier_whatsapp_optin_code_miss;
create policy supplier_whatsapp_optin_code_miss_service_role_only on public.supplier_whatsapp_optin_code_miss
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_whatsapp_optin_code_miss from anon, authenticated;

-- 3. THE RULE. One signature: the 4-argument rule is dropped so no call is ever ambiguous; a 4-argument call (an edge
-- function deployed before this file) resolves here with read_by null, which a consent reply does not pass.
drop function if exists public.fn_wa_optin_rule(text, text, text, text);
create or replace function public.fn_wa_optin_rule(p_source text, p_button_payload text, p_question text, p_answer text,
                                                   p_read_by text default null)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare
  v_q text := lower(regexp_replace(translate(coalesce(p_question, ''), '’‘“”', '''''""'), '\s+', ' ', 'g'));
begin
  if p_source = 'wa_button' then
    if btrim(coalesce(p_button_payload, '')) = 'supplier_invite_yes' then
      return jsonb_build_object('counts', true, 'why', 'the supplier tapped "Set up my page"'); end if;
    return jsonb_build_object('counts', false, 'why', 'not the "Set up my page" button payload');
  end if;
  if p_source in ('wa_consent_reply', 'email_consent_reply', 'call_consent_reply') then
    -- a fact: the message he answered asked him (the consent question or the job-request offer, word for word)
    if position(lower(public.fn_wa_consent_question()) in v_q) = 0
       and position(lower(translate(public.fn_wa_job_request_offer(), '’‘“”', '''''""')) in v_q) = 0 then
      return jsonb_build_object('counts', false, 'why', 'the message answered did not ask for consent (neither the consent question nor the WhatsApp offer)'); end if;
    if btrim(coalesce(p_answer, '')) = '' then
      return jsonb_build_object('counts', false, 'why', 'there is no answer'); end if;
    -- meaning: a model read the answer as a yes (rulings 1663/1664); the writer calls only when it did, and names it
    if btrim(coalesce(p_read_by, '')) = '' then
      return jsonb_build_object('counts', false, 'why', 'no model read the answer as a yes (a yes is understood by a model, never by a keyword)'); end if;
    return jsonb_build_object('counts', true, 'why', 'the supplier answered yes to the WhatsApp offer, read by ' || btrim(p_read_by));
  end if;
  return jsonb_build_object('counts', false, 'why', 'not a consent source: only the button or a yes to the consent question counts (ledger 1341)');
end $fn$;
revoke execute on function public.fn_wa_optin_rule(text, text, text, text, text) from public, anon, authenticated;

-- the rule on the table itself, reading who read the yes; a WhatsApp-sourced row is confirmed by its origin
create or replace function public.fn_supplier_whatsapp_optin_obeys_the_rule()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := public.fn_wa_optin_rule(new.source, new.button_payload, new.consent_question, new.consent_answer, new.answer_read_by);
begin
  if not (v->>'counts')::boolean then
    raise exception 'supplier_whatsapp_optin refused (ledger 1341): %', v->>'why' using errcode = 'check_violation';
  end if;
  if new.source in ('wa_button', 'wa_consent_reply') and new.phone_confirmed_at is null then
    new.phone_confirmed_at := coalesce(new.opted_in_at, now());
    new.phone_confirmed_how := 'the number wrote to us on WhatsApp';
  end if;
  return new;
end $fn$;

-- the WhatsApp writer: production body; a reply to the consent question counts only when wa_inbound's model read it as a
-- yes and passes p_consent_read_by. One signature (the 3-argument one is dropped).
drop function if exists public.fn_marketing_files_wa_invite_reply(text, text, text);
create or replace function public.fn_marketing_files_wa_invite_reply(p_from text, p_body text, p_button_payload text default null,
                                                                     p_consent_read_by text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '\D', '', 'g');
  v_optins int := 0; l public.leads; v_reply text := btrim(coalesce(p_body, '')); v_id bigint;
  v_ask public.supplier_whatsapp_consent_ask; v_source text; v_rule jsonb;
begin
  if v_phone !~ '^\+[0-9]{8,15}$' then return jsonb_build_object('due', false, 'reason', 'no number'); end if;
  -- (a) the button
  if btrim(coalesce(p_button_payload, '')) <> '' then
    v_source := 'wa_button'; v_rule := public.fn_wa_optin_rule('wa_button', p_button_payload, null, null);
  else
    -- (b) the first reply after an open consent ask on this number (7 days) answers it, yes or not; the ask closes
    select * into v_ask from public.supplier_whatsapp_consent_ask
     where phone = v_phone and answered_at is null and asked_at > now() - interval '7 days'
     order by asked_at desc, id desc limit 1 for update;
    if v_ask.id is not null then
      update public.supplier_whatsapp_consent_ask set answered_at = now(), answer = left(v_reply, 500)
       where phone = v_phone and answered_at is null;
      v_source := 'wa_consent_reply'; v_rule := public.fn_wa_optin_rule('wa_consent_reply', null, v_ask.question, v_reply, p_consent_read_by);
    else
      v_rule := jsonb_build_object('counts', false, 'why', 'a message that is neither the button nor a reply to the consent question');
    end if;
  end if;
  if (v_rule->>'counts')::boolean then
    insert into public.supplier_whatsapp_optin (lead_id, phone, source, button_payload, consent_question, consent_answer, answer_read_by, evidence)
    select x.id, v_phone, v_source, nullif(btrim(coalesce(p_button_payload, '')), ''), v_ask.question,
           case when v_source = 'wa_consent_reply' then left(v_reply, 500) end,
           case when v_source = 'wa_consent_reply' then nullif(btrim(coalesce(p_consent_read_by, '')), '') end,
           (v_rule->>'why') || ' on WhatsApp at ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai'
      from public.leads x
     where (x.phone_e164 = v_phone or x.whatsapp_phone = v_phone) and coalesce(x.whatsapp_opt, '') <> 'none'
    on conflict (lead_id, phone) do nothing;
    get diagnostics v_optins = row_count;
  end if;

  select * into l from public.leads x
   where (x.phone_e164 = v_phone or x.whatsapp_phone = v_phone)
     and not coalesce(x.claimed, false)
     and (x.invited_at is not null or x.invite_status is not null
          or exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.lead_id = x.id and n.status = 'sent'))
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('due', false, 'reason', 'no invited lead without a company page on this number',
                                                 'optins', v_optins, 'optin_why', v_rule->>'why'); end if;
  if v_reply = '' then return jsonb_build_object('due', false, 'reason', 'an empty message', 'optins', v_optins, 'optin_why', v_rule->>'why'); end if;
  v_id := public.fn_seat_handoff('marketing', 'sales_engineer', 'invite.reply', 'leads', l.id::text,
    jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'channel', 'whatsapp', 'from_phone', v_phone,
                       'reply_text', left(v_reply, 4000), 'opted_in', (v_rule->>'counts')::boolean,
                       'ask', case when (v_rule->>'counts')::boolean
                                   then 'Set up the company page for this supplier from the trades it listed in its WhatsApp reply.'
                                   else 'Answer this supplier. This message is not a WhatsApp opt-in (ledger 1341); to message it later, ask the consent question and record the ask with fn_supplier_whatsapp_consent_ask_record.' end));
  -- null = a demo lead (ruling 1199: a demo row files no handoff)
  return jsonb_build_object('due', true, 'reason', 'an invited supplier wrote on WhatsApp', 'lead_id', l.id,
                            'handoff_id', v_id, 'optins', v_optins, 'optin_why', v_rule->>'why');
end $fn$;
revoke execute on function public.fn_marketing_files_wa_invite_reply(text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_marketing_files_wa_invite_reply(text, text, text, text) to service_role;

-- the sales engineer's writer (a yes on a call or by e-mail he read): production body plus who read the yes; such a row is
-- NOT confirmed until the supplier sends a code from the number (fn_supplier_whatsapp_optin_confirm). One signature.
drop function if exists public.fn_supplier_whatsapp_optin_record(bigint, text, text, text, text);
create or replace function public.fn_supplier_whatsapp_optin_record(p_lead_id bigint, p_source text, p_question text, p_answer text,
                                                                    p_phone text default null, p_read_by text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare l public.leads; v_phone text; v_id bigint;
  v_rule jsonb := public.fn_wa_optin_rule(p_source, null, p_question, p_answer, p_read_by);
begin
  if p_source not in ('email_consent_reply', 'call_consent_reply') then
    return jsonb_build_object('ok', false, 'reason', 'p_source is email_consent_reply or call_consent_reply'); end if;
  if not (v_rule->>'counts')::boolean then return jsonb_build_object('ok', false, 'reason', v_rule->>'why'); end if;
  select * into l from public.leads where id = p_lead_id;
  if l.id is null then return jsonb_build_object('ok', false, 'reason', 'no such lead'); end if;
  if coalesce(l.whatsapp_opt, '') = 'none' then return jsonb_build_object('ok', false, 'reason', 'the lead opted out of WhatsApp'); end if;
  v_phone := '+' || regexp_replace(coalesce(p_phone, l.phone_e164, ''), '\D', '', 'g');
  if v_phone !~ '^\+[0-9]{8,15}$' then return jsonb_build_object('ok', false, 'reason', 'no usable number'); end if;
  insert into public.supplier_whatsapp_optin (lead_id, phone, source, consent_question, consent_answer, answer_read_by, evidence)
  values (l.id, v_phone, p_source, p_question, p_answer, btrim(p_read_by),
          'answered yes to the consent question (' || replace(p_source, '_consent_reply', '') || ') at '
          || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai')
  on conflict (lead_id, phone) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'lead_id', l.id, 'phone', v_phone, 'new', v_id is not null, 'why', v_rule->>'why',
                            'confirmed', false, 'next', 'the number is used for job requests only after the supplier sends a code from it');
end $fn$;
revoke execute on function public.fn_supplier_whatsapp_optin_record(bigint, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_whatsapp_optin_record(bigint, text, text, text, text, text) to service_role;

-- 4. what a reply to this supplier says about WhatsApp. One lead by his exact address (the invitation's address, or the
-- address that claimed it); a second match is nobody (an address never joins two companies).
create or replace function public.fn_supplier_whatsapp_lead_by_email(p_email text)
returns bigint language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with m as (select l.id from public.leads l
              where btrim(coalesce(p_email, '')) <> ''
                and (lower(btrim(l.email)) = lower(btrim(p_email)) or lower(btrim(l.claimed_by)) = lower(btrim(p_email))))
  select case when (select count(*) from m) = 1 then (select id from m) end
$fn$;
revoke execute on function public.fn_supplier_whatsapp_lead_by_email(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_whatsapp_lead_by_email(text) to service_role;

create or replace function public.fn_supplier_whatsapp_offer_state(p_email text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_lead bigint := public.fn_supplier_whatsapp_lead_by_email(p_email); l public.leads; v_gate jsonb;
begin
  if v_lead is null then return jsonb_build_object('state', 'not_a_lead'); end if;
  select * into l from public.leads where id = v_lead;
  if coalesce(l.whatsapp_opt, '') = 'none' then return jsonb_build_object('state', 'declined', 'lead_id', v_lead); end if;
  v_gate := public.fn_supplier_job_request_whatsapp(v_lead, null);
  if v_gate->>'to' is not null then return jsonb_build_object('state', 'consented', 'lead_id', v_lead, 'source', v_gate->>'source'); end if;
  if exists (select 1 from public.supplier_whatsapp_optin_pending p where p.lead_id = v_lead and p.closed_at is null and p.code_expires > now()) then
    return jsonb_build_object('state', 'pending', 'lead_id', v_lead); end if;
  return jsonb_build_object('state', 'offer', 'lead_id', v_lead, 'offer', public.fn_wa_job_request_offer());
end $fn$;
revoke execute on function public.fn_supplier_whatsapp_offer_state(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_whatsapp_offer_state(text) to service_role;

-- 4b. the mailbox reading model said this e-mail agrees to job requests on WhatsApp
create or replace function public.fn_supplier_whatsapp_optin_from_mail(p_inbound_id bigint, p_answer text, p_read_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare m public.inbound_messages; v_addr text; v_lead bigint; l public.leads; v_since timestamptz; v_question text;
  v_rule jsonb; v_code text; v_id bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if m.id is null then return jsonb_build_object('ok', false, 'code', 'no_mail'); end if;
  v_addr := lower(coalesce(substring(m.from_email from '<([^<>[:space:]]+@[^<>[:space:]]+)>'), substring(m.from_email from '([^<>[:space:]"]+@[^<>[:space:]"]+)'), ''));
  v_lead := public.fn_supplier_whatsapp_lead_by_email(v_addr);
  if v_lead is null then return jsonb_build_object('ok', false, 'code', 'not_a_lead', 'why', 'the sender is not one supplier by his exact address'); end if;
  select * into l from public.leads where id = v_lead;
  if coalesce(l.whatsapp_opt, '') = 'none' then return jsonb_build_object('ok', false, 'code', 'declined', 'why', 'he said he does not use WhatsApp, or replied STOP'); end if;
  if public.fn_supplier_job_request_whatsapp(v_lead, null)->>'to' is not null then
    return jsonb_build_object('ok', true, 'code', 'already', 'lead_id', v_lead, 'why', 'job requests already reach his confirmed WhatsApp'); end if;
  -- the fact: one of our mails to this address carried the offer (a stored reply with the sentence, or a campaign mail sent
  -- after the offer went into the campaign text)
  select (value->>'since')::timestamptz into v_since from public.decision_policy where key = 'wa_job_request_offer';
  if not exists (select 1 from public.notifications n
                  where lower(btrim(n.to_email)) = v_addr and coalesce(n.channel, 'email') = 'email' and n.status = 'sent'
                    and n.created_at <= m.created_at
                    and (position(public.fn_wa_job_request_offer() in coalesce(n.body, '')) > 0
                         or (n.type in ('supplier_invite', 'supplier_invite_nudge') and v_since is not null and n.sent_at >= v_since))) then
    return jsonb_build_object('ok', false, 'code', 'not_offered', 'why', 'none of our mails to this address offered WhatsApp, so his words answer no consent question');
  end if;
  v_question := public.fn_wa_job_request_offer();
  v_rule := public.fn_wa_optin_rule('email_consent_reply', null, v_question, p_answer, p_read_by);
  if not (v_rule->>'counts')::boolean then return jsonb_build_object('ok', false, 'code', 'rule', 'why', v_rule->>'why'); end if;
  -- one open code per supplier: a newer yes replaces the older code
  update public.supplier_whatsapp_optin_pending set closed_at = now(), closed_why = 'replaced by a newer yes'
   where lead_id = v_lead and closed_at is null;
  -- eight digits from gen_random_uuid (a cryptographic source), never random(); only its sha256 is kept
  v_code := lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))::bit(48)::bigint % 100000000))::text, 8, '0');
  insert into public.supplier_whatsapp_optin_pending (lead_id, inbound_id, consent_question, consent_answer, answer_read_by, code_sha, code_expires)
  values (v_lead, m.id, v_question, left(btrim(p_answer), 500), btrim(p_read_by), encode(sha256(convert_to(v_code, 'UTF8')), 'hex'), now() + interval '7 days')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'code', 'pending', 'lead_id', v_lead, 'pending_id', v_id, 'code_to_send', v_code, 'expires_in_days', 7,
                            'why', v_rule->>'why');
end $fn$;
revoke execute on function public.fn_supplier_whatsapp_optin_from_mail(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_whatsapp_optin_from_mail(bigint, text, text) to service_role;

-- 5. the code sent FROM his WhatsApp confirms the number and records the consent
create or replace function public.fn_supplier_whatsapp_optin_confirm(p_phone text, p_code text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_phone text := '+' || regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'); p public.supplier_whatsapp_optin_pending;
  l public.leads; v_misses int; v_other bigint; v_optin bigint;
begin
  if v_phone !~ '^\+[0-9]{8,15}$' or coalesce(p_code, '') !~ '^[0-9]{8}$' then return jsonb_build_object('ok', false, 'code', 'no_code'); end if;
  select count(*) into v_misses from public.supplier_whatsapp_optin_code_miss where phone = v_phone and at > now() - interval '24 hours';
  if v_misses >= 5 then return jsonb_build_object('ok', false, 'code', 'too_many_tries'); end if;
  select * into p from public.supplier_whatsapp_optin_pending
   where code_sha = encode(sha256(convert_to(p_code, 'UTF8')), 'hex') and closed_at is null and code_expires > now()
   order by id desc limit 1 for update;
  if p.id is null then
    insert into public.supplier_whatsapp_optin_code_miss (phone) values (v_phone);
    return jsonb_build_object('ok', false, 'code', 'no_pending_code');
  end if;
  select * into l from public.leads where id = p.lead_id;
  if coalesce(l.whatsapp_opt, '') = 'none' then
    update public.supplier_whatsapp_optin_pending set closed_at = now(), closed_why = 'he said no to WhatsApp before confirming' where id = p.id;
    return jsonb_build_object('ok', false, 'code', 'declined');
  end if;
  -- a number that already speaks for another party is not joined to this one (a phone tail never joins two people)
  select coalesce(o.lead_id, -1) into v_other from public.fn_whatsapp_owner(v_phone, true) o
   where o.party_kind = 'customer' or o.lead_id is distinct from p.lead_id limit 1;
  if v_other is null then
    select o.lead_id into v_other from public.supplier_whatsapp_optin o
     where o.phone = v_phone and o.lead_id <> p.lead_id and o.phone_confirmed_at is not null limit 1;
  end if;
  if v_other is not null then
    update public.supplier_whatsapp_optin_pending set closed_at = now(), closed_why = 'the number already belongs to another party' where id = p.id;
    return jsonb_build_object('ok', false, 'code', 'number_belongs_to_another');
  end if;
  insert into public.supplier_whatsapp_optin (lead_id, phone, source, consent_question, consent_answer, answer_read_by, evidence,
                                              phone_confirmed_at, phone_confirmed_how)
  values (p.lead_id, v_phone, 'email_consent_reply', p.consent_question, p.consent_answer, p.answer_read_by,
          'answered yes to the WhatsApp offer by e-mail (inbound ' || coalesce(p.inbound_id::text, '?') || ', read by ' || p.answer_read_by
          || ') and sent its code from this WhatsApp at ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai',
          now(), 'the code from his e-mail was sent from this WhatsApp number')
  on conflict (lead_id, phone) do update
     set phone_confirmed_at = now(), phone_confirmed_how = excluded.phone_confirmed_how,
         consent_question = excluded.consent_question, consent_answer = excluded.consent_answer,
         answer_read_by = excluded.answer_read_by, evidence = excluded.evidence, source = excluded.source, opted_in_at = now()
  returning id into v_optin;
  update public.supplier_whatsapp_optin_pending set closed_at = now(), closed_why = 'confirmed', optin_id = v_optin where id = p.id;
  return jsonb_build_object('ok', true, 'lead_id', p.lead_id, 'optin_id', v_optin, 'company_name', l.company_name);
end $fn$;
revoke execute on function public.fn_supplier_whatsapp_optin_confirm(text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_whatsapp_optin_confirm(text, text) to service_role;

-- 6. THE CHANNEL GATE FOR JOB REQUESTS
create or replace function public.fn_supplier_job_request_types()
returns text[] language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select array['new_inquiry', 'rfq_invite', 'rfq_addendum']::text[]
$fn$;
revoke execute on function public.fn_supplier_job_request_types() from public, anon, authenticated;

create or replace function public.fn_supplier_job_request_whatsapp(p_lead bigint, p_email text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare l public.leads; v_to text; o public.supplier_whatsapp_optin;
begin
  select * into l from public.leads x
   where x.id = p_lead or (p_lead is null and p_email is not null and lower(x.claimed_by) = lower(btrim(p_email)))
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('to', null, 'reason', 'no such supplier'); end if;
  if coalesce(l.whatsapp_opt, '') = 'none' then
    return jsonb_build_object('to', null, 'reason', 'not sent on WhatsApp: the supplier said he does not use WhatsApp or replied STOP; email carries this job request'); end if;
  -- his own answer in the portal ("We can send your updates on WhatsApp as well as by email"), number confirmed by code
  v_to := public.fn_whatsapp_destination('supplier', null, l.id, null);
  if v_to is not null then
    return jsonb_build_object('to', v_to, 'source', 'portal_whatsapp_choice', 'at', coalesce(l.whatsapp_verified_at, l.whatsapp_asked_at)); end if;
  -- a yes to the offer or the consent question, with the number confirmed (it wrote to us, or sent its code)
  select * into o from public.supplier_whatsapp_optin x
   where x.lead_id = l.id and x.phone_confirmed_at is not null order by x.phone_confirmed_at desc, x.id desc limit 1;
  if o.id is not null then
    return jsonb_build_object('to', o.phone, 'source', o.source, 'at', o.opted_in_at, 'optin_id', o.id); end if;
  return jsonb_build_object('to', null, 'reason', 'not sent on WhatsApp: the supplier has not agreed to job requests on WhatsApp with a confirmed number; email carries this job request');
end $fn$;
revoke execute on function public.fn_supplier_job_request_whatsapp(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_job_request_whatsapp(bigint, text) to service_role;

-- a03: production body; a supplier's JOB REQUEST on WhatsApp goes only where the gate says
create or replace function public.fn_notifications_whatsapp_goes_to_a_confirmed_number()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_dest text; v_opt text; v_gate jsonb;
begin
  if coalesce(new.channel, '') <> 'whatsapp' or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  if new.to_role = 'supplier' and new.type = any (public.fn_supplier_job_request_types()) then
    v_gate := public.fn_supplier_job_request_whatsapp(new.lead_id, new.to_email);
    if v_gate->>'to' is not null then new.to_phone := v_gate->>'to'; return new; end if;
    new.status := 'skipped';
    new.last_error := v_gate->>'reason';
    return new;
  end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is not null then new.to_phone := v_dest; return new; end if;
  if new.to_role = 'customer' then
    select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(btrim(coalesce(new.to_email, ''))) limit 1;
  else
    select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(btrim(coalesce(new.to_email, '')))) order by l.id limit 1;
  end if;
  new.status := 'skipped';
  new.last_error := case when v_opt = 'none'
    then 'not sent on WhatsApp: the recipient said they do not use WhatsApp; email or SMS carries this message'
    else 'not sent on WhatsApp: no confirmed WhatsApp number on file (an unverified number is never used)' end;
  return new;
end $fn$;

-- the twin: production body; a job request is twinned to the number the gate names, and to nobody without consent
create or replace function public.fn_wa_fanout()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_dest text; v_opt text;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(new.channel, 'email') <> 'email' or new.to_email is null or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  -- a reply answers on the channel the message came in on (3 Nov 2026, sales_engineer): never twinned
  -- (kept from a_supplier_reply_goes_back_from_its_own_mailbox.sql, which this file follows in MANIFEST)
  if new.type = 'inbound_reply' then return new; end if;
  if new.to_role = 'supplier' and new.type = any (public.fn_supplier_job_request_types()) then
    v_dest := public.fn_supplier_job_request_whatsapp(new.lead_id, new.to_email)->>'to';
    if v_dest is null then return new; end if;   -- no consent, no twin: the e-mail carries it
  else
    v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  end if;
  if v_dest is null then
    if new.to_role = 'customer' then
      select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(new.to_email) limit 1;
    else
      select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
    end if;
    -- 'none' is recorded (a03 marks the twin skipped with the reason); unanswered makes no twin.
    -- 3 Nov 2026 (customer_support): the confirmations the founder asked for on both channels always get their twin,
    -- so a missing confirmed number is recorded by a03 with its reason instead of leaving no trace.
    if v_opt is distinct from 'none'
       and new.type not in ('customer_account_active', 'supplier_approved', 'reveal_receipt', 'invoice_ready') then return new; end if;
  end if;
  insert into public.notifications (type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_dest, new.lead_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return new;
end $fn$;
