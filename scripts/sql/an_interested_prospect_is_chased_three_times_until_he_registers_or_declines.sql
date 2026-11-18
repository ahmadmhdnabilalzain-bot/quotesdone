-- AN INTERESTED PROSPECT IS CHASED THREE TIMES UNTIL HE REGISTERS OR DECLINES, AND A FAILED HAND-OVER CANNOT LOSE HIM.
-- Seat: sales_engineer. 18 Nov 2026. Case: Shine Carpets Washing L.L.C. (leads 2936) and the campaign since 28 Oct 2026.
--
-- WHAT WAS MEASURED (production, read-only, 18 Nov 2026; live bodies read with pg_get_functiondef):
--   * After customer_support answers a prospect's reply, fn_sales_engineer_follows_up_supplier_replies (every 15 min) acts on the
--     invite.reply hand-over through fn_sales_engineer_acts_on_supplier_reply, which books exactly ONE follow-up
--     (supplier_reply_followup, unique per inbound message) at +7 days (+14 for "later"), whose text ends "This is the only reminder
--     we will send about it", and the generic /en/portal link, not his company's own. Then nothing, ever. Rows today: 8; 2 sent
--     (inbound 1615 lead 19398, inbound 1871 lead 455), 1 due (inbound 2214, Shine, who has since registered), 5 dropped.
--   * The hand-over is filed by trg_invite_reply_reaches_sales_engineer -> fn_marketing_files_invite_reply on INSERT of the mail; the
--     trigger swallows any error into a server WARNING nobody reads. A reply whose hand-over failed (Hindco) never had a follow-up row.
--   * A support case closed on such a mail asks for a CSAT rating (fn_support_case_closed_asks_for_the_rating) unless something set
--     csat_requested_at first; a prospect who asked for "the plans" was sent a rating survey instead of the plans.
--   * test_reply: trg_a05_test_reply_leaves_review files as test_reply only fn_is_founder_own_inbox addresses (a named list, one of
--     which is ahmad@666realestate.ae, the address Triple Six Real Estate (leads 158318, approved) registered with; its 28 Oct
--     "Definitely but later", inbound 1483, was filed test_reply by that list). Unchanged here: the list is the founder's to correct.
--
-- WHAT THIS CHANGES
--   1. supplier_reply_followup.touch (1..3), unique per (inbound message, touch).
--   2. fn_sales_engineer_follows_up_supplier_replies: each follow-up carries his company's OWN registration link
--      (/portal?t=<claim_token>) and one next step; after a send the next touch is booked 7 days later, three touches at most
--      (days 7, 14, 21; 'later' starts at 14; a subsidiary question keeps its single note). Same stops before every send: he started
--      registering or claimed, the reading did not allow an answer, a machine or fixture address, email_suppressions (a decline is
--      suppressed by fn_sales_engineer_acts_on_supplier_reply), he wrote again. New: the campaign's own stops (invite_enabled,
--      supplier_outreach_golive, an open invite_brake, the bounce judgement's company brake) hold every touch, and at most
--      app_secrets.invite_daily_cap follow-ups leave per Dubai day. leads.invite_followups and invite_last_followup_at count them.
--   3. fn_sales_engineer_books_prospect_chase + trigger z54 on inbound_messages: the moment customer_support's answer to a supplier
--      question from an invited lead who has not registered is recorded (replied_at), touch 1 is booked from the mail itself, so a
--      failed hand-over cannot lose him; a failure here is an it_engineer finding, never silent.
--   4. trg_invite_reply_reaches_sales_engineer records a failed hand-over as an it_engineer finding (it still never costs the mail)
--      and marks the lead 'replied'.
--   5. fn_support_case_closed_asks_for_the_rating asks no rating of an invited supplier who has not registered: his case is a sale
--      in progress, not a service he can rate (csat_request_error says so).
--   6. ONE-OFF: a lead whose single follow-up was already sent and who has not registered or declined gets touch 2 booked at
--      max(sent + 7 days, now + 1 hour); every stop above still applies at send time. At 18 Nov 2026 that is inbound 1871 (lead 455).
--
-- Pending: scripts/sql/pending/an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.txt
-- Prevented by: scripts/checks/an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.test.mjs

set local lock_timeout = '1500ms';   -- apply discipline: a DDL that waits behind live traffic gives up, never queues it

-- ── 1. the touch ────────────────────────────────────────────────────────────────────────────────
alter table public.supplier_reply_followup add column if not exists touch smallint not null default 1;
do $ddl$
begin
  if not exists (select 1 from pg_constraint where conname = 'supplier_reply_followup_touch_check') then
    alter table public.supplier_reply_followup add constraint supplier_reply_followup_touch_check check (touch between 1 and 3);
  end if;
  if exists (select 1 from pg_constraint where conname = 'supplier_reply_followup_inbound_message_id_key') then
    alter table public.supplier_reply_followup drop constraint supplier_reply_followup_inbound_message_id_key;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'supplier_reply_followup_message_touch_key') then
    alter table public.supplier_reply_followup add constraint supplier_reply_followup_message_touch_key unique (inbound_message_id, touch);
  end if;
end $ddl$;
comment on column public.supplier_reply_followup.touch is
  'Which follow-up this is (1..3, 7 days apart) of a prospect we answered who has not registered or declined. sales_engineer, 18 Nov 2026.';

-- ── 2. the hand-over handler books touch 1 (live body, 18 Nov 2026; only the insert's conflict target and the stage changed) ──
create or replace function public.fn_sales_engineer_acts_on_supplier_reply(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
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
      -- 18 Nov 2026: the first of up to three touches (fn_sales_engineer_follows_up_supplier_replies books the next after each send)
      insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, touch)
      values (m.id, l.id, v_from, case when v_intent in ('subsidiary', 'later') then v_intent else 'interested' end, v_followup, 1)
      on conflict (inbound_message_id, touch) do nothing;
      if l.id is not null and lower(btrim(coalesce(l.email, ''))) = v_from then   -- his own lead only, never a domain match
        update public.leads set lifecycle_stage = 'replied' where id = l.id and coalesce(lifecycle_stage, 'not_contacted') in ('not_contacted', 'contacted', 'no_response');
      end if;
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
revoke execute on function public.fn_sales_engineer_acts_on_supplier_reply(bigint) from public, anon, authenticated;

-- ── 3. touch 1 from the answered mail itself, whatever happened to the hand-over ─────────────────
create or replace function public.fn_sales_engineer_books_prospect_chase(p_inbound_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare m public.inbound_messages; l public.leads; v_from text; v_reading text; v_intent text; v_id bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if m.id is null or m.replied_at is null then return jsonb_build_object('booked', false, 'reason', 'not answered'); end if;
  select d.reading into v_reading from public.mailbox_reply_decision d where d.inbound_message_id = m.id;
  if not (coalesce(m.ai_category, '') = 'supplier_question' or coalesce(v_reading, '') in ('supplier_registration', 'supplier_account_question')) then
    return jsonb_build_object('booked', false, 'reason', 'not a supplier question');
  end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  if v_from is null or public.fn_is_demo_email(v_from) or public.fn_is_founder_own_inbox(v_from) then
    return jsonb_build_object('booked', false, 'reason', 'a fixture or the founder''s own address');
  end if;
  -- the company is the one whose OWN address wrote (review of #2051: inbound_messages.lead_id can be a domain match)
  select * into l from public.leads x where lower(btrim(x.email)) = v_from order by (x.id = m.lead_id) desc, x.id limit 1;
  if l.id is null or (l.invited_at is null and l.invite_status is null) then return jsonb_build_object('booked', false, 'reason', 'not an invited lead at this exact address'); end if;
  if coalesce(l.claimed, false) or l.registration_submitted_at is not null then return jsonb_build_object('booked', false, 'reason', 'he registered'); end if;
  if not public.fn_mailbox_followup_allowed(m.id) then return jsonb_build_object('booked', false, 'reason', 'the reading did not allow an answer'); end if;
  v_intent := public.fn_supplier_reply_intent(m.body);
  if v_intent = 'decline' then return jsonb_build_object('booked', false, 'reason', 'a decline'); end if;
  insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, touch)
  values (m.id, l.id, v_from, case when v_intent in ('subsidiary', 'later') then v_intent else 'interested' end,
          m.replied_at + case v_intent when 'later' then interval '14 days' else interval '7 days' end, 1)
  on conflict (inbound_message_id, touch) do nothing
  returning id into v_id;
  update public.leads set lifecycle_stage = 'replied' where id = l.id and coalesce(lifecycle_stage, 'not_contacted') in ('not_contacted', 'contacted', 'no_response');
  return jsonb_build_object('booked', v_id is not null, 'followup_id', v_id, 'lead_id', l.id, 'intent', v_intent);
end $fn$;
revoke execute on function public.fn_sales_engineer_books_prospect_chase(bigint) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_books_prospect_chase(bigint) to service_role;

create or replace function public.trg_answered_prospect_gets_its_chase()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_sales_engineer_books_prospect_chase(new.id);
  exception when others then
    -- never costs the answer it rides on, and never silent: the it_engineer sees it
    begin
      perform public.fn_it_engineer_finding_upsert('sales_engineer:prospect_chase_not_booked:' || new.id,
        'An answered prospect''s follow-up could not be booked (inbound_messages ' || new.id || ')',
        'public.fn_sales_engineer_books_prospect_chase', 'customer_facing', 1,
        jsonb_build_object('inbound_message_id', new.id, 'error', left(sqlerrm, 400), 'owner_seat', 'sales_engineer'),
        '{}'::text[], array['why fn_sales_engineer_books_prospect_chase failed for this mail'], 'sales_engineer');
    exception when others then raise warning 'trg_answered_prospect_gets_its_chase %: %', new.id, sqlerrm;
    end;
  end;
  return null;
end $fn$;
revoke execute on function public.trg_answered_prospect_gets_its_chase() from public, anon, authenticated;
drop trigger if exists z54_answered_prospect_gets_its_chase on public.inbound_messages;
create trigger z54_answered_prospect_gets_its_chase after update of replied_at on public.inbound_messages
  for each row when (new.replied_at is not null and old.replied_at is null)
  execute function public.trg_answered_prospect_gets_its_chase();

-- ── 4. a failed hand-over is a finding, not a warning nobody reads ───────────────────────────────
create or replace function public.trg_invite_reply_reaches_sales_engineer()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb;
begin
  -- never costs the mail it rides on; a failure is recorded as an it_engineer finding (18 Nov 2026: Hindco's was lost silently)
  begin
    v := public.fn_marketing_files_invite_reply(new.id);
    if coalesce((v->>'due')::boolean, false) and (v->>'lead_id') is not null then
      update public.leads set lifecycle_stage = 'replied'
       where id = (v->>'lead_id')::bigint and coalesce(lifecycle_stage, 'not_contacted') in ('not_contacted', 'contacted', 'no_response')
         and lower(btrim(coalesce(email, ''))) = lower(substring(coalesce(new.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
    end if;
  exception when others then
    begin
      perform public.fn_it_engineer_finding_upsert('sales_engineer:invite_reply_not_filed:' || new.id,
        'An invited supplier''s reply was not handed to the sales engineer (inbound_messages ' || new.id || ')',
        'public.trg_invite_reply_reaches_sales_engineer -> fn_marketing_files_invite_reply', 'customer_facing', 1,
        jsonb_build_object('inbound_message_id', new.id, 'error', left(sqlerrm, 400), 'owner_seat', 'sales_engineer'),
        '{}'::text[], array['why fn_marketing_files_invite_reply failed for this mail'], 'sales_engineer');
    exception when others then
      raise warning 'trg_invite_reply_reaches_sales_engineer: inbound_messages % not handed to the sales engineer: %', new.id, sqlerrm;
    end;
  end;
  return null;
end $fn$;
revoke execute on function public.trg_invite_reply_reaches_sales_engineer() from public, anon, authenticated;

-- ── 5. up to three touches, his own link, inside the campaign's limits ───────────────────────────
create or replace function public.fn_sales_engineer_follows_up_supplier_replies()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; f public.supplier_reply_followup; l public.leads; v_acted int := 0; v_sent int := 0; v_dropped int := 0; v_site text; v_body text;
  v_err jsonb := '[]'::jsonb; v_link text; v_free int; v_stop text; v_cap int; v_today int; v_next bigint;
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

  -- 3. the follow-ups, on a Dubai weekday inside the sending window, inside the campaign's own stops and daily cap
  -- review of #2051: the nudge's own calendar rule too: no follow-up on a UAE public holiday (company_calendar)
  if extract(isodow from now() at time zone 'Asia/Dubai') not in (6, 7)
     and extract(hour from now() at time zone 'Asia/Dubai') between 9 and 16
     and not exists (select 1 from public.company_calendar c where c.kind = 'public_holiday'
                      and (now() at time zone 'Asia/Dubai')::date between c.starts_on and coalesce(c.ends_on, c.starts_on)) then
    -- THE ONE DAILY CAP (ruling #1007): invite_daily_cap is spent by invitations and nudges queued this UTC day (exactly as
    -- enqueue_supplier_invites and fn_sales_engineer_nudges_invited_suppliers count it) and by the follow-ups sent this UTC day;
    -- send_outbox counts the follow-ups into the same number at send time. The advisory lock makes the read-and-spend one step,
    -- so two runs at once cannot both spend the last slot (the second waits, then reads the first one's sends).
    perform pg_advisory_xact_lock(hashtext('qd_invite_daily_cap'));
    v_stop := case when not coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
                     then 'the supplier campaign is paused (invite_enabled is false)'
                   when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                   when exists (select 1 from public.invite_brake b where b.resumed_at is null) then 'a bounce brake is open'
                   when coalesce((public.fn_invite_bounce_judgement(now())->>'company_brake')::boolean, false) then 'the bounce judgement stops the company' end;
    v_cap := coalesce((select nullif(btrim(value), '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
    v_today := (select count(*) from public.notifications n where n.type in ('supplier_invite', 'supplier_invite_nudge')
                 and (n.created_at at time zone 'UTC')::date = (now() at time zone 'UTC')::date and not public.fn_is_demo_email(n.to_email))
             + (select count(*) from public.supplier_reply_followup x where x.state = 'sent'
                 and (x.done_at at time zone 'UTC')::date = (now() at time zone 'UTC')::date);
    select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
    v_site := coalesce(v_site, 'https://quotesdone.com');
    v_free := coalesce((select p.supplier_free_count from public.pricing_config p where p.id = 1), 1000);
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
      -- review of #2051: the founder's own addresses, and every rule the campaign itself obeys (fn_supplier_outreach_reachable: a demo,
      -- banned or closed company, a bounced invitation, a sanctions hit, an address fn_email_sendable refuses, the company already
      -- registered under another account), plus an invitation that drew a complaint or an unsubscribe
      if public.fn_is_founder_own_inbox(f.to_email)
         or (l.id is not null and (not public.fn_supplier_outreach_reachable(l, f.to_email)
                                   or coalesce(l.invite_status, '') in ('complained', 'unsubscribed')))
         or (l.id is null and not coalesce((public.fn_email_sendable(f.to_email)->>'ok')::boolean, false)) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'not reachable by the campaign''s own rules (founder''s address, bounced, complained, unsubscribed, demo, banned, screened or registered under another account)', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      if exists (select 1 from public.inbound_messages n where lower(btrim(coalesce(substring(n.from_email from '<([^>]+)>'), n.from_email))) = lower(btrim(f.to_email)) and n.id > f.inbound_message_id and n.owner_role is distinct from 'it_engineer') then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the supplier wrote again: that mail is answered on its own', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      -- the campaign's stops and cap hold the touch (it stays due, nothing is lost)
      if v_stop is not null or v_today >= v_cap then continue; end if;
      -- his company's own claim link ONLY when the follow-up goes to that company's own address (review of #2051: inbound_email links a
      -- lead by mail DOMAIN, so another person on a shared domain must never receive this company's token); else the plain portal
      v_link := case when f.intent <> 'subsidiary' and l.claim_token is not null and lower(btrim(coalesce(l.email, ''))) = lower(btrim(f.to_email))
                     then v_site || '/portal?t=' || l.claim_token else v_site || '/portal' end;
      v_body := case
        when f.intent = 'subsidiary' then E'Hello,\n\nA week ago you asked about registering a separate company. It registers with its own trade licence and a different e-mail address: ' || v_site || E'/portal\n\nIf we can help, reply to this e-mail. This is the only reminder we will send about it.'
        else 'Hello,' || E'\n\n'
          || case f.touch when 1 then case f.intent when 'later' then 'You told us a little while ago that later would suit you better. ' else 'You replied to us last week and your company has not registered yet. ' end
                          when 2 then 'A short reminder: your company has not registered with QuotesDone yet. '
                          else 'One last note from us: your company has not registered with QuotesDone yet. ' end
          || 'Registration is free for our first ' || to_char(v_free, 'FM999,999') || ' suppliers and takes a few minutes.'
          || E'\n\nNext step: open your company''s own registration link, choose "Create account" with your work e-mail and type the 6-digit code we e-mail you:\n'
          || v_link || E'\n\n'
          || case when f.touch >= 3 then 'This is the last reminder we will send about it. If something is stopping you, reply to this e-mail.'
                  else 'If something is stopping you, or you would rather not hear from us, reply to this e-mail.' end end;
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', f.to_email, 'to_role', 'supplier',
        'lead_id', f.lead_id, 'lang', 'en', 'subject', 'Your QuotesDone supplier registration', 'body', v_body,
        'dedupe_key', 'supplier_reply_followup:' || f.id)));
      update public.supplier_reply_followup set state = 'sent', outcome = 'follow-up ' || f.touch || ' queued', done_at = now() where id = f.id;
      if f.lead_id is not null then
        update public.leads set invite_followups = coalesce(invite_followups, 0) + 1, invite_last_followup_at = now() where id = f.lead_id;
      end if;
      -- the next touch, 7 days on, three at most; a subsidiary question keeps its single note
      if f.intent <> 'subsidiary' and f.touch < 3 then
        insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, touch)
        values (f.inbound_message_id, f.lead_id, f.to_email, f.intent, now() + interval '7 days', f.touch + 1)
        on conflict (inbound_message_id, touch) do nothing returning id into v_next;
      end if;
      v_sent := v_sent + 1; v_today := v_today + 1;
    end loop;
  end if;
  return jsonb_build_object('acted', v_acted, 'followups_sent', v_sent, 'followups_dropped', v_dropped, 'held_by', v_stop,
                            'sent_today', v_today, 'daily_cap', v_cap, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_sales_engineer_follows_up_supplier_replies() from public, anon, authenticated;

-- ── 6. no rating survey for a prospect who has not registered (live body, 18 Nov 2026; only the prospect test added) ──
create or replace function public.fn_support_case_closed_asks_for_the_rating()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare v_p public.support_customer_profile; v_lang text := coalesce(new.lang, 'en'); v_body text; v_err text; v_phone text;
begin
  if new.state <> 'closed' or old.state = 'closed' or new.csat_requested_at is not null then return null; end if;
  if exists (select 1 from public.feedback f where f.case_id = new.case_id and f.kind = 'csat') then return null; end if;
  select * into v_p from public.support_customer_profile where id = new.customer_profile_id;
  -- 18 Nov 2026 (sales_engineer): an invited supplier who has not registered is a sale in progress, not a service he can rate. His
  -- case closes without a survey; the chase (supplier_reply_followup) carries the conversation on until he registers or declines.
  if exists (select 1 from public.leads l
              where (l.id = v_p.lead_id or (v_p.lead_id is null and lower(btrim(l.email)) = lower(btrim(coalesce(v_p.email, new.party_id, '')))))
                and (l.invited_at is not null or l.invite_status is not null)
                and not coalesce(l.claimed, false) and l.registration_submitted_at is null) then
    update public.support_case set csat_requested_at = now(), csat_request_error = 'not asked: an invited supplier who has not registered (a sale in progress, not a service to rate)'
     where case_id = new.case_id;
    return null;
  end if;
  v_body := case when v_lang = 'ar'
    then 'كيف كانت خدمتنا في البلاغ ' || new.case_ref || E'؟\nأرسلوا رقمًا من ١ (غير راضٍ) إلى ٥ (راضٍ جدًا)، '
         || 'ويمكنكم إضافة رقم ثانٍ من ١ (صعب جدًا) إلى ٧ (سهل جدًا) لمدى سهولة حل المشكلة. مثال: ٥ ٧'
    else 'How did we do on case ' || new.case_ref || E'?\nReply with a number from 1 (unhappy) to 5 (very happy). '
         || 'You can add a second number from 1 (very hard) to 7 (very easy) for how easy it was to get it solved, e.g. "5 7".' end;
  if new.last_channel = 'whatsapp' then
    v_phone := coalesce(case when new.party_id ~ '^\+?[0-9]{9,}$' then new.party_id end,
                        (select coalesce(c.whatsapp_phone, c.phone) from public.customers c where c.id = v_p.customer_id),
                        (select coalesce(l.whatsapp_phone, l.phone_e164, l.phone) from public.leads l where l.id = v_p.lead_id));
  end if;
  begin
    if v_phone is not null then
      insert into public.notifications (type, kind, to_phone, to_role, channel, lang, subject, body, requested_by, sender)
      values ('support_csat_request', 'support_csat_request', v_phone, new.party_kind, 'whatsapp', v_lang, 'Case ' || new.case_ref || ' rating', v_body, 'customer_support', 'customer_support');
    elsif v_p.email is not null then
      insert into public.notifications (type, kind, to_email, to_role, channel, lang, subject, body, requested_by, sender)
      values ('support_csat_request', 'support_csat_request', v_p.email, new.party_kind, 'email', v_lang,
              case when v_lang = 'ar' then 'قيّموا خدمتنا في البلاغ ' || new.case_ref else 'How did we do? Case ' || new.case_ref end,
              v_body, 'customer_support', 'customer_support');
    else
      v_err := 'no channel to ask on';
    end if;
  exception when others then
    v_err := left(sqlerrm, 500);   -- a refused notice never undoes the close
  end;
  update public.support_case set csat_requested_at = case when v_err is null then now() end, csat_request_error = v_err
   where case_id = new.case_id;
  return null;
end $fn$;
revoke execute on function public.fn_support_case_closed_asks_for_the_rating() from public, anon, authenticated;

-- ── 7. ONE-OFF: a prospect whose single follow-up already went gets his second touch (every stop still applies at send time) ──
insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, touch)
select f.inbound_message_id, f.lead_id, f.to_email, f.intent, greatest(f.done_at + interval '7 days', now() + interval '1 hour'), 2
  from public.supplier_reply_followup f
  join public.leads l on l.id = f.lead_id
 where f.state = 'sent' and f.touch = 1 and f.intent <> 'subsidiary'
   and not coalesce(l.claimed, false) and l.registration_submitted_at is null
   and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(f.to_email)
   and not public.fn_is_founder_own_inbox(f.to_email)
   and public.fn_supplier_outreach_reachable(l, f.to_email)
   and not exists (select 1 from public.email_suppressions s where lower(s.email) = lower(f.to_email))
on conflict (inbound_message_id, touch) do nothing;

-- ── PROBE: reads only, touches no row; a VERDICT ROW, never a raise (this file creates DDL: apply discipline section 4) ──────
select case
  when not exists (select 1 from pg_constraint where conname = 'supplier_reply_followup_message_touch_key')
    then 'PROBE FAILED: the (inbound_message_id, touch) key is missing'
  when exists (select 1 from pg_constraint where conname = 'supplier_reply_followup_inbound_message_id_key')
    then 'PROBE FAILED: the one-follow-up key is still there'
  when not exists (select 1 from pg_trigger where tgname = 'z54_answered_prospect_gets_its_chase' and tgrelid = 'public.inbound_messages'::regclass)
    then 'PROBE FAILED: z54 trigger missing'
  when position('fn_it_engineer_finding_upsert' in (select prosrc from pg_proc where proname = 'trg_invite_reply_reaches_sales_engineer')) = 0
    then 'PROBE FAILED: the hand-over trigger still swallows its error'
  when position('lower(btrim(coalesce(l.email, ''''))) = lower(btrim(f.to_email))' in (select prosrc from pg_proc where proname = 'fn_sales_engineer_follows_up_supplier_replies')) = 0
    then 'PROBE FAILED: the claim token is not tied to the company''s own address'
  else 'PROBE OK' end as verdict;
