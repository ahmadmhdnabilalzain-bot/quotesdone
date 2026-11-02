-- A SUPPLIER'S REPLY GETS THE ACTION IT ASKED FOR, THE HANDOFF CLOSES ON THAT ACTION, AND A STARTED REGISTRATION IS CHASED.
-- Seat: sales_engineer (customer_support delivers). 2 Nov 2026, founder ledger 1436, 1447; audit items 4, 5, 12.
--
-- MEASURED 1-2 Nov 2026 (production, read-only):
--   * invite.reply #326819 (Al Gouri) and mailbox.supplier_reply #329843 (666realestate) pending: both handlers only return
--     'waiting'. Inbound 1485 was answered by triage on 30 Oct; inbound 1483 ("Definitely but later") never was.
--   * invite.reply is filed BEFORE email_triage finishes (1485: filed 12:01:20Z, answered 12:04:19Z), so a handler that sends
--     at filing would double-answer. The handler waits for the triage verdict and the duty below acts on it.
--   * fn_supplier_registration_reminders_due works: it lists lead 19398 today. A pause no longer stops it (#1744).
--   * Reminder copy for a started registration listed all six items, though Al Gouri had already verified two.
--   * 653-655 are the founder's own seed inboxes answering a test ("All good"), sitting in needs_review beside real mail.
--
-- WHAT THE SEAT DOES WITH A REPLY (deterministic: fn_supplier_reply_intent reads the supplier's own words):
--   subsidiary  answers unless triage already did: a separate licensed company registers alone, its own licence, a different e-mail. Follow-up 7 days.
--   later       answers, follow-up in 14 days, once.
--   decline     outranks the rest: suppresses the address, says nothing more.
--   interested  answers with the six things and the link, or stands on triage's answer. Follow-up 7 days unless the company
--               page is claimed, where the registration reminder owns the chase.
-- It never offers to register them or set up a page: only they can verify and accept (account_facts.ts, NO_SETUP_FOR_THEM).
--
-- Prevented by: scripts/checks/nothing_a_person_sends_us_waits.test.mjs and scripts/sql/a_supplier_reply_gets_the_action_it_asked_for_probe.sql

create table if not exists public.supplier_reply_followup (
  id bigserial primary key,
  inbound_message_id bigint not null unique references public.inbound_messages (id),
  lead_id bigint,
  to_email text not null,
  intent text not null check (intent in ('subsidiary', 'later', 'interested')),
  due_at timestamptz not null,
  state text not null default 'due' check (state in ('due', 'sent', 'dropped')),
  outcome text,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
alter table public.supplier_reply_followup enable row level security;
drop policy if exists supplier_reply_followup_service_role_only on public.supplier_reply_followup;
create policy supplier_reply_followup_service_role_only on public.supplier_reply_followup
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_reply_followup from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('supplier_reply_followup', true, 'supplier', 'Each follow-up promised to a supplier who replied to an invitation, with its due date and outcome.', 'sales_engineer')
on conflict (table_name) do nothing;

create or replace function public.fn_supplier_reply_intent(p_text text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    -- a decline or a stop outranks everything else in the same mail
    when coalesce(p_text, '') ~* '(\mnot interested\M|\mno,? thank|\mdo not contact\M|\mdon''t contact\M|\mremove (me|us|our)\M|\munsubscribe\M)'
         or coalesce(p_text, '') ~* '(^|\n)\s*stop\s*[.!]?\s*(\n|$)' then 'decline'
    when coalesce(p_text, '') ~* '(subsid|sister (company|concern)|(another|other|second|separate|different) (licen[cs]ed )?(company|licen[cs]e|trade licen[cs]e)|more than one company|group compan|our group)' then 'subsidiary'
    when coalesce(p_text, '') ~* '(\mlater\M|\mnot now\M|\mnot yet\M|\mnext (week|month|year)\M|\mafter (eid|ramadan|the holidays?)\M|\mbusy\M|\mfew (days|weeks|months)\M|\msome other time\M)' then 'later'
    else 'interested' end
$fn$;
revoke execute on function public.fn_supplier_reply_intent(text) from public, anon, authenticated;

create or replace function public.fn_supplier_reply_answer(p_intent text, p_link text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case p_intent
    when 'subsidiary' then
      E'Thank you for your message.\n\nA separately licensed company registers on its own, with its own trade licence and a different e-mail address: one e-mail address manages one company.\n\nTo register it, open ' || p_link || E' , choose "Create account" and use that company''s work e-mail. It needs its licensed name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and acceptance of the supplier terms.\n\nAnything you have already started for your first company stays as it is. We will check in with you in a week.'
    when 'later' then
      E'Thank you, and there is no rush. Registration stays free for our first 1,000 suppliers.\n\nWhen the time suits you, open ' || p_link || E' and choose "Create account". We will write once more in two weeks. If you would rather we did not, reply "stop".'
    else
      E'Thank you for your reply.\n\nTo register, open ' || p_link || E' , choose "Create account" with your work e-mail and type the 6-digit code we send you. To be verified we need your licensed company name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and your acceptance of the supplier terms. Only you can verify and accept these, so we cannot do it for you, but it takes a few minutes.\n\nIf you have a question, reply to this e-mail.'
    end
$fn$;
revoke execute on function public.fn_supplier_reply_answer(text, text) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_acts_on_supplier_reply(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; m public.inbound_messages; l public.leads; v_text text; v_intent text; v_from text; v_site text;
  v_sent jsonb; v_followup timestamptz; v_note text; c record;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  select * into m from public.inbound_messages where id = (a.detail->>'inbound_message_id')::bigint;
  if m.id is null then return jsonb_build_object('action', 'none', 'reason', 'the inbound message no longer exists'); end if;
  -- triage answers first; a verdict that never comes must not strand the person
  if m.triaged_at is null and m.replied_at is null and now() < m.created_at + interval '1 hour' then
    return jsonb_build_object('waiting', 'email_triage reads this message first; fn_sales_engineer_follows_up_supplier_replies acts next');
  end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  select * into l from public.leads x where x.id = coalesce((a.detail->>'lead_id')::bigint, m.lead_id);
  v_text := coalesce(a.detail->>'reply_text', m.body, '');
  v_intent := public.fn_supplier_reply_intent(v_text);

  if v_from is null or public.fn_is_demo_email(v_from) or public.fn_is_founder_own_inbox(v_from) then
    return jsonb_build_object('action', 'none', 'reason', 'a fixture or the founder''s own address: nothing is sent', 'intent', v_intent);
  end if;

  if v_intent = 'decline' then
    insert into public.email_suppressions (email, reason, source) values (v_from, 'declined_in_reply', 'supplier_reply') on conflict (email) do nothing;
    update public.inbound_messages set needs_review = false where id = m.id;
    v_note := 'declined: the address is suppressed';
  else
    select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
    -- Only when triage has not: its facts carry the same separate-company rule (account_facts.ts), and a person gets one answer.
    if m.replied_at is null then
      v_sent := public.fn_inbox_send(m.id, public.fn_supplier_reply_answer(v_intent, coalesce(v_site, 'https://quotesdone.com') || '/en/portal'), 'sales_engineer');
      if v_sent ? 'error' then return jsonb_build_object('waiting', 'the answer was refused: ' || (v_sent->>'error')); end if;
      v_note := 'answered: ' || v_intent;
    else
      update public.inbound_messages set needs_review = false where id = m.id and needs_review;
      v_note := 'already answered by ' || coalesce(m.replied_by, 'triage') || ' at ' || m.replied_at;
    end if;
    -- a claimed page is chased by fn_supplier_registration_reminders_due; a subsidiary has a second company, so it is followed anyway
    if not coalesce(l.claimed, false) or v_intent = 'subsidiary' then
      v_followup := now() + case v_intent when 'later' then interval '14 days' else interval '7 days' end;
      insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at)
      values (m.id, l.id, v_from, v_intent, v_followup) on conflict (inbound_message_id) do nothing;
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
  return jsonb_build_object('action', v_note, 'intent', v_intent, 'inbound_message_id', m.id, 'lead_id', l.id, 'followup_due', v_followup);
end $fn$;
revoke execute on function public.fn_sales_engineer_acts_on_supplier_reply(bigint) from public, anon, authenticated;

-- The two registered handlers lose STABLE and act.
create or replace function public.fn_sales_engineer_takes_invite_reply(p_id bigint)
returns jsonb language sql volatile security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_sales_engineer_acts_on_supplier_reply(p_id) $fn$;
create or replace function public.fn_sales_engineer_takes_supplier_mailbox_reply(p_id bigint)
returns jsonb language sql volatile security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_sales_engineer_acts_on_supplier_reply(p_id) $fn$;
revoke execute on function public.fn_sales_engineer_takes_invite_reply(bigint) from public, anon, authenticated;
revoke execute on function public.fn_sales_engineer_takes_supplier_mailbox_reply(bigint) from public, anon, authenticated;

update public.seat_handoff_kind
   set meaning = 'an invited supplier replied: the sales engineer answers what it asked (registration, a separate company, later), files the follow-up, and the handoff closes on that',
       owner_file = 'scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql'
 where type = 'invite.reply';
update public.seat_handoff_kind
   set meaning = 'a person who is not an invited lead wrote to the supplier mailbox: the sales engineer answers in its thread, files the follow-up, and the handoff closes on that',
       owner_file = 'scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql'
 where type = 'mailbox.supplier_reply';

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
revoke execute on function public.fn_sales_engineer_follows_up_supplier_replies() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.supplier_reply_followups', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_follows_up_supplier_replies',
   'Acts on every supplier reply once triage has read it, sends the one follow-up it promised, and takes acted bounces out of review.',
   'scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- 666REALESTATE IS THE FOUNDER'S OWN ADDRESS (review of #1746: display name Ahmad Alzain, a warm-up reply to his hand-sent
-- test): it joins the list, it is mailed nothing, and its handoff, row and case close by exact key.
create or replace function public.fn_is_founder_own_inbox(p_addr text)
returns boolean
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_list text[]; v text;
begin
  if p_addr is null or btrim(p_addr) = '' then return false; end if;
  select array_agg(public.fn_mailbox_fold(a)) into v_list
    from (select unnest(array['management@quotesdone.com', 'ahmadmhdnabilalzain@gmail.com',
                              'management@doratajewelries.com', 'djzaino@outlook.com', 'bookings@djzaino.com',
                              'fati.labib@icloud.com', 'ahmad@666realestate.ae']) a
          union all
          select btrim(x) from public.app_secrets s, regexp_split_to_table(coalesce(s.value, ''), ',') x
           where s.key in ('founder_email', 'admin_emails') and btrim(x) like '%@%') l;
  v := public.fn_mailbox_fold(p_addr);
  return v = any(v_list);
end $fn$;
revoke execute on function public.fn_is_founder_own_inbox(text) from public, anon, authenticated;
select public.fn_seat_handoff_complete(329843, jsonb_build_object('action', 'none',
  'reason', 'ahmad@666realestate.ae is the founder''s own address, a warm-up reply: nobody is waiting and nothing is sent'))
 where exists (select 1 from public.agent_actions where id = 329843 and status <> 'done');
update public.support_case set csat_requested_at = coalesce(csat_requested_at, now()) where case_ref = 'QD-S-SDGR7P' and state <> 'closed';
select public.fn_support_case_close('QD-S-SDGR7P', 'the founder''s own address, a warm-up reply', 'sales_engineer');

-- TEST REPLIES LEAVE REVIEW (audit item 12): the founder's own inbox answering a seed, whichever path wrote the row last.
create or replace function public.trg_a05_test_reply_leaves_review()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_is_founder_own_inbox(lower(substring(coalesce(new.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'))) then
    new.needs_review := false;
    new.ai_category := 'test_reply';
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_a05_test_reply_leaves_review() from public, anon, authenticated;
drop trigger if exists a05_test_reply_leaves_review on public.inbound_messages;
create trigger a05_test_reply_leaves_review before update on public.inbound_messages
  for each row when (new.owner_role = 'it_engineer') execute function public.trg_a05_test_reply_leaves_review();
update public.inbound_messages set owner_role = 'it_engineer' where id = 1483 and owner_role = 'sales_engineer';
update public.inbound_messages set owner_role = owner_role where id in (653, 654, 655, 1483) and owner_role = 'it_engineer';

-- THE REMINDER COPY: names only what is missing (the body is otherwise the live one). Who is chased in a pause, the complaint
-- stop and the sending window are #1744's (fn_supplier_reminder_is_open), and are not touched here.
CREATE OR REPLACE FUNCTION public.fn_supplier_registration_reminder_compose(p leads, p_stage text, p_step integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
  v_lang text; v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_items_en text; v_items_ar text; v_due_en text; v_due_ar text; v_last boolean := p_step >= 2;
  v_greet text; v_subj text; v_body text;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورِّد'));
begin
  if p_stage not in ('clicked', 'started', 'incomplete') or p_step not in (1, 2) then
    raise exception 'fn_supplier_registration_reminder_compose: unknown stage % or step %', p_stage, p_step;
  end if;
  v_lang := case when v_ar then 'ar' else 'en' end;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  v_link := v_site || '/' || v_lang || '/portal'
            || case when p_stage = 'clicked' and p.claim_token is not null then '?t=' || p.claim_token::text else '' end;

  if p_stage in ('incomplete', 'started') then
    select string_agg(coalesce(v_label->k->>0, k), ', ' order by o), string_agg(coalesce(v_label->k->>1, k), '، ' order by o)
      into v_items_en, v_items_ar from unnest(public.fn_supplier_mandatory_six(p)) with ordinality u(k, o);
    if p.license_expiry is not null and p.license_expiry < current_date then
      v_items_en := concat_ws(', ', v_items_en, 'a trade licence that is in date');
      v_items_ar := concat_ws('، ', v_items_ar, 'رخصة تجارية سارية المفعول');
    end if;
    v_items_en := coalesce(v_items_en, 'the items shown in your portal');
    v_items_ar := coalesce(v_items_ar, 'البنود الموضّحة في بوابتكم');
    v_due_en := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD Mon YYYY');
    v_due_ar := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD/MM/YYYY');
  end if;

  if v_ar then
    v_greet := case when v_name is null then 'السادة الكرام،' else 'السادة/ ' || v_name || ' المحترمين،' end;
    v_subj := case when v_last then 'تذكير أخير: ' else '' end
      || case p_stage when 'clicked' then 'دعوتكم للانضمام إلى الموردين المؤسِّسين في QuotesDone'
                      else 'استكمال تسجيلكم كمورِّد في QuotesDone' end;
    v_body := v_greet || E'\n\nتحية طيبة وبعد،\n\n'
      || case p_stage
           when 'clicked' then
             'نشكر لكم اطّلاعكم على دعوتنا للانضمام بصفة «مورِّد مؤسِّس» إلى QuotesDone، ونودّ إفادتكم بأن تسجيل شركتكم لم يبدأ بعد. '
             || 'ولا يستغرق التسجيل سوى دقائق معدودة، وهو مجاني دون أي عمولة على الأعمال التي تُرسى عليكم.'
             || E'\n\nللتسجيل، يُرجى الدخول إلى بوابة الموردين عبر الرابط التالي:\n\n' || v_link
           when 'started' then
             'نشكر لكم بدء تسجيل شركتكم مورِّدًا على منصة QuotesDone، ونودّ إفادتكم بأن طلب التسجيل لم يُستكمل بعد. '
             || 'وما زال ينقصه: ' || v_items_ar || '.'
             || E'\n\nيمكنكم متابعة التسجيل من حيث توقفتم عبر الرابط التالي:\n\n' || v_link
           else
             'نفيدكم بأن طلب تسجيل شركتكم محفوظ لدينا، غير أنه ما زال ينقصه: ' || v_items_ar || '. '
             || 'ويُرجى استكماله في موعد أقصاه ' || v_due_ar || '، إذ يُغلق طلب التسجيل تلقائيًا بعد هذا التاريخ، ويمكنكم التسجيل من جديد في أي وقت.'
             || E'\n\nيمكنكم استكمال البنود المطلوبة عبر بوابة الموردين:\n\n' || v_link
         end
      || case when v_last then E'\n\nوهذا آخر تذكير نرسله إليكم بهذا الشأن.' else '' end
      || E'\n\nوفي حال عدم رغبتكم في تلقي هذه التذكيرات، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_greet := case when v_name is null then 'Dear Sir or Madam,' else 'Dear ' || v_name || ',' end;
    v_subj := case when v_last then 'A last reminder: ' else '' end
      || case p_stage when 'clicked' then 'your invitation to join QuotesDone as a founding supplier'
                      else 'complete your QuotesDone supplier registration' end;
    v_body := v_greet || E'\n\n'
      || case p_stage
           when 'clicked' then
             'Thank you for opening our invitation to join QuotesDone as a founding supplier. Your company has not registered yet. '
             || 'It takes a few minutes, it is free, and there is no commission on the work you win.'
             || E'\n\nTo register, open your supplier portal here:\n\n' || v_link
           when 'started' then
             'Thank you for starting to register your company as a supplier on QuotesDone. The registration is not finished yet. '
             || 'It still needs: ' || v_items_en || '.'
             || E'\n\nContinue where you left off:\n\n' || v_link
           else
             'Your registration is saved, but it still needs: ' || v_items_en || '. '
             || 'Please complete it by ' || v_due_en || '; after that date the registration closes automatically, and you are welcome to start again at any time.'
             || E'\n\nComplete the missing items in your supplier portal:\n\n' || v_link
         end
      || case when v_last then E'\n\nThis is the last reminder we will send about it.' else '' end
      || E'\n\nIf you would rather not receive these reminders, reply to this e-mail and we will remove your address.';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$;

select case
  when (select provolatile from pg_proc where oid = 'public.fn_sales_engineer_takes_invite_reply(bigint)'::regprocedure) <> 'v'
    then 'PROBE FAILED: the invite.reply handler is still STABLE'
  when public.fn_supplier_reply_intent('we have a subsidiary with its own licence') <> 'subsidiary' then 'PROBE FAILED: subsidiary not read'
  when public.fn_supplier_reply_intent('We would like to register our Subsidairy') <> 'subsidiary' then 'PROBE FAILED: the real spelling of inbound 1615 is not read'
  when public.fn_supplier_reply_intent('Definitely but later') <> 'later' then 'PROBE FAILED: later not read'
  when public.fn_supplier_reply_intent('We are not interested in registering our subsidiary') <> 'decline' then 'PROBE FAILED: a decline lost to subsidiary'
  when public.fn_supplier_reply_intent(E'stop\n\nour subsidiary') <> 'decline' then 'PROBE FAILED: a stop lost to subsidiary'
  when not public.fn_is_founder_own_inbox('ahmad@666realestate.ae') then 'PROBE FAILED: the founder''s address is not his'
  when exists (select 1 from public.notifications where type = 'inbound_reply' and lower(to_email) like '%666realestate%') then 'PROBE FAILED: the founder''s address was mailed'
  when (select status from public.agent_actions where id = 329843) <> 'done' then 'PROBE FAILED: handoff 329843 is open'
  when exists (select 1 from public.inbound_messages where id in (653, 654, 655) and needs_review) then 'PROBE FAILED: a test reply is still in review'
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.supplier_reply_followups') then 'PROBE FAILED: the duty is missing'
  else 'PROBE OK' end as verdict;
