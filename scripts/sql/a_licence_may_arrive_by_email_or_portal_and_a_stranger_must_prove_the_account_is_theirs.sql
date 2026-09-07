-- A LICENCE MAY ARRIVE BY EMAIL OR PORTAL, AND A STRANGER MUST PROVE THE ACCOUNT IS THEIRS
--
-- Build spec §6: "Accept the licence on every intake path the company offers -- WhatsApp, email and
-- the portal -- with the same classification, the same attachment and the same receipt. A document
-- that arrives on a path with no handler is a document the company lost."
--
-- Build spec §7: "When the sender does not match a known party, do not guess and do not attach.
-- Challenge the identity through a channel the ACCOUNT already owns."
--
-- WhatsApp intake was built (fn_wa_attach_document). Email and portal had no handler at all, so a
-- supplier who replied to the invitation email with their trade licence attached was sending it into
-- a mailbox nothing read. That is §6's "document the company lost", exactly.
--
-- THE §7 TRAP, AND WHY THE CHALLENGE IS SHAPED THIS WAY. The WhatsApp path already tells an
-- unmatched sender: "if you reply with the email address you registered with, I can do it straight
-- away." Nothing implemented that, and the obvious implementation is the dangerous one -- match on
-- the email they typed and attach. That hands any stranger the ability to name a company and file
-- documents against it, and worse, to be told whether that company exists.
--
-- So the code below never trusts the supplied address. It looks the account up, and sends a
-- single-use code TO THE ADDRESS ALREADY ON THE ACCOUNT. Only somebody who can read the account's
-- own mail can complete it. And the answer returned to the challenger is IDENTICAL whether or not
-- the account exists -- a different answer for "no such company" is an account-enumeration oracle,
-- which is the same leak as a login page that says "no such user".
--
-- This is the founder's standing rule expressed in code: a phone may CONFIRM, never SELECT. The
-- number proves you hold the handset; the email of record proves you hold the account.

-- ---------------------------------------------------------------------------------------------
-- 1. ONE INTAKE LEDGER FOR THE PATHS THAT HAD NONE
-- ---------------------------------------------------------------------------------------------
create table if not exists public.support_document_intake (
  intake_id      bigserial primary key,
  received_at    timestamptz not null default now(),
  channel        text not null,
  sender_ref     text not null,
  lead_id        bigint references public.leads(id),
  case_id        bigint references public.support_case(case_id),
  storage_path   text not null,
  media_kind     text,
  caption        text,
  classified_as  text not null,
  classified_by  text not null,
  confidence     text not null,
  attached       boolean not null default false,
  attach_note    text not null,

  constraint support_document_intake_channel_ck check (channel in ('email','portal')),
  constraint support_document_intake_class_ck check (classified_as in ('licence','profile','signed_terms','unknown')),
  constraint support_document_intake_by_ck check (classified_by in ('caption','filename','declared','model','human')),
  constraint support_document_intake_conf_ck check (confidence in ('high','low')),
  -- ATTACHED MEANS BOTH FACTS WERE KNOWN. A row cannot claim it filed a document without an owner
  -- and a type; "filed on a guess" is what the WhatsApp path already refuses and this must match it.
  constraint support_document_intake_attached_ck check (
    not attached or (lead_id is not null and classified_as <> 'unknown'))
);

create index if not exists support_document_intake_lead_idx
  on public.support_document_intake (lead_id, received_at desc);
create index if not exists support_document_intake_unattached_idx
  on public.support_document_intake (received_at desc) where not attached;

comment on table public.support_document_intake is
  'Documents arriving by email or portal -- the two paths §6 named that had no handler. Same classification and same receipt as the WhatsApp path; an unattached row is a document being held, never a document lost.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE IDENTITY CHALLENGE (§7)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.support_identity_challenge (
  challenge_id   bigserial primary key,
  created_at     timestamptz not null default now(),
  channel        text not null,
  sender_ref     text not null,
  claimed_email  text,
  -- The account this challenge is FOR, and the address the code actually went to. They are recorded
  -- separately on purpose: the whole security property is that sent_to came off the account, not off
  -- the message.
  lead_id        bigint references public.leads(id),
  sent_to        text,
  code_hash      text not null,
  expires_at     timestamptz not null,
  attempts       int not null default 0,
  consumed_at    timestamptz,
  outcome        text,

  constraint support_identity_challenge_outcome_ck check (
    outcome is null or outcome in ('verified','expired','exhausted','abandoned')),
  -- A CODE IS NEVER STORED. Only its hash, so a leak of this table is not a leak of live codes.
  constraint support_identity_challenge_hash_ck check (code_hash ~ '^[0-9a-f]{64}$'),
  constraint support_identity_challenge_attempts_ck check (attempts between 0 and 5)
);

create index if not exists support_identity_challenge_open_idx
  on public.support_identity_challenge (sender_ref, created_at desc) where consumed_at is null;

comment on table public.support_identity_challenge is
  'A single-use code sent to the address ALREADY on the account -- never to the address the unmatched sender supplied. Stored as a hash, capped at five attempts, and expiring. lead_id and sent_to are recorded apart from claimed_email because the security property is precisely that they did not come from the message.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE SHARED CLASSIFIER. One implementation, so the three paths cannot drift apart.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_document_classify(p_caption text, p_path text, p_declared text default null)
returns jsonb
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
declare v_cap text := lower(coalesce(p_caption, '') || ' ' || coalesce(p_path, ''));
begin
  -- A DECLARED TYPE BEATS A GUESS. The portal has a dropdown; when the uploader has told us what the
  -- file is, reading the filename instead would be replacing knowledge with inference.
  if p_declared in ('licence','profile','signed_terms') then
    return jsonb_build_object('kind', p_declared, 'by', 'declared', 'confidence', 'high');
  end if;
  if v_cap ~ '(trade|licence|license|رخصة|رخصه)' then
    return jsonb_build_object('kind', 'licence', 'by', 'caption', 'confidence', 'high');
  elsif v_cap ~ '(profile|company profile|brochure|ملف|بروفايل)' then
    return jsonb_build_object('kind', 'profile', 'by', 'caption', 'confidence', 'high');
  elsif v_cap ~ '(terms|t&c|agreement|signed|شروط|اتفاقية)' then
    return jsonb_build_object('kind', 'signed_terms', 'by', 'caption', 'confidence', 'high');
  end if;
  return jsonb_build_object('kind', 'unknown', 'by', 'caption', 'confidence', 'low');
end $function$;

comment on function public.fn_document_classify is
  'The one classifier the WhatsApp, email and portal paths share, so §6''s "the same classification" is a fact about the code rather than a promise about three copies of it.';

-- ---------------------------------------------------------------------------------------------
-- 4. INTAKE ON EMAIL AND PORTAL
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_receive_document(
  p_channel      text,
  p_sender_ref   text,
  p_storage_path text,
  p_caption      text default null,
  p_media_kind   text default null,
  p_declared     text default null,
  p_lead_id      bigint default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  c jsonb; v_lead bigint; v_id bigint; v_note text; v_reply text;
  v_before jsonb; v_after jsonb; v_grant jsonb; v_missing text;
begin
  v_grant := public.fn_support_may_act('document');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;
  if p_channel not in ('email','portal') then
    return jsonb_build_object('ok', false, 'reason',
      'this function serves the email and portal paths; WhatsApp has fn_wa_attach_document.');
  end if;
  if coalesce(btrim(p_storage_path), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'no stored file. A receipt for a document that was never stored is the lost-document failure with a friendlier message.');
  end if;

  -- WHO SENT IT. The portal already knows -- the session is the identity, which is why it may pass a
  -- lead directly. Email has only the From address, so it is matched against the address of record.
  if p_channel = 'portal' then
    v_lead := p_lead_id;
  else
    select id into v_lead from public.leads
     where lower(email) = lower(btrim(p_sender_ref)) order by id limit 1;
  end if;

  c := public.fn_document_classify(p_caption, p_storage_path, p_declared);

  if v_lead is not null then v_before := public.fn_supplier_mandatory_check(v_lead); end if;

  if v_lead is null then
    v_note := 'No account matches this sender. Held, and an identity challenge is the only route to attaching it.';
    v_reply := 'Thank you -- I have your file safely. I could not match it to a registered account '
            || 'from this address, so I have not filed it yet. Reply with the email address you '
            || 'registered with and I will send a short code to that address to confirm it is you.';
  elsif (c->>'kind') = 'unknown' then
    v_note := 'Owner known, type not. Held rather than filed on a guess.';
    v_reply := 'Thank you, I have saved that to your file. I could not tell which document it is, so '
            || 'to file it correctly please tell me: is it your trade licence, your company profile, '
            || 'or the signed terms?';
  else
    v_note := format('Attached as %s to lead %s.', c->>'kind', v_lead);
  end if;

  insert into public.support_document_intake
    (channel, sender_ref, lead_id, storage_path, media_kind, caption,
     classified_as, classified_by, confidence, attached, attach_note)
  values (p_channel, p_sender_ref, v_lead, p_storage_path, p_media_kind, p_caption,
          c->>'kind', c->>'by', c->>'confidence',
          v_lead is not null and (c->>'kind') <> 'unknown', coalesce(v_note, ''))
  returning intake_id into v_id;

  if v_lead is not null and (c->>'kind') <> 'unknown' then
    if (c->>'kind') = 'licence' then
      update public.leads set license_doc_path = p_storage_path where id = v_lead;
    elsif (c->>'kind') = 'profile' then
      update public.leads set company_profile_doc_path = p_storage_path where id = v_lead;
    else
      update public.leads set signed_terms_path = p_storage_path where id = v_lead;
    end if;

    v_after := public.fn_supplier_mandatory_check(v_lead);
    -- THE RECEIPT SAYS WHAT IS STILL MISSING, the same as the WhatsApp path. A receipt that only
    -- confirms arrival leaves the supplier believing they are finished when they are not, which is
    -- how 81 invitations became 0 registrations.
    if coalesce((v_after->>'complete')::boolean, false) then
      v_reply := 'Got it -- your ' || replace(c->>'kind','_',' ') || ' is saved. Your file is now '
              || 'complete and goes for verification. I will let you know when it is approved.';
    else
      select string_agg(value #>> '{}', ', ') into v_missing
        from jsonb_array_elements(v_after->'missing');
      v_reply := 'Got it -- your ' || replace(c->>'kind','_',' ') || ' is saved. Still needed: '
              || coalesce(v_missing, '(nothing listed)') || '. You can send them the same way.';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'intake_id', v_id, 'channel', p_channel,
    'lead_id', v_lead, 'classified_as', c->>'kind', 'confidence', c->>'confidence',
    'attached', v_lead is not null and (c->>'kind') <> 'unknown',
    'needs_identity_challenge', v_lead is null,
    'mandatory_before', v_before, 'mandatory_after', v_after, 'reply', v_reply);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 5. THE CHALLENGE ITSELF (§7). Two halves: open one, and answer one.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_open_identity_challenge(
  p_channel     text,
  p_sender_ref  text,
  p_claimed_email text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lead bigint; v_to text; v_code text; v_id bigint; v_grant jsonb; v_open int;
begin
  v_grant := public.fn_support_may_act('document');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason');
  end if;

  -- RATE LIMIT PER SENDER, not per account. Limiting per account would let a stranger lock a real
  -- supplier out of their own verification by spamming challenges at them.
  select count(*) into v_open from public.support_identity_challenge
   where sender_ref = p_sender_ref and created_at > now() - interval '1 hour';
  if v_open >= 5 then
    return jsonb_build_object('ok', true, 'challenge_opened', false, 'reason', 'rate_limited',
      'message', 'I have sent several codes to this account recently. Please use the most recent one, or try again in an hour.');
  end if;

  select id, email into v_lead, v_to from public.leads
   where lower(email) = lower(btrim(p_claimed_email)) order by id limit 1;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  if v_lead is not null then
    insert into public.support_identity_challenge
      (channel, sender_ref, claimed_email, lead_id, sent_to, code_hash, expires_at)
    values (p_channel, p_sender_ref, p_claimed_email, v_lead, v_to,
            encode(sha256(convert_to(v_code || '|' || v_lead::text, 'UTF8')), 'hex'), now() + interval '15 minutes')
    returning challenge_id into v_id;

    insert into public.support_notification (dedupe_key, case_id, purpose, channel, recipient,
      subject, body, anonymity_checked_at, anonymity_result)
    values ('idchallenge|' || v_id::text, null, 'identity_challenge', 'email', v_to,
            'Your QuotesDone confirmation code',
            'Your confirmation code is ' || v_code || '. It expires in 15 minutes. If you did not ask '
            || 'to confirm a document upload, you can ignore this message and nothing will be filed.',
            now(), jsonb_build_object('safe', true, 'note', 'code to the address of record; no counterparty data'));
  end if;

  -- THE SAME ANSWER EITHER WAY. Whether or not that account exists, the sender is told a code was
  -- sent to the address they named. Saying "no account with that email" would turn this into a
  -- free tool for discovering who is registered with us.
  return jsonb_build_object('ok', true, 'challenge_opened', v_lead is not null,
    'message', 'I have sent a 6-digit code to ' || p_claimed_email || '. Reply with the code and I '
            || 'will file your document against that account. The code expires in 15 minutes.');
end $function$;

create or replace function public.fn_support_answer_identity_challenge(
  p_sender_ref text,
  p_code       text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare ch record; v_filed int := 0;
begin
  select * into ch from public.support_identity_challenge
   where sender_ref = p_sender_ref and consumed_at is null
   order by created_at desc limit 1 for update;

  if not found then
    return jsonb_build_object('ok', false, 'verified', false, 'reason', 'no_open_challenge',
      'message', 'I do not have a code outstanding for you. Send me the email address you registered with and I will start again.');
  end if;

  if ch.expires_at <= now() then
    update public.support_identity_challenge
       set consumed_at = now(), outcome = 'expired' where challenge_id = ch.challenge_id;
    return jsonb_build_object('ok', true, 'verified', false, 'reason', 'expired',
      'message', 'That code has expired. Send me the email address again and I will issue a fresh one.');
  end if;

  if ch.attempts >= 4 then
    update public.support_identity_challenge
       set attempts = ch.attempts + 1, consumed_at = now(), outcome = 'exhausted'
     where challenge_id = ch.challenge_id;
    return jsonb_build_object('ok', true, 'verified', false, 'reason', 'exhausted',
      'message', 'Too many attempts on that code, so I have cancelled it. Send me the email address again for a new one.');
  end if;

  if encode(sha256(convert_to(btrim(p_code) || '|' || ch.lead_id::text, 'UTF8')), 'hex') <> ch.code_hash then
    update public.support_identity_challenge
       set attempts = ch.attempts + 1 where challenge_id = ch.challenge_id;
    return jsonb_build_object('ok', true, 'verified', false, 'reason', 'wrong_code',
      'attempts_left', 4 - ch.attempts,
      'message', 'That code does not match. Please check the email and try again.');
  end if;

  update public.support_identity_challenge
     set consumed_at = now(), outcome = 'verified' where challenge_id = ch.challenge_id;

  -- NOTE ON THE ORDERING BELOW: received_at alone is not a tie-break. Two documents that arrive in
  -- the SAME transaction carry the same now(), so "the latest licence" was decided by whichever row
  -- the planner returned first. The intake_id settles it, and the probe that caught this is the
  -- reason the tie-break is here rather than a comment saying it cannot happen.
  -- NOW the held documents may be filed -- and only the ones this sender actually sent, on this
  -- channel. Verifying an identity does not adopt every orphan document in the table.
  update public.support_document_intake i
     set lead_id = ch.lead_id, attached = classified_as <> 'unknown',
         attach_note = case when classified_as = 'unknown'
           then 'Owner confirmed by identity challenge; type still unknown, so still held.'
           else format('Attached as %s to lead %s after identity challenge %s.', classified_as, ch.lead_id, ch.challenge_id) end
   where i.sender_ref = p_sender_ref and i.lead_id is null;
  get diagnostics v_filed = row_count;

  update public.leads l set
    license_doc_path = coalesce((select storage_path from public.support_document_intake
      where lead_id = ch.lead_id and classified_as = 'licence' order by received_at desc, intake_id desc limit 1), l.license_doc_path),
    company_profile_doc_path = coalesce((select storage_path from public.support_document_intake
      where lead_id = ch.lead_id and classified_as = 'profile' order by received_at desc, intake_id desc limit 1), l.company_profile_doc_path),
    signed_terms_path = coalesce((select storage_path from public.support_document_intake
      where lead_id = ch.lead_id and classified_as = 'signed_terms' order by received_at desc, intake_id desc limit 1), l.signed_terms_path)
  where l.id = ch.lead_id;

  return jsonb_build_object('ok', true, 'verified', true, 'lead_id', ch.lead_id,
    'documents_released', v_filed,
    'mandatory', public.fn_supplier_mandatory_check(ch.lead_id),
    'message', 'Confirmed, thank you. I have filed the document you sent against your account.');
end $function$;

revoke execute on function public.fn_support_receive_document(text,text,text,text,text,text,bigint) from public;
revoke execute on function public.fn_support_receive_document(text,text,text,text,text,text,bigint) from anon;
revoke execute on function public.fn_support_receive_document(text,text,text,text,text,text,bigint) from authenticated;
revoke execute on function public.fn_support_open_identity_challenge(text,text,text) from public;
revoke execute on function public.fn_support_open_identity_challenge(text,text,text) from anon;
revoke execute on function public.fn_support_open_identity_challenge(text,text,text) from authenticated;
revoke execute on function public.fn_support_answer_identity_challenge(text,text) from public;
revoke execute on function public.fn_support_answer_identity_challenge(text,text) from anon;
revoke execute on function public.fn_support_answer_identity_challenge(text,text) from authenticated;
revoke execute on function public.fn_document_classify(text,text,text) from public;
revoke execute on function public.fn_document_classify(text,text,text) from anon;
revoke execute on function public.fn_document_classify(text,text,text) from authenticated;
