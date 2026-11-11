-- A REPLY FROM THE SUPPLIER MAILBOX LEAVES ONLY WHEN THE READING OF THE MAIL SAID ANSWER.
-- Assigned: customer_support (the e-mail reply decision and the send gate for supplier_mailbox_reply). 11 Nov 2026.
-- Founder rulings 1633 ("an agent must understand an email before it replies"), 1630 (HIGH effort for anything that decides),
-- 1631 (read the conversation history before replying or sending anything).
--
-- MEASURED 11 Nov 2026 (production htdblwldjkcgjvmqkbeh, read-only):
--   * inbound_messages 1874 (azure-noreply@microsoft.com, 9 Nov), 1994 and 2069 (supportmail@techsupport.microsoft.com,
--     10 Nov) were declined by email_triage (ai_category 'no_auto_reply', "Not answered automatically: internal") and each was
--     answered anyway, 0.1-0.7 s later, with the registration template: notifications 129468, 134514, 138326, kind
--     supplier_mailbox_reply, replied_by sales_engineer. In 30 days 5 of the 19 declined rows to supplier@ were answered
--     (1872, 1873, 1874, 1994, 2069); the other 14 are bounces and one auto-generated recall report.
--   * THE SECOND PATH. email_triage's decline fires z53 (every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.sql).
--     fn_supplier_mailbox_mail_gets_its_owner hands every sender that is not a bounce, the founder's inbox or an auto-reply
--     to sales_engineer as a mailbox.supplier_reply handoff, and its handler fn_sales_engineer_acts_on_supplier_reply
--     (a_supplier_reply_gets_the_action_it_asked_for.sql) looked only at replied_at: unanswered meant fn_inbox_send with
--     fn_supplier_reply_answer, a template chosen by a regex over the words (fn_supplier_reply_intent; 2069's "we will continue
--     working on it" read as 'later'). It never read ai_category, the decline it was handed, and fn_inbox_send refused nothing
--     but an empty body. 1874's sender is one fn_is_machine_sender already recognises; nothing on that path asked it.
--   * Each template answer also filed a follow-up: supplier_reply_followup 14, 15, 16 (Microsoft) and 12, 13
--     (info@666realestate.ae), due 15-24 Nov, so Microsoft was due two more registration mails.
--   * The decline said "internal" for all five: noAutoReply returns 'internal' for supplier@ before it tests a no-reply
--     sender, so the stored reason hid the real one.
--
-- WHAT THIS CHANGES
--   1. public.mailbox_reply_decision: one row per mail into the supplier mailbox saying what the mail IS (nine readings) and,
--      GENERATED from that, whether a seat may answer it: only a supplier about registering or its account, an existing
--      supplier's question, or a customer, and only with no code rule against it.
--   2. fn_mailbox_reply_hard_rule: what code refuses whatever the reading says: a bounce; the founder's or our own address;
--      a no-reply / mailer-daemon / postmaster / notification sender; Auto-Submitted, X-Autoreply, Precedence bulk/list/junk,
--      List-Id or List-Unsubscribe; a reply to mail the founder sent by hand (its In-Reply-To is no message we sent and it
--      quotes our mailbox); a thread whose last answer was written by a person; a second automatic answer to one sender in
--      one thread on one Dubai day.
--   3. fn_mailbox_reply_decide: the only writer of a decision. It computes the hard rule itself, so a caller cannot skip it.
--   4. fn_inbox_send (the one door every reply goes through): a SEAT's reply to supplier-mailbox mail needs a decision that
--      says answer, re-checked when it is queued, and carries dedupe_key mailbox_auto_reply:<sender>:<thread>:<Dubai day>, so
--      the unique index makes it one per sender per thread per day. A PERSON's reply (p_by null or 'founder') is his decision
--      and is marked mailbox_person_reply. Every other mailbox is unchanged.
--   5. fn_mailbox_reply_may_leave: send_outbox asks it for every such row (and every follow-up) before the provider call.
--   6. fn_sales_engineer_acts_on_supplier_reply writes NO reply any more. It waits for the reading, records what it found,
--      applies a supplier's own "stop", and files a follow-up only for an answer the reading allowed.
--   7. fn_sales_engineer_follows_up_supplier_replies sends a follow-up only for such an answer (fn_mailbox_followup_allowed),
--      and the due follow-ups to the template's answers (12-16 on 11 Nov) are dropped by that same rule below.
-- NOT CHANGED: what the reading decides (supabase/functions/email_triage/supplier_mailbox_reading.ts: the model at HIGH
-- effort with the correspondence, ruling 1630/1631); the three replies already sent to Microsoft (nothing can be unsent);
-- fn_supplier_reply_answer and fn_supplier_reply_intent stay defined (nothing calls the answer now; the intent still names a
-- follow-up and a "stop"; a_supplier_reply_names_confirming_services_and_is_signed.test.mjs reads the answer's text).
-- The new routines are created and revoked here (CREATE grants EXECUTE to PUBLIC). The three replaced ones keep their ACL.
-- Prevented by: scripts/e2e/supplier_mailbox_reply_gate_sql.mjs (a throwaway Postgres: the previous bodies answer the Azure
-- mail and these do not), supabase/functions/email_triage/supplier_mailbox_reading.test.ts and
-- supabase/functions/send_outbox/mailbox_reply_gate.test.ts.

create table if not exists public.mailbox_reply_decision (
  inbound_message_id bigint primary key references public.inbound_messages (id),
  reading text not null check (reading in ('supplier_registration', 'supplier_account_question', 'customer', 'vendor_our_account',
    'automated_notice', 'bounce', 'founder_correspondence', 'spam_or_irrelevant', 'unclear')),
  hard_rule text check (hard_rule is null or hard_rule in ('bounce', 'founder_inbox', 'own_domain', 'machine_sender', 'auto_submitted',
    'list_mail', 'replies_to_mail_sent_by_hand', 'person_in_thread', 'daily_cap')),
  may_reply boolean generated always as (hard_rule is null and reading in ('supplier_registration', 'supplier_account_question', 'customer')) stored,
  why text,
  quote text,
  method text not null check (method in ('model', 'code', 'no_model')),
  model text,
  effort text,
  decided_by text not null default 'customer_support',
  decided_at timestamptz not null default now(),
  reply_notification_id bigint
);
create index if not exists mailbox_reply_decision_reply_notification_idx on public.mailbox_reply_decision (reply_notification_id)
  where reply_notification_id is not null;
alter table public.mailbox_reply_decision enable row level security;
drop policy if exists mailbox_reply_decision_service_role_only on public.mailbox_reply_decision;
create policy mailbox_reply_decision_service_role_only on public.mailbox_reply_decision
  as permissive for all to public using (false) with check (false);
revoke all on public.mailbox_reply_decision from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('mailbox_reply_decision', true, 'support', 'What each mail to the supplier mailbox was read as, why, and whether a seat was allowed to answer it.', 'customer_support')
on conflict (table_name) do nothing;

-- The thread a mail belongs to: the first Message-ID in References (the thread's root), else In-Reply-To, else its own.
create or replace function public.fn_mail_thread_key(p_raw jsonb)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select lower(coalesce(nullif(substring(coalesce(p_raw->>'references', '') from '<[^<>]+>'), ''),
                        nullif(btrim(coalesce(p_raw->>'in_reply_to', '')), ''),
                        nullif(btrim(coalesce(p_raw->>'message_id', '')), ''), ''))
$fn$;
revoke execute on function public.fn_mail_thread_key(jsonb) from public, anon, authenticated;

-- Mail into the supplier mailbox: the Microsoft 365 box and the Resend reply address (the two z53 reads), matched by address.
create or replace function public.fn_is_supplier_mailbox_mail(p_to text)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (
    select 1
      from public.app_secrets s,
           regexp_split_to_table(lower(coalesce(p_to, '')), '[,;]') a
     where s.key in ('invite_m365_mailbox', 'email_reply_supplier') and btrim(coalesce(s.value, '')) <> ''
       and coalesce(substring(a from '<([^<>[:space:]]+@[^<>[:space:]]+)>'), btrim(a)) = lower(btrim(s.value)))
$fn$;
revoke execute on function public.fn_is_supplier_mailbox_mail(text) from public, anon, authenticated;

-- Is the message a mail replies to one our system sent (or the sender's own earlier mail)? Every send of ours carries a
-- qd-notif-<id> Message-ID (the Microsoft 365 lane) or Resend's amazonses.com one (inbound 1615 answers notification 117599).
create or replace function public.fn_mail_reply_target_is_ours(p_message_id text, p_sender text)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p_message_id), '') = ''
      or lower(p_message_id) ~ 'qd-notif-[0-9]+\.'
      or lower(p_message_id) ~ '@(mail\.)?quotesdone\.(com|ae)>?\s*$'
      or lower(p_message_id) ~ '@([a-z0-9-]+\.)*amazonses\.com>?\s*$'
      or exists (select 1 from public.inbound_messages i
                  where coalesce(p_sender, '') <> '' and position(lower(p_sender) in lower(coalesce(i.from_email, ''))) > 0
                    and lower(btrim(coalesce(i.raw->>'message_id', ''))) = lower(btrim(p_message_id)))
$fn$;
revoke execute on function public.fn_mail_reply_target_is_ours(text, text) from public, anon, authenticated;

-- The dedupe key of a seat's automatic answer: one per sender, per thread, per Dubai day (notifications_dedupe_key_uidx).
create or replace function public.fn_mailbox_auto_reply_key(p_inbound_id bigint)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'mailbox_auto_reply:' || lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'))
         || ':' || md5(public.fn_mail_thread_key(m.raw)) || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD')
    from public.inbound_messages m where m.id = p_inbound_id
$fn$;
revoke execute on function public.fn_mailbox_auto_reply_key(bigint) from public, anon, authenticated;

create or replace function public.fn_mailbox_reply_hard_rule(p_inbound_id bigint)
returns text
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; v_addr text; v_local text; v_irt text; v_key text; v_last record; v_lastkey text;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then raise exception 'fn_mailbox_reply_hard_rule: no inbound message %', p_inbound_id; end if;
  v_addr := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  if v_addr is null then return 'machine_sender'; end if;
  v_local := split_part(v_addr, '@', 1);
  if public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw) then return 'bounce'; end if;
  if public.fn_is_founder_own_inbox(v_addr) or public.fn_mail_sender_known(v_addr) = 'staff' then return 'founder_inbox'; end if;
  if split_part(v_addr, '@', 2) ~ '(^|\.)quotesdone\.(com|ae)$' then return 'own_domain'; end if;
  if public.fn_is_machine_sender(m.from_email)
     or v_local ~ '(^|[-_.+])(no-?reply|do-?not-?reply|donotreply|notifications?|notify|alerts?|mailer|newsletters?)([-_.+0-9]|$)' then
    return 'machine_sender';
  end if;
  if lower(btrim(coalesce(m.raw->>'auto_submitted', ''))) not in ('', 'no')
     or btrim(coalesce(m.raw->>'x_autoreply', '')) <> ''
     or lower(btrim(coalesce(m.raw->>'precedence', ''))) = 'auto_reply' then
    return 'auto_submitted';
  end if;
  -- resend_inbound stores List-Unsubscribe, else List-Id, as list_unsubscribe (steps/supplier_docs.ts); list_id if it ever does
  if btrim(coalesce(m.raw->>'list_unsubscribe', '')) <> '' or btrim(coalesce(m.raw->>'list_id', '')) <> ''
     or lower(btrim(coalesce(m.raw->>'precedence', ''))) in ('bulk', 'list', 'junk') then
    return 'list_mail';
  end if;
  -- the founder writes from this mailbox in Outlook by hand: a reply to that mail names a Message-ID we never sent and
  -- quotes our mailbox as its From (inbound 1483: In-Reply-To <...PROD.OUTLOOK.COM>, "From: ... <supplier@quotesdone.com>")
  v_irt := nullif(btrim(coalesce(m.raw->>'in_reply_to', '')), '');
  if v_irt is not null and not public.fn_mail_reply_target_is_ours(v_irt, v_addr)
     and coalesce(m.body, '') ~* 'from:[^\n]{0,200}<?(supplier@quotesdone\.com|suppliers@mail\.quotesdone\.com)' then
    return 'replies_to_mail_sent_by_hand';
  end if;
  -- the last answer in this thread was a person's: the Inbox send of a person, or a reply whose author is no seat
  v_key := public.fn_mail_thread_key(m.raw);
  select i.replied_by into v_last from public.inbound_messages i
   where i.id <> m.id and i.replied_at is not null and i.created_at <= m.created_at
     and position(v_addr in lower(coalesce(i.from_email, ''))) > 0
     and v_key <> '' and public.fn_mail_thread_key(i.raw) = v_key
   order by i.replied_at desc limit 1;
  if found and (v_last.replied_by is null or v_last.replied_by = 'founder'
                or not exists (select 1 from public.org_role r where r.role_id = v_last.replied_by)) then
    return 'person_in_thread';
  end if;
  select n.dedupe_key into v_lastkey from public.notifications n
   where n.type = 'inbound_reply' and n.channel = 'email' and lower(btrim(n.to_email)) = v_addr and n.created_at <= now()
   order by n.id desc limit 1;
  if v_lastkey like 'mailbox_person_reply:%' then return 'person_in_thread'; end if;
  if exists (select 1 from public.notifications n where n.dedupe_key = public.fn_mailbox_auto_reply_key(m.id)) then return 'daily_cap'; end if;
  return null;
end $fn$;
revoke execute on function public.fn_mailbox_reply_hard_rule(bigint) from public, anon, authenticated;

-- A rule that already says what the mail is; daily_cap does not (the model still reads it, and it is not answered).
create or replace function public.fn_mailbox_reading_of_rule(p_rule text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case p_rule
    when 'bounce' then 'bounce'
    when 'founder_inbox' then 'founder_correspondence'
    when 'own_domain' then 'founder_correspondence'
    when 'replies_to_mail_sent_by_hand' then 'founder_correspondence'
    when 'person_in_thread' then 'founder_correspondence'
    when 'machine_sender' then 'automated_notice'
    when 'auto_submitted' then 'automated_notice'
    when 'list_mail' then 'automated_notice'
    else null end
$fn$;
revoke execute on function public.fn_mailbox_reading_of_rule(text) from public, anon, authenticated;

-- What email_triage asks before it reads a mail: is it the supplier mailbox's, and does code already decide it?
create or replace function public.fn_mailbox_reply_rules(p_inbound_id bigint)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; v_rule text;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return jsonb_build_object('supplier_mailbox', false, 'error', 'no such inbound message'); end if;
  if not public.fn_is_supplier_mailbox_mail(m.to_email) then return jsonb_build_object('supplier_mailbox', false); end if;
  v_rule := public.fn_mailbox_reply_hard_rule(m.id);
  return jsonb_build_object('supplier_mailbox', true, 'hard_rule', v_rule, 'reading', public.fn_mailbox_reading_of_rule(v_rule));
end $fn$;
revoke execute on function public.fn_mailbox_reply_rules(bigint) from public, anon, authenticated;

create or replace function public.fn_mailbox_reply_decide(p_inbound_id bigint, p_reading text, p_why text, p_quote text,
  p_method text, p_model text default null, p_effort text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_rule text; v_reading text; v_may boolean;
begin
  if not exists (select 1 from public.inbound_messages where id = p_inbound_id) then
    raise exception 'fn_mailbox_reply_decide: no inbound message %', p_inbound_id;
  end if;
  v_rule := public.fn_mailbox_reply_hard_rule(p_inbound_id);
  -- the code's reading wins where it has one; an answer outside the nine is 'unclear', held and never answered
  v_reading := coalesce(public.fn_mailbox_reading_of_rule(v_rule), p_reading);
  if v_reading is null or v_reading not in ('supplier_registration', 'supplier_account_question', 'customer', 'vendor_our_account',
       'automated_notice', 'bounce', 'founder_correspondence', 'spam_or_irrelevant', 'unclear') then v_reading := 'unclear'; end if;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, hard_rule, why, quote, method, model, effort, decided_by, decided_at)
  values (p_inbound_id, v_reading, v_rule, left(p_why, 1000), left(p_quote, 500),
          case when p_method in ('model', 'code', 'no_model') then p_method else 'code' end, p_model, p_effort, 'customer_support', now())
  on conflict (inbound_message_id) do update
     set reading = excluded.reading, hard_rule = excluded.hard_rule, why = excluded.why, quote = excluded.quote,
         method = excluded.method, model = excluded.model, effort = excluded.effort, decided_at = excluded.decided_at
  returning may_reply into v_may;
  return jsonb_build_object('reading', v_reading, 'hard_rule', v_rule, 'may_reply', v_may);
end $fn$;
revoke execute on function public.fn_mailbox_reply_decide(bigint, text, text, text, text, text, text) from public, anon, authenticated;

-- A follow-up promises a second mail: only after an answer the reading allowed. A row from before the readings existed
-- counts only when customer_support's model wrote its answer (replied_by), never the template (sales_engineer).
create or replace function public.fn_mailbox_followup_allowed(p_inbound_id bigint)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
    (select d.may_reply from public.mailbox_reply_decision d where d.inbound_message_id = p_inbound_id),
    exists (select 1 from public.inbound_messages i where i.id = p_inbound_id and i.replied_by = 'customer_support')
      and public.fn_mailbox_reply_hard_rule(p_inbound_id) is null)
$fn$;
revoke execute on function public.fn_mailbox_followup_allowed(bigint) from public, anon, authenticated;

-- THE ONE DOOR, re-checked at the moment a reply is queued. Base: the live body of 11 Nov 2026
-- (a_supplier_reply_goes_back_from_its_own_mailbox.sql), unchanged outside the supplier mailbox.
create or replace function public.fn_inbox_send(p_id bigint, p_body text, p_by text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  m public.inbound_messages%rowtype;
  v_mailbox text; v_to text; v_known text; v_role text; v_lead bigint; v_kind text; v_name text;
  v_box boolean; v_person boolean := (p_by is null or p_by = 'founder');
  d public.mailbox_reply_decision; v_rule text; v_dedupe text; v_nid bigint;
begin
  select * into m from public.inbound_messages where id=p_id;
  if m.id is null then return jsonb_build_object('error','message not found'); end if;
  if m.from_email is null then return jsonb_build_object('error','no sender address'); end if;
  if coalesce(trim(p_body),'')='' then return jsonb_build_object('error','empty reply'); end if;

  -- A SEAT ANSWERS SUPPLIER-MAILBOX MAIL ONLY WHEN ITS READING SAID ANSWER (ruling 1633). A person's reply is his own.
  v_box := public.fn_is_supplier_mailbox_mail(m.to_email);
  if v_box then
    if v_person then
      v_dedupe := 'mailbox_person_reply:' || m.id || ':' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
    else
      select * into d from public.mailbox_reply_decision where inbound_message_id = m.id;
      if not found then
        return jsonb_build_object('error', 'refused: ' || p_by || ' may not answer mail to the supplier mailbox that was never read (no mailbox_reply_decision)');
      end if;
      v_rule := public.fn_mailbox_reply_hard_rule(m.id);
      if not d.may_reply or v_rule is not null then
        return jsonb_build_object('error', 'refused: this mail was read as ' || d.reading
          || coalesce(' (' || coalesce(v_rule, d.hard_rule) || ')', '') || ', which is not answered automatically');
      end if;
      v_dedupe := public.fn_mailbox_auto_reply_key(m.id);
    end if;
  end if;

  -- Which mailbox the message came into, and who wrote it.
  select lower(btrim(value)) into v_mailbox from public.app_secrets where key = 'invite_m365_mailbox';
  v_mailbox := coalesce(nullif(v_mailbox, ''), 'supplier@quotesdone.com');
  v_to := lower(btrim(coalesce(substring(m.to_email from '<([^>]+)>'), m.to_email, '')));
  v_known := public.fn_mail_sender_known(m.from_email);
  if coalesce(v_known, '') not in ('staff', 'customer') then
    if m.lead_id is not null or v_known = 'supplier' then
      v_role := 'supplier';
      v_lead := coalesce(m.lead_id, (select l.id from public.leads l
                                       where lower(btrim(l.email)) = lower(btrim(m.from_email))
                                          or lower(btrim(l.claimed_by)) = lower(btrim(m.from_email))
                                       order by l.id limit 1));
    end if;
    if v_to = v_mailbox then v_kind := 'supplier_mailbox_reply'; end if;
  end if;
  -- a supplier is answered in English: an Arabic letter in the body (the lead's own name set aside) is never sent
  if v_role = 'supplier' then
    select nullif(btrim(l.company_name), '') into v_name from public.leads l where l.id = v_lead;
    if replace(p_body, coalesce(v_name, ''), '') ~ '[؀-ۿ]' then
      return jsonb_build_object('error', 'a supplier is always answered in English: this reply carries Arabic, so it was not sent');
    end if;
  end if;

  begin
    insert into public.notifications(type,to_email,to_role,lead_id,kind,channel,subject,body,in_reply_to,dedupe_key)
      values('inbound_reply', m.from_email, v_role, v_lead, v_kind, 'email',
             case when coalesce(m.subject,'') ilike 're:%' then m.subject else 'Re: '||coalesce(nullif(m.subject,''),'your message') end,
             p_body, nullif(btrim(m.raw->>'message_id'), ''), v_dedupe)
      returning id into v_nid;
  exception when unique_violation then
    return jsonb_build_object('error', 'refused: one automatic reply per sender per thread per day, and this thread had its reply today');
  end;
  if v_box and not v_person then
    update public.mailbox_reply_decision set reply_notification_id = v_nid where inbound_message_id = m.id;
  end if;

  update public.inbound_messages set replied_at=now(), replied_by=coalesce(p_by,'founder'), needs_review=false where id=p_id;
  update public.agent_actions set status='approved', decided_by=coalesce(p_by,'founder'), decided_at=now()
   where target_table='inbound_messages' and target_id=p_id::text
     and status in ('pending','held_for_review','proposed','open');
  return jsonb_build_object('ok',true, 'to', m.from_email, 'to_role', v_role, 'lead_id', v_lead, 'notification_id', v_nid);
end $fn$;

-- THE SAME RULE AT SEND TIME (send_outbox asks before the provider call). Not this gate's row: allowed.
create or replace function public.fn_mailbox_reply_may_leave(p_notification_id bigint)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n public.notifications; d public.mailbox_reply_decision; f public.supplier_reply_followup;
begin
  select * into n from public.notifications where id = p_notification_id;
  if not found then return jsonb_build_object('allow', false, 'reason', 'no such notification'); end if;
  if coalesce(n.dedupe_key, '') like 'mailbox_person_reply:%' then
    return jsonb_build_object('allow', true, 'reason', 'a person wrote this reply');
  end if;
  if coalesce(n.dedupe_key, '') like 'supplier_reply_followup:%' then
    select * into f from public.supplier_reply_followup
     where id = nullif(substring(n.dedupe_key from '^supplier_reply_followup:([0-9]+)$'), '')::bigint;
    if not found or not public.fn_mailbox_followup_allowed(f.inbound_message_id) then
      return jsonb_build_object('allow', false, 'reason', 'a follow-up to mail whose reading did not allow an answer');
    end if;
    if public.fn_is_machine_sender(n.to_email) then
      return jsonb_build_object('allow', false, 'reason', 'the recipient is a no-reply or machine address');
    end if;
    return jsonb_build_object('allow', true, 'reason', 'a follow-up to an answer the reading allowed');
  end if;
  if n.type = 'inbound_reply' and (n.kind = 'supplier_mailbox_reply' or coalesce(n.dedupe_key, '') like 'mailbox_auto_reply:%') then
    select * into d from public.mailbox_reply_decision where reply_notification_id = n.id;
    if not found then
      return jsonb_build_object('allow', false, 'reason', 'no reading of the mail it answers allowed this reply');
    end if;
    if not d.may_reply then
      return jsonb_build_object('allow', false, 'reason', 'the mail it answers was read as ' || d.reading || coalesce(' (' || d.hard_rule || ')', ''));
    end if;
    if public.fn_is_machine_sender(n.to_email) then
      return jsonb_build_object('allow', false, 'reason', 'the recipient is a no-reply or machine address');
    end if;
    return jsonb_build_object('allow', true, 'reason', 'the reading said answer (' || d.reading || ')');
  end if;
  return jsonb_build_object('allow', true, 'reason', 'not a supplier-mailbox reply');
end $fn$;
revoke execute on function public.fn_mailbox_reply_may_leave(bigint) from public, anon, authenticated;

-- THE HANDOFF NO LONGER ANSWERS. Base: the live body of 11 Nov 2026 (a_supplier_reply_gets_the_action_it_asked_for.sql).
create or replace function public.fn_sales_engineer_acts_on_supplier_reply(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; m public.inbound_messages; l public.leads; d public.mailbox_reply_decision; v_read boolean;
  v_text text; v_intent text; v_from text; v_followup timestamptz; v_note text; c record;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  select * into m from public.inbound_messages where id = (a.detail->>'inbound_message_id')::bigint;
  if m.id is null then return jsonb_build_object('action', 'none', 'reason', 'the inbound message no longer exists'); end if;
  select * into d from public.mailbox_reply_decision where inbound_message_id = m.id;
  v_read := found;
  -- customer_support reads the mail first (email_triage, supplier_mailbox_reading.ts); a reading that never comes is
  -- handled below, never by a template
  if not v_read and m.replied_at is null and now() < m.created_at + interval '1 hour' then
    return jsonb_build_object('waiting', 'customer_support reads this mail first and answers it only if its reading says so; this handler never writes a reply');
  end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  select * into l from public.leads x where x.id = coalesce((a.detail->>'lead_id')::bigint, m.lead_id);
  v_text := coalesce(a.detail->>'reply_text', m.body, '');
  v_intent := public.fn_supplier_reply_intent(v_text);

  if v_from is null or public.fn_is_demo_email(v_from) or public.fn_is_founder_own_inbox(v_from) then
    return jsonb_build_object('action', 'none', 'reason', 'a fixture or the founder''s own address: nothing is sent', 'intent', v_intent);
  end if;

  if v_read and not d.may_reply and m.replied_at is null then
    -- vendor, notification, the founder's own thread, spam, unclear, or a code rule: nothing is sent, nothing is promised
    v_note := 'not answered: the mail was read as ' || d.reading || coalesce(' (' || d.hard_rule || ')', '');
  elsif not v_read and m.replied_at is null then
    update public.inbound_messages set needs_review = true where id = m.id and not needs_review;
    v_note := 'not answered: no reading of this mail was recorded within the hour, so it waits for review';
  elsif v_intent = 'decline' then
    insert into public.email_suppressions (email, reason, source) values (v_from, 'declined_in_reply', 'supplier_reply') on conflict (email) do nothing;
    update public.inbound_messages set needs_review = false where id = m.id;
    v_note := 'declined: the address is suppressed';
  elsif m.replied_at is null then
    -- the reading allowed an answer and customer_support writes it, answering what they wrote; nothing is written here
    if now() < m.created_at + interval '24 hours' then
      return jsonb_build_object('waiting', 'the reading allowed an answer: customer_support writes it in the thread');
    end if;
    update public.inbound_messages set needs_review = true where id = m.id and not needs_review;
    v_note := 'the reading allowed an answer and none was sent within a day: it waits for review';
  else
    update public.inbound_messages set needs_review = false where id = m.id and needs_review;
    v_note := 'answered by ' || coalesce(m.replied_by, 'triage') || ' at ' || m.replied_at;
    -- a claimed page is chased by fn_supplier_registration_reminders_due; a subsidiary has a second company, so it is followed anyway
    if not public.fn_mailbox_followup_allowed(m.id) then
      v_note := v_note || '; no follow-up: the reading did not allow an answer';
    elsif not coalesce(l.claimed, false) or v_intent = 'subsidiary' then
      v_followup := now() + case v_intent when 'later' then interval '14 days' else interval '7 days' end;
      insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at)
      values (m.id, l.id, v_from, case when v_intent in ('subsidiary', 'later') then v_intent else 'interested' end, v_followup)
      on conflict (inbound_message_id) do nothing;
    else
      v_note := v_note || '; the registration reminder chases the started page';
    end if;
  end if;

  -- only the support case THIS mail opened ends with the action: its subject is 'Email: <subject> <body>', read by position
  -- so a % in a subject matches nothing. Another open case from the same sender stays open. No rating on a first reply.
  for c in select s.case_ref from public.support_case s
            where s.channel = 'email' and s.party_id = v_from and s.state <> 'closed'
              and position('Email: ' || coalesce(m.subject, '') in coalesce(s.subject, '')) = 1
              and position(left(btrim(coalesce(m.body, '')), 30) in coalesce(s.subject, '')) > 0
            order by s.case_id desc limit 1 loop
    update public.support_case set csat_requested_at = now() where case_ref = c.case_ref and csat_requested_at is null;
    perform public.fn_support_case_close(c.case_ref, v_note, 'sales_engineer');
  end loop;
  return jsonb_build_object('action', v_note, 'intent', v_intent, 'inbound_message_id', m.id, 'lead_id', l.id, 'followup_due', v_followup,
                            'reading', d.reading, 'may_reply', d.may_reply);
end $fn$;

-- Base: the live body of 11 Nov 2026 (a_supplier_reply_gets_the_action_it_asked_for.sql); one rule added in step 3.
create or replace function public.fn_sales_engineer_follows_up_supplier_replies()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h record; f public.supplier_reply_followup; l public.leads; v_acted int := 0; v_sent int := 0; v_dropped int := 0; v_site text; v_body text; v_err jsonb := '[]'::jsonb;
begin
  -- 1. replies whose triage has spoken (or the hour passed)
  for h in select a.id from public.agent_actions a
             join public.inbound_messages m on m.id = (a.detail->>'inbound_message_id')::bigint
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' in ('invite.reply', 'mailbox.supplier_reply')
              and (m.triaged_at is not null or m.replied_at is not null or now() >= m.created_at + interval '1 hour')
            order by a.id limit 50 loop
    begin
      perform public.fn_seat_handoff_act(h.id);
      v_acted := v_acted + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 2. a bounce the customer_support seat already acted on leaves review
  update public.inbound_messages i set needs_review = false
    from public.agent_actions b
   where b.kind = 'mail_bounce' and b.status = 'auto_done' and b.target_table = 'inbound_messages'
     and b.target_id = i.id::text and i.needs_review;

  -- 3. the one follow-up, on a Dubai weekday inside the sending window
  if extract(isodow from now() at time zone 'Asia/Dubai') not in (6, 7)
     and extract(hour from now() at time zone 'Asia/Dubai') between 9 and 16 then
    select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
    for f in select * from public.supplier_reply_followup where state = 'due' and due_at <= now() order by id limit 20 for update skip locked loop
      -- a follow-up only after an answer the reading allowed (ruling 1633): never to a vendor, a notification or a template answer
      if not public.fn_mailbox_followup_allowed(f.inbound_message_id) or public.fn_is_machine_sender(f.to_email) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the mail it follows was not one the reading allowed an answer to', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      l := null;
      if f.lead_id is not null then select * into l from public.leads where id = f.lead_id; end if;
      if f.intent <> 'subsidiary' and (coalesce(l.claimed, false) or l.registration_submitted_at is not null) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the company started registering', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      if public.fn_is_demo_email(f.to_email) or exists (select 1 from public.email_suppressions s where lower(s.email) = lower(f.to_email)) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'suppressed or a fixture', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      if exists (select 1 from public.inbound_messages n where lower(n.from_email) like '%' || lower(f.to_email) || '%' and n.id > f.inbound_message_id and n.owner_role is distinct from 'it_engineer') then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the supplier wrote again: that mail is answered on its own', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      v_body := case f.intent
        when 'subsidiary' then E'Hello,\n\nA week ago you asked about registering a separate company. It registers with its own trade licence and a different e-mail address: ' || coalesce(v_site, 'https://quotesdone.com') || E'/en/portal\n\nIf we can help, reply to this e-mail. This is the only reminder we will send about it.'
        when 'later' then E'Hello,\n\nYou told us a little while ago that later would suit you better. Registration is still free for our first 1,000 suppliers, and takes a few minutes: ' || coalesce(v_site, 'https://quotesdone.com') || E'/en/portal\n\nThis is the only reminder we will send about it.'
        else E'Hello,\n\nYou replied to us last week and your company has not registered yet. It takes a few minutes: ' || coalesce(v_site, 'https://quotesdone.com') || E'/en/portal\n\nIf something is stopping you, reply to this e-mail. This is the only reminder we will send about it.' end;
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', f.to_email, 'to_role', 'supplier',
        'lead_id', f.lead_id, 'lang', 'en', 'subject', 'Your QuotesDone supplier registration', 'body', v_body,
        'dedupe_key', 'supplier_reply_followup:' || f.id)));
      update public.supplier_reply_followup set state = 'sent', outcome = 'follow-up queued', done_at = now() where id = f.id;
      v_sent := v_sent + 1;
    end loop;
  end if;
  return jsonb_build_object('acted', v_acted, 'followups_sent', v_sent, 'followups_dropped', v_dropped, 'errors', v_err);
end $fn$;

-- The follow-ups the template promised are dropped by the same rule the duty now applies (measured 11 Nov: 12, 13, 14, 15, 16).
update public.supplier_reply_followup
   set state = 'dropped', outcome = 'the mail it follows was not one the reading allowed an answer to', done_at = now()
 where state = 'due' and not public.fn_mailbox_followup_allowed(inbound_message_id);

-- verdict (reads only)
select case
  when to_regclass('public.mailbox_reply_decision') is null then 'PROBE FAILED: mailbox_reply_decision is missing'
  when exists (select 1 from public.inbound_messages where id = 1874)
       and public.fn_mailbox_reply_hard_rule(1874) is distinct from 'machine_sender'
    then 'PROBE FAILED: azure-noreply@microsoft.com is not refused by code: ' || coalesce(public.fn_mailbox_reply_hard_rule(1874), 'null')
  when exists (select 1 from public.notifications where id = 129468)
       and coalesce((public.fn_mailbox_reply_may_leave(129468)->>'allow')::boolean, true)
    then 'PROBE FAILED: the Azure reply (notification 129468) would be allowed to leave'
  when exists (select 1 from public.supplier_reply_followup f where f.state = 'due' and not public.fn_mailbox_followup_allowed(f.inbound_message_id))
    then 'PROBE FAILED: a follow-up to an answer the reading did not allow is still due'
  when exists (select 1 from public.supplier_reply_followup where id in (12, 13, 14, 15, 16) and state = 'due')
    then 'PROBE FAILED: a follow-up to a template answer is still due'
  else 'PROBE OK' end as verdict;
