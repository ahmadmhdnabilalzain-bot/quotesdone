-- EVERY REAL SUPPLIER REPLY IS CHASED, AND A "LATER" IS ASKED AGAIN LATER.
-- Seat: sales_engineer. Agent: chase-fix. 19 Nov 2026. Founder ruling 1543 ("if the agent does not follow up properly on email with
-- replies it is a big issue"), ruling 1633 (a vendor's mail gets no supplier reply), ruling 1729 (Triple Six is a supplier).
--
-- WHAT WAS MEASURED (production, read-only, 19 Nov 2026 15:07 UTC; live bodies read with pg_get_functiondef and equal, line for line,
-- to an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql):
--   * Lead 455 (powdercoating.ae): touch 1 (supplier_reply_followup 11) left 12 Nov 06:50 UTC; touch 2 (row 18) was booked by that
--     file's one-off, due 19 Nov 06:50 UTC (10:50 Dubai, a Thursday). Still 'due' at 15:07: not dropped, so every drop rule passed it.
--     fn_sales_engineer_follows_up_supplier_replies reads its stops only inside the 09:00-16:59 Dubai window (05:00-12:59 UTC), and
--     its first stop was app_secrets.invite_enabled, false until the CEO's restart at 14:17 UTC (MANIFEST, 19 Nov 14:17): every run
--     from 06:50 to 12:55 UTC held the touch with "the supplier campaign is paused". By 14:17 UTC it was 18:17 in Dubai, outside the
--     window, so no run reached it. held_by reads null in seat_duty.last_result because that run (15:05 UTC) was outside the
--     window, where the stops are never read. NOT the cap: 0 invitations queued today of a cap of 20, and enqueue_supplier_invites
--     reserves each due follow-up in the same count. NOT a holiday (next: 2-3 Dec) and NOT the lock (pg_advisory_xact_lock is a
--     wait, released at commit). No open invite_brake. invite_followups reads 0 on leads 455 and 19398 although each has 1 sent
--     follow-up: both were sent by the body before 18 Nov 13:30, which did not count them.
--   * The invitation switch pauses COLD invitations (to unchecked addresses, for their bounces). A follow-up goes to an address that
--     wrote to us. Holding it on that switch silenced every warm conversation for as long as the campaign was paused: a defect
--     against ruling 1543, introduced 18 Nov by the chase file.
--   * The five dropped rows (supplier_reply_followup 12-16, dropped 11 Nov 11:10 UTC "the mail it follows was not one the reading
--     allowed an answer to"). None has a mailbox_reply_decision row; each was answered by sales_engineer within 10 s and stamped
--     ai_category 'no_auto_reply' with the summary "Not answered automatically: internal", i.e. triage stood back because a seat had
--     answered: that category says nothing about the sender. fn_mailbox_followup_allowed, with no reading, allowed only a mail
--     answered by customer_support, so all five fell:
--       1872 info@ Triple Six (666realestate.ae), 8 Nov, "Registration": asks how to register the company. A REAL SUPPLIER, interested.
--       1873 info@ Triple Six, 8 Nov, "Re: Registration": says registering is complicated. A REAL SUPPLIER, interested with an objection.
--            Both drops were wrong. No chase is owed now: lead 158318 registered 12 Nov 19:55 UTC and is approved.
--       1874 azure-noreply@ microsoft.com, "Your new Azure account is ready": a vendor notice. Drop correct (ruling 1633).
--       1994 supportmail@ techsupport.microsoft.com, an Azure quota ticket: a vendor. Drop correct.
--       2069 the same Microsoft ticket ("backlogged ... reviewed again"): read "later" by the keyword rule, but a vendor. Drop correct.
--   * A "later" waited 14 days for its first touch. The founder's instruction for this fix: ask a "later" again about a month on.
--   * Inbound 1483 (ahmad@666realestate.ae, 28 Oct, "Definitely but later") was filed test_reply by trg_a05_test_reply_leaves_review
--     because fn_is_founder_own_inbox named that address. The live fn_is_founder_own_inbox no longer names it (ruling 1729,
--     triple_six_real_estate_is_a_supplier_and_its_mail_is_real_supplier_mail.sql, 18 Nov 17:33 UTC), and no app_secrets
--     founder_email / admin_emails / expense_forwarders entry names it: new mail from it is not test mail. 1483 needs no chase: the
--     company registered 12 Nov.
--
-- WHAT THIS CHANGES
--   1. fn_mailbox_followup_allowed: with no reading row, a mail answered by sales_engineer is followed up too, when the sender is
--      evidenced as a supplier (category supplier_question, or fn_mail_sender_known = 'supplier': a lead's own address) and no hard
--      rule refuses it (bounce, machine sender, auto-submitted, list mail, the founder's inbox, our own domain). test_reply, spam and
--      opt_out are never followed up. A reading row still decides alone. Its callers are the chase routines and the follow-up branch
--      of fn_mailbox_reply_may_leave only, so no other reply changes.
--   1b. fn_prospect_chase_next_touch: a "later" is re-asked ONCE, at 30 days, and never again (was: touches 2 and 3 at 37 and 44 days,
--      review of #2075); an interested prospect keeps touches 1-3, a subsidiary question its single note.
--   2. fn_sales_engineer_books_prospect_chase: the same supplier evidence opens the booking; a "later" is booked 30 days on (was 14);
--      a fixture run (qd.duty_fixtures = on) books only a ZZ DEMO lead at a reserved address, a real run never a fixture.
--   3. fn_sales_engineer_acts_on_supplier_reply: a "later" 30 days on (was 14). Nothing else.
--   4. fn_sales_engineer_follows_up_supplier_replies: invite_enabled no longer holds a follow-up; golive, an open bounce brake, the
--      company brake, the one daily cap, the Dubai weekday window and the holiday calendar still do. Touch 1 of a "later" says
--      "about a month ago".
--   5. ONE-OFF: leads.invite_followups counts the follow-ups already sent (leads 455 and 19398: 0 -> 1).
--   Lead 455's touch 2 sends on the first run inside the window: Friday 20 Nov 2026 from 05:00 UTC (09:00 Dubai), unless he
--   registers, writes again, or a brake opens first. That is true with or without this file (invite_enabled is true since 14:17).
--
-- How to apply: node scripts/apply_sql.mjs scripts/sql/every_real_supplier_reply_is_chased_and_a_later_is_asked_again_later.sql --apply --ddl, then delete
--   scripts/sql/pending/every_real_supplier_reply_is_chased_and_a_later_is_asked_again_later.txt and append this file to the END of scripts/sql/MANIFEST.txt. The probe returns a
--   verdict row; the applier exits 3 on PROBE FAILED.
-- Rollback: re-apply the four bodies from an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql (sections 2, 3
--   and 5) and fn_mailbox_followup_allowed from a_reply_from_the_supplier_mailbox_leaves_only_when_the_reading_said_answer.sql. The
--   counter backfill needs no rollback (it counts rows that exist).
-- Pending: scripts/sql/pending/every_real_supplier_reply_is_chased_and_a_later_is_asked_again_later.txt
-- Prevented by: scripts/checks/every_real_supplier_reply_is_chased_and_a_later_is_asked_again_later.test.mjs and the probe below (a ZZ DEMO interested reply and a later reply each book a chase row; an auto-reply, a vendor and a
--   test reply book none; a sent later books no further touch; the follow-up names no invitation switch).

set local lock_timeout = '1500ms';   -- apply discipline: a DDL that waits behind live traffic gives up, never queues it

-- ── 1. which mail may be followed up ────────────────────────────────────────────────────────────
create or replace function public.fn_mailbox_followup_allowed(p_inbound_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  -- a reading decides alone (ruling 1633). Without one: an answer a seat sent, to a sender evidenced as a supplier, that no hard rule
  -- refuses. 19 Nov 2026: answered by sales_engineer counts too (Triple Six's 1872 and 1873 were dropped for want of it); the
  -- evidence is what keeps Microsoft's 1874, 1994 and 2069 out (no lead holds their address).
  select coalesce(
    (select d.may_reply from public.mailbox_reply_decision d where d.inbound_message_id = p_inbound_id),
    exists (select 1 from public.inbound_messages i
             where i.id = p_inbound_id
               and coalesce(i.ai_category, '') not in ('test_reply', 'spam', 'opt_out')
               and (i.replied_by = 'customer_support'
                    or (i.replied_by = 'sales_engineer'
                        and (coalesce(i.ai_category, '') = 'supplier_question'
                             or coalesce(public.fn_mail_sender_known(lower(substring(coalesce(i.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'))), '') = 'supplier'))))
      and public.fn_mailbox_reply_hard_rule(p_inbound_id) is null)
$fn$;
revoke execute on function public.fn_mailbox_followup_allowed(bigint) from public, anon, authenticated;
grant execute on function public.fn_mailbox_followup_allowed(bigint) to service_role;

-- ── 1b. which touch follows a sent one (19 Nov 2026, review of #2075): an interested prospect 1 -> 2 -> 3, then none; a "later" and a
--     subsidiary question get their single touch and none after it ──
create or replace function public.fn_prospect_chase_next_touch(p_intent text, p_touch integer)
returns smallint language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when coalesce(p_intent, '') in ('subsidiary', 'later') or p_touch is null or p_touch >= 3 then null
              else (p_touch + 1)::smallint end
$fn$;
revoke execute on function public.fn_prospect_chase_next_touch(text, integer) from public, anon, authenticated;
grant execute on function public.fn_prospect_chase_next_touch(text, integer) to service_role;

-- ── 2. touch 1 from the answered mail itself (live body, 19 Nov 2026; supplier evidence, 30-day later, fixture mode) ──
create or replace function public.fn_sales_engineer_books_prospect_chase(p_inbound_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare m public.inbound_messages; l public.leads; v_from text; v_reading text; v_intent text; v_id bigint;
  -- a fixture run (set local qd.duty_fixtures = 'on', inside a probe) books ONLY a ZZ DEMO lead at a reserved address; a real run never does
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if m.id is null or m.replied_at is null then return jsonb_build_object('booked', false, 'reason', 'not answered'); end if;
  select d.reading into v_reading from public.mailbox_reply_decision d where d.inbound_message_id = m.id;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  -- 19 Nov 2026: a supplier's mail is known by its reading, its triage category, OR its sender being a lead's own address
  -- (fn_mail_sender_known): Triple Six's 8 Nov "How to register our company?" (inbound 1872, category no_auto_reply because a
  -- seat had already answered it) was a supplier's question by its sender, and no rule here could see it
  if not (coalesce(m.ai_category, '') = 'supplier_question' or coalesce(v_reading, '') in ('supplier_registration', 'supplier_account_question')
          or coalesce(public.fn_mail_sender_known(v_from), '') = 'supplier') then
    return jsonb_build_object('booked', false, 'reason', 'not a supplier question');
  end if;
  if v_from is null or public.fn_is_demo_email(v_from) <> v_fx or public.fn_is_founder_own_inbox(v_from) then
    return jsonb_build_object('booked', false, 'reason', 'a fixture or the founder''s own address');
  end if;
  -- the company is the one whose OWN address wrote (review of #2051: inbound_messages.lead_id can be a domain match)
  select * into l from public.leads x where lower(btrim(x.email)) = v_from order by (x.id = m.lead_id) desc, x.id limit 1;
  if l.id is null or (l.invited_at is null and l.invite_status is null) then return jsonb_build_object('booked', false, 'reason', 'not an invited lead at this exact address'); end if;
  if v_fx and not coalesce(l.is_demo, false) then return jsonb_build_object('booked', false, 'reason', 'a fixture run books only a ZZ DEMO lead'); end if;
  if coalesce(l.claimed, false) or l.registration_submitted_at is not null then return jsonb_build_object('booked', false, 'reason', 'he registered'); end if;
  if not public.fn_mailbox_followup_allowed(m.id) then return jsonb_build_object('booked', false, 'reason', 'the reading did not allow an answer'); end if;
  v_intent := public.fn_supplier_reply_intent(m.body);
  if v_intent = 'decline' then return jsonb_build_object('booked', false, 'reason', 'a decline'); end if;
  insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, touch)
  values (m.id, l.id, v_from, case when v_intent in ('subsidiary', 'later') then v_intent else 'interested' end,
          m.replied_at + case v_intent when 'later' then interval '30 days' else interval '7 days' end, 1)   -- 19 Nov 2026: a later, a month on
  on conflict (inbound_message_id, touch) do nothing
  returning id into v_id;
  update public.leads set lifecycle_stage = 'replied' where id = l.id and coalesce(lifecycle_stage, 'not_contacted') in ('not_contacted', 'contacted', 'no_response');
  return jsonb_build_object('booked', v_id is not null, 'followup_id', v_id, 'lead_id', l.id, 'intent', v_intent);
end $fn$;
revoke execute on function public.fn_sales_engineer_books_prospect_chase(bigint) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_books_prospect_chase(bigint) to service_role;

-- ── 3. the hand-over handler (live body, 19 Nov 2026; only the "later" interval changed) ─────────
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
      -- 19 Nov 2026: a "later" is asked again a month on (30 days), an interested reply a week on
      v_followup := now() + case v_intent when 'later' then interval '30 days' else interval '7 days' end;
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

-- ── 4. the follow-ups no longer wait on the invitation switch (live body, 19 Nov 2026; only the stop and one sentence changed) ──
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
    -- 19 Nov 2026 (ruling 1543): the invitation switch pauses COLD invitations; it no longer holds the follow-up of a supplier who
    -- WROTE to us. Measured: touch 2 of lead 455 (supplier_reply_followup 18), due 19 Nov 06:50 UTC, was held on every run of
    -- the 05:00-12:59 UTC window by invite_enabled = false, which turned true at 14:17 UTC, after the window had closed. The
    -- master switch, an open bounce brake and the bounce judgement's company brake (the sending domain all mail shares) still hold it.
    v_stop := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
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
          || case f.touch when 1 then case f.intent when 'later' then 'About a month ago you told us that later would suit you better. ' else 'You replied to us last week and your company has not registered yet. ' end
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
      -- the next touch, 7 days on, three at most; a subsidiary question keeps its single note, and (19 Nov 2026, review of #2075) a
      -- "later" its single re-ask at 30 days: fn_prospect_chase_next_touch decides, so the probe can prove it without sending
      if public.fn_prospect_chase_next_touch(f.intent, f.touch) is not null then
        insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, touch)
        values (f.inbound_message_id, f.lead_id, f.to_email, f.intent, now() + interval '7 days', public.fn_prospect_chase_next_touch(f.intent, f.touch))
        on conflict (inbound_message_id, touch) do nothing returning id into v_next;
      end if;
      v_sent := v_sent + 1; v_today := v_today + 1;
    end loop;
  end if;
  return jsonb_build_object('acted', v_acted, 'followups_sent', v_sent, 'followups_dropped', v_dropped, 'held_by', v_stop,
                            'sent_today', v_today, 'daily_cap', v_cap, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_sales_engineer_follows_up_supplier_replies() from public, anon, authenticated;

-- ── 5. ONE-OFF: the counter counts the follow-ups already sent (19 Nov 2026: leads 455 and 19398 read 0 with 1 sent each) ──
update public.leads l
   set invite_followups = s.n, invite_last_followup_at = greatest(l.invite_last_followup_at, s.last_at)
  from (select x.lead_id, count(*)::int as n, max(x.done_at) as last_at
          from public.supplier_reply_followup x where x.state = 'sent' and x.lead_id is not null group by x.lead_id) s
 where l.id = s.lead_id and coalesce(l.invite_followups, 0) < s.n;

-- ── PROBE: ZZ DEMO leads at example.invalid addresses only, inside a block that ALWAYS raises, so every row it writes rolls back
--    while the DDL above stays (apply discipline section 4); the verdict leaves the block in a transaction-local setting and is
--    RETURNED AS A ROW. It calls only the booking and the predicate, never the sender, so nothing can be queued to anyone. ──
do $probe$
declare v_p text[] := '{}'; v_tag text := 'zz-demo-chase-' || substr(md5(random()::text), 1, 10); v_res text;
  v_real_before bigint; v_real_after bigint; v_row18 text; la bigint; lb bigint; lc bigint; ma bigint; mb bigint; mc bigint; md bigint; me bigint;
  r jsonb; f public.supplier_reply_followup;
begin
  select count(*) into v_real_before from public.supplier_reply_followup where not public.fn_is_demo_email(to_email);
  select state || '|' || due_at::text into v_row18 from public.supplier_reply_followup where id = 18;
  begin
    perform set_config('qd.duty_fixtures', 'on', true);
    insert into public.leads (company_name, email, email_verified, invited_at, invite_status)
    values ('ZZ DEMO Chase Interested', v_tag || '-a@example.invalid', 'verified', now() - interval '10 days', 'sent') returning id into la;
    insert into public.leads (company_name, email, email_verified, invited_at, invite_status)
    values ('ZZ DEMO Chase Later', v_tag || '-b@example.invalid', 'verified', now() - interval '10 days', 'sent') returning id into lb;
    insert into public.leads (company_name, email, email_verified, invited_at, invite_status)
    values ('ZZ DEMO Chase Away', v_tag || '-c@example.invalid', 'verified', now() - interval '10 days', 'sent') returning id into lc;
    -- A: an interested reply customer_support answered (inbound 1871's shape)
    insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, triaged_at, replied_at, replied_by, ai_category)
    values (la, v_tag || '-a@example.invalid', v_tag || '-box@example.invalid', 'ZZ DEMO Re: your invitation', 'Please share the plans',
            now() - interval '1 hour', now() - interval '1 hour', now() - interval '50 minutes', 'customer_support', 'supplier_question') returning id into ma;
    -- B: a "later" a seat answered, no reading row, category no_auto_reply (inbound 1872 / 1483's shape)
    insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, triaged_at, replied_at, replied_by, ai_category, ai_summary)
    values (lb, v_tag || '-b@example.invalid', v_tag || '-box@example.invalid', 'ZZ DEMO Re: Registration', 'Definitely but later',
            now() - interval '1 hour', now() - interval '1 hour', now() - interval '50 minutes', 'sales_engineer', 'no_auto_reply',
            'Not answered automatically: internal (customer_mail.ts noAutoReply).') returning id into mb;
    -- C: the same supplier's out-of-office (Auto-Submitted: auto-replied)
    insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, triaged_at, replied_at, replied_by, ai_category, raw)
    values (lc, v_tag || '-c@example.invalid', v_tag || '-box@example.invalid', 'ZZ DEMO Automatic reply: away', 'I am out of the office until next week.',
            now() - interval '1 hour', now() - interval '1 hour', now() - interval '50 minutes', 'sales_engineer', 'no_auto_reply',
            jsonb_build_object('auto_submitted', 'auto-replied')) returning id into mc;
    -- D: a vendor's ticket no lead holds (inbound 1994 / 2069's shape), answered by a seat
    insert into public.inbound_messages (from_email, to_email, subject, body, created_at, triaged_at, replied_at, replied_by, ai_category)
    values (v_tag || '-vendor@example.invalid', v_tag || '-box@example.invalid', 'ZZ DEMO Your quota request', 'It will be reviewed again later.',
            now() - interval '1 hour', now() - interval '1 hour', now() - interval '50 minutes', 'sales_engineer', 'no_auto_reply') returning id into md;
    -- E: a test reply from a lead's own address
    insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, triaged_at, replied_at, replied_by, ai_category)
    values (la, v_tag || '-a@example.invalid', v_tag || '-box@example.invalid', 'ZZ DEMO test', 'test',
            now() - interval '1 hour', now() - interval '1 hour', now() - interval '50 minutes', 'sales_engineer', 'test_reply') returning id into me;

    r := public.fn_sales_engineer_books_prospect_chase(ma);
    select * into f from public.supplier_reply_followup where inbound_message_id = ma and touch = 1;
    if f.id is null or f.intent <> 'interested' or f.state <> 'due' or f.lead_id <> la
       or abs(extract(epoch from f.due_at - ((select replied_at from public.inbound_messages where id = ma) + interval '7 days'))) > 1 then
      v_p := v_p || ('A: an interested reply got no 7-day chase row: ' || r::text); end if;
    r := public.fn_sales_engineer_books_prospect_chase(mb);
    f := null; select * into f from public.supplier_reply_followup where inbound_message_id = mb and touch = 1;
    if f.id is null or f.intent <> 'later' or f.state <> 'due'
       or abs(extract(epoch from f.due_at - ((select replied_at from public.inbound_messages where id = mb) + interval '30 days'))) > 1 then
      v_p := v_p || ('B: a later reply got no 30-day chase row: ' || r::text); end if;
    -- ... and that one re-ask is the last: nothing follows a sent "later"; an interested prospect still gets 2 and 3, then none
    if public.fn_prospect_chase_next_touch('later', 1) is not null then v_p := v_p || 'B: a sent later books another touch'::text; end if;
    if public.fn_prospect_chase_next_touch('interested', 1) is distinct from 2 or public.fn_prospect_chase_next_touch('interested', 2) is distinct from 3
       or public.fn_prospect_chase_next_touch('interested', 3) is not null or public.fn_prospect_chase_next_touch('subsidiary', 1) is not null then
      v_p := v_p || 'the interested / subsidiary touch sequence changed'::text; end if;
    if not public.fn_mailbox_followup_allowed(mb) then v_p := v_p || 'B: the sender may not follow up a later its seat answered'::text; end if;
    r := public.fn_sales_engineer_books_prospect_chase(mc);
    if exists (select 1 from public.supplier_reply_followup where inbound_message_id = mc) or public.fn_mailbox_followup_allowed(mc) then
      v_p := v_p || ('C: an auto-reply got a chase: ' || r::text); end if;
    r := public.fn_sales_engineer_books_prospect_chase(md);
    if exists (select 1 from public.supplier_reply_followup where inbound_message_id = md) or public.fn_mailbox_followup_allowed(md) then
      v_p := v_p || ('D: a vendor no lead holds got a chase: ' || r::text); end if;
    r := public.fn_sales_engineer_books_prospect_chase(me);
    if exists (select 1 from public.supplier_reply_followup where inbound_message_id = me) or public.fn_mailbox_followup_allowed(me) then
      v_p := v_p || ('E: a test reply got a chase: ' || r::text); end if;
    -- a real run never books a fixture
    perform set_config('qd.duty_fixtures', '', true);
    delete from public.supplier_reply_followup where inbound_message_id = ma;
    r := public.fn_sales_engineer_books_prospect_chase(ma);
    if exists (select 1 from public.supplier_reply_followup where inbound_message_id = ma) then v_p := v_p || 'a real run booked a ZZ DEMO fixture'::text; end if;
    raise exception 'CHK<<%>>', coalesce(nullif(array_to_string(v_p, '; '), ''), 'ok');
  exception when others then
    v_res := case when sqlerrm like 'CHK<<%>>' then substring(sqlerrm from '^CHK<<(.*)>>$') else 'the probe itself failed: ' || sqlerrm end;
  end;
  -- after the rollback: nothing of the probe is left, no real row moved
  select count(*) into v_real_after from public.supplier_reply_followup where not public.fn_is_demo_email(to_email);
  if exists (select 1 from public.leads where email like v_tag || '%') or exists (select 1 from public.inbound_messages where from_email like v_tag || '%')
     or exists (select 1 from public.supplier_reply_followup where to_email like v_tag || '%') then
    v_res := v_res || '; the probe left a row behind'; end if;
  if v_real_after <> v_real_before or (select state || '|' || due_at::text from public.supplier_reply_followup where id = 18) is distinct from v_row18 then
    v_res := v_res || '; a real follow-up row changed'; end if;
  if position('key = ''invite_enabled''' in (select prosrc from pg_proc where proname = 'fn_sales_engineer_follows_up_supplier_replies')) > 0 then
    v_res := v_res || '; the follow-up still waits on the invitation switch'; end if;
  if position('public.fn_prospect_chase_next_touch(f.intent, f.touch) is not null then' in (select prosrc from pg_proc where proname = 'fn_sales_engineer_follows_up_supplier_replies')) = 0 then
    v_res := v_res || '; the sender does not ask fn_prospect_chase_next_touch for the next touch'; end if;
  if position('fn_supplier_outreach_golive()' in (select prosrc from pg_proc where proname = 'fn_sales_engineer_follows_up_supplier_replies')) = 0 then
    v_res := v_res || '; the follow-up lost its master switch'; end if;
  if has_function_privilege('anon', 'public.fn_mailbox_followup_allowed(bigint)', 'execute')
     or has_function_privilege('anon', 'public.fn_sales_engineer_books_prospect_chase(bigint)', 'execute') then
    v_res := v_res || '; anon may execute a chase routine'; end if;
  perform set_config('qd.chase_probe', case when v_res = 'ok' then 'PROBE OK: a ZZ DEMO interested reply is chased at 7 days and a later once at 30, then never again; an auto-reply, a vendor and a test reply are not; the follow-up no longer waits on invite_enabled'
                                            else 'PROBE FAILED: ' || v_res end, true);
end $probe$;
select current_setting('qd.chase_probe') as verdict;
