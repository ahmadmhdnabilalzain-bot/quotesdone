-- AN UNANSWERED MAIL IS HANDED TO ITS SEAT WITH ITS FACTS, NOT FILED AS A REVIEW OF A DECISION.
-- Seat: customer_support. Agent: customer_support held-mail retrier (19 Nov 2026; ledger 1436: no supplier goes unanswered).
--
-- WHY (production SELECTs, 19 Nov 2026): when email_triage cannot send an answer it handed the mail to the CEO as review.requested.
-- That kind means "a customer or supplier asked us to review an automated decision" (seat_handoff_kind.meaning); its payload held
-- only the inbound id and an ask, and fn_review_request_waits left it awaiting "the ceo verdict on review request ?". For inbound
-- 2169 (HomeBox, lead 853) the CEO's overdue question (ceo.overdue_handoff, 18 Nov) was shown exactly that, chose 'answer' and wrote
-- "this handoff does not identify the decision or the point you want reviewed" (agent_actions 393159): dismissed, nothing sent.
--
-- WHAT: registers mail.unanswered, customer_support to customer_support (the mail's owning seat), on the estate's own machinery:
--   * reply_within 24 h (support_first_reply_sla_hours); the handler fn_customer_support_holds_an_unanswered_mail leaves it waiting
--     and says, in `awaiting`, which mail from whom is owed what. email_triage (unanswered_mail.ts) files it with the mail's facts in
--     `what`: inbound id, sender, owner seat, received and hours waited, subject, why no answer went, and the draft if one exists.
--   * past the clock fn_handoff_overdue_escalate escalates it once to the CEO and fn_ceo_files_judgements files ceo.overdue_handoff
--     with owner customer_support, whose choices are 'chase' (a ceo.order to customer_support, due in 2 days, the CEO's words saying
--     what to answer) or 'close' with the reason. Both carry the mail's `what` and `awaiting`, so there is always context to act on.
--   * an answer that goes completes it (email_triage closeUnansweredHandover, fn_seat_handoff_complete).
-- THE DRIVE ESCALATES THE SAME WAY (23 Nov 2026, review of #2089). fn_customer_support_unanswered_inbound_tick handed every message
--   past support_first_reply_sla_hours (24) to the CEO as review.requested: the 2169 failure again, and the path a mail held after
--   its model attempts takes (inbound 2227, info@, 22 Nov, held by gateway_http_502:all_models_failed). For an E-MAIL it now files
--   mail.unanswered with the same facts and due_at now (it is already past the SLA), so the next overdue pass gives the CEO chase or
--   close. The body is the live one (pg_get_functiondef, 23 Nov 2026, identical to its canonical file
--   every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered.sql) with only that
--   branch changed. WhatsApp keeps review.requested (no mail to hand over; out of this change).
-- NOT CHANGED: review.requested and its handler, the CEO's routines, fn_seat_handoff.
-- prevented by: an_unanswered_mail_is_handed_to_its_seat_with_its_facts_probe.sql (LOCAL), email_triage/unanswered_mail.test.ts
-- APPLY: node scripts/apply_sql.mjs scripts/sql/an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql --apply --ddl
--   BEFORE deploying email_triage from the same PR (before it, fn_seat_handoff files the new kind as 'failed', unregistered).
-- ROLLBACK: re-apply every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered.sql's
--   fn_customer_support_unanswered_inbound_tick (the drive), then delete from public.seat_handoff_kind where type = 'mail.unanswered'; delete from public.event_subscription where
--   event_type like 'handoff.mail.unanswered.%'; drop function
--   public.fn_customer_support_holds_an_unanswered_mail(bigint); and redeploy email_triage from main.
-- LOCKS: one seat_handoff_kind row, five event_subscription seed rows, one new routine and one replaced (the drive).
set local lock_timeout = '1500ms';

create or replace function public.fn_customer_support_holds_an_unanswered_mail(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting',
           'customer_support has the e-mail inbound_messages #' || coalesce(a.detail->>'inbound_message_id', '?')
           || ' from ' || coalesce(a.detail->>'from_email', 'an unknown sender')
           || ' (' || left(coalesce(a.detail->>'subject', ''), 120) || ', received ' || coalesce(a.detail->>'received_at', '?')
           || ') answered in its thread or closed with the reason; no answer went because: ' || left(coalesce(a.detail->>'error', 'not recorded'), 200)
           || case when coalesce(a.detail->>'draft', '') <> '' then '; a draft exists' else '' end)
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_customer_support_holds_an_unanswered_mail(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('mail.unanswered', 'customer_support', 'customer_support',
   'An e-mail a person wrote to QuotesDone has no answer: email_triage could not send one (the reason is in the payload). It is the mail, not a decision to review: its facts are inbound id, sender, owner seat, when it arrived and how long it has waited, the subject, what they wrote and the draft if one exists. Answer it in its thread, or close it with the reason nothing is owed. Past the clock the CEO orders customer_support to answer it, saying what to answer, or closes it with the reason.',
   'fn_customer_support_holds_an_unanswered_mail', interval '24 hours', false,
   'scripts/sql/an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- its echoes have an owner and an audience, the pool's own rule (three_hand_over_kinds_made_after_the_pool_have_an_owner_and_an_audience.sql):
-- the one seat that sends it, which also holds it; a failed one is the sender's to re-send and IT watches it. Seed rows: a row a seat
-- has edited since is never overwritten.
select set_config('qd.pool_seed', 'on', true);
insert into public.event_subscription as s (event_type, agent_key, owns, delivery, reason) values
  ('handoff.mail.unanswered.sent', 'customer_support', true, 'none', 'the one seat that sends mail.unanswered, to itself; nobody else: it holds the unanswered mail as a hand-over in its own queue'),
  ('handoff.mail.unanswered.waiting', 'customer_support', true, 'none', 'the one seat that sends and holds mail.unanswered; nobody else: the CEO sees it only past its clock'),
  ('handoff.mail.unanswered.done', 'customer_support', true, 'none', 'the one seat that sends mail.unanswered; nobody else: it is done when the answer went (email_triage) or the CEO closed it'),
  ('handoff.mail.unanswered.failed', 'customer_support', true, 'digest', 'the one seat that sends mail.unanswered; a failed hand-over is the sender''s to re-send'),
  ('handoff.mail.unanswered.failed', 'it_engineer', false, 'digest', 'a failed hand-over is a fault IT watches')
on conflict (agent_key, event_type) do update
   set owns = excluded.owns, delivery = excluded.delivery, reason = excluded.reason
 where s.edited_by is null;
select set_config('qd.pool_seed', '', true);

-- ── THE DRIVE: an e-mail past its SLA is mail.unanswered, not review.requested ─────────────────────────────────────
create or replace function public.fn_customer_support_unanswered_inbound_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_cut timestamptz := now() - make_interval(hours => greatest(1, public.fn_seat_clock_policy('support_unanswered_drive_hours', 2)::int));
  v_sla int := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24)::int;
  v_founder text[]; m record; w record; d record; v_t jsonb; v_ref text; v_h bigint; v_st jsonb; v_state text; v_why text;
  v_known text; v_from text;
  n_email int := 0; n_wa int := 0; n_answered int := 0; n_noid int := 0; n_closed int := 0; n_cases_closed int := 0;
  n_reread int := 0; n_sales int := 0; n_escalated int := 0;
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- 1. every row still open: answered since, closed with its reason, or (past the SLA) the CEO's
  for d in select i.* from public.customer_support_inbound_drive i
            where i.answered_at is null and i.closed_at is null and i.fixture = v_fx order by i.acted_at limit 200 loop
    v_state := null; v_why := null;
    if d.channel = 'email' then
      v_st := public.fn_inbound_email_reply_owed(d.message_id); v_state := v_st->>'state'; v_why := v_st->>'reason';
    else
      select case when x.id is null then 'gone'
                  when x.reply is not null and coalesce(x.sent, false) then 'answered'
                  when public.fn_is_demo_phone(x.wa_from) then 'fixture'
                  when coalesce(btrim(x.meta->>'no_autoreply_reason'), '') <> '' then 'recorded'
                  else 'owed' end,
             left(x.meta->>'no_autoreply_reason', 300)
        into v_state, v_why from (select 1) one left join public.wa_messages x on x.id = d.message_id;
      -- 'recorded': wa_inbound kept it with no reply of its own and said why (a burst answered by its first message, a thank-you,
      -- a stopped machine loop, an unverified webhook: wa_inbound/burst.ts, arrival.ts)
      v_why := case v_state when 'gone' then 'the WhatsApp message is no longer on file'
                            when 'fixture' then 'a reserved fixture number (+97150000000xx): test traffic, never sent to a person'
                            when 'recorded' then 'wa_inbound recorded it with no reply of its own: ' || v_why end;
      if v_state in ('gone', 'fixture', 'recorded') then v_state := 'no_reply_needed'; end if;
    end if;
    if v_state = 'answered' then
      update public.customer_support_inbound_drive set answered_at = now() where channel = d.channel and message_id = d.message_id;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = d.handoff_id and a.status not in ('done', 'failed')) then
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('answered', true, 'channel', d.channel, 'message_id', d.message_id));
      end if;
      n_answered := n_answered + 1;
    elsif v_state = 'no_reply_needed' then
      update public.customer_support_inbound_drive
         set closed_at = now(), no_reply_reason = v_why, outcome = left('no reply needed: ' || v_why, 500)
       where channel = d.channel and message_id = d.message_id;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = d.handoff_id and a.status not in ('done', 'failed')) then
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('no_reply_needed', true, 'reason', v_why, 'channel', d.channel, 'message_id', d.message_id));
      end if;
      if d.case_ref is not null and public.fn_customer_support_close_case_nothing_owed(d.case_ref) then n_cases_closed := n_cases_closed + 1; end if;
      n_closed := n_closed + 1;
    elsif d.channel = 'email' and v_state = 'decide' and d.reread_requested_at is null then
      -- read 'unclear': a SECOND READING by the model, told who the sender is (supplier_mailbox_reading.ts SECOND_READING)
      update public.inbound_messages
         set triaged_at = null, ai_category = null, owner_role = null, needs_review = true,
             raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('second_reading_requested_at', now())
       where id = d.message_id and replied_at is null;
      update public.customer_support_inbound_drive set reread_requested_at = now(),
             outcome = 'read unclear: a second reading by the model was asked (it decides an answer or no answer, with its reason)'
       where channel = d.channel and message_id = d.message_id;
      n_reread := n_reread + 1;
    elsif v_state in ('owed', 'decide') and d.escalated_at is null
          and (select coalesce(x.created_at, d.acted_at) from (select 1) one
                 left join public.inbound_messages x on d.channel = 'email' and x.id = d.message_id) < now() - make_interval(hours => v_sla) then
      -- still owed past the seat's SLA: the CEO seat decides the answer (never silent, never for a fixture)
      if not v_fx and d.channel = 'email' then
        -- AN UNANSWERED E-MAIL IS HANDED OVER AS A MAIL, NOT A REVIEW (customer_support, 23 Nov 2026; inbound 2169, handoff 393159
        -- dismissed by the CEO for want of "the decision to review"). mail.unanswered to its owning seat with the mail's facts and
        -- due_at now: it is already past the SLA, so the next overdue pass puts it to the CEO with owner customer_support, whose
        -- choices are chase (order customer_support to answer) or close with the reason (email_triage/unanswered_mail.ts).
        select x.* into m from public.inbound_messages x where x.id = d.message_id;
        v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'mail.unanswered', 'inbound_messages', d.message_id::text,
          jsonb_build_object('inbound_message_id', d.message_id, 'from_email', m.from_email, 'to_email', m.to_email,
            'subject', left(coalesce(m.subject, ''), 200), 'owner_seat', 'customer_support', 'received_at', m.created_at,
            'waited_hours', round(extract(epoch from now() - coalesce(m.created_at, d.acted_at)) / 3600.0, 1),
            'error', left('no reply and no reasoned close within ' || v_sla || ' h (' || v_state || ': ' || coalesce(v_why, '') || ')', 300),
            'draft', nullif(left(coalesce(m.ai_draft_reply, ''), 1500), ''), 'body_untrusted', left(coalesce(m.body, ''), 1500),
            'case_ref', d.case_ref, 'due_at', now(),
            'what', 'Answer or close, with the reason, the e-mail inbound_messages #' || d.message_id || ' from ' || coalesce(m.from_email, 'an unknown sender')
              || ' to ' || coalesce(m.to_email, '?') || ' ("' || left(coalesce(m.subject, ''), 200) || '"), received ' || coalesce(m.created_at::text, '?')
              || ', unanswered for ' || round(extract(epoch from now() - coalesce(m.created_at, d.acted_at)) / 3600.0, 1) || ' h. Owner: customer_support. Why no answer went: '
              || left(coalesce(v_why, v_state), 200) || '.' || case when coalesce(m.ai_draft_reply, '') <> '' then ' A draft exists (in `draft`), never sent.' else ' No draft exists.' end,
            'ask', 'The sender has heard nothing. Have the answer written and sent in the thread, or close it with the reason they are owed nothing.'));
        update public.customer_support_inbound_drive set escalated_at = now(), escalation_handoff_id = v_h
         where channel = d.channel and message_id = d.message_id;
        n_escalated := n_escalated + 1;
      elsif not v_fx then
        v_h := public.fn_seat_handoff('customer_support', 'ceo', 'review.requested', 'inbound_messages', d.message_id::text,
          jsonb_build_object('inbound_message_id', d.message_id, 'channel', d.channel, 'case_ref', d.case_ref, 'state', v_state, 'why', v_why,
            'ask', 'This message has had no reply and no reasoned close within ' || v_sla || ' h. Decide the answer and have it sent in the thread, or close it with the reason.'));
        update public.customer_support_inbound_drive set escalated_at = now(), escalation_handoff_id = v_h
         where channel = d.channel and message_id = d.message_id;
        n_escalated := n_escalated + 1;
      end if;
    end if;
  end loop;

  -- 2. email still unanswered past the drive threshold: closed with its reason, the sales engineer's, or a case
  for m in select x.* from public.inbound_messages x
            where x.replied_at is null and x.created_at < v_cut and x.created_at > now() - interval '30 days'
              and public.fn_support_email_is_a_customer_contact(x.from_email, x.to_email, x.owner_role, x.subject, v_fx)
              and not exists (select 1 from public.customer_support_inbound_drive i where i.channel = 'email' and i.message_id = x.id)
            order by x.id limit 50 loop
    v_st := public.fn_inbound_email_reply_owed(m.id); v_state := v_st->>'state'; v_why := v_st->>'reason';
    if v_state = 'answered' then continue; end if;
    if v_state = 'no_reply_needed' then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, no_reply_reason, closed_at, fixture)
      values ('email', m.id, left('no reply needed: ' || v_why, 500), v_why, now(), v_fx);
      n_closed := n_closed + 1; continue;
    end if;
    if v_state = 'with_sales_engineer' then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture)
      values ('email', m.id, left('owed: ' || v_why, 500), v_fx);
      n_sales := n_sales + 1; continue;
    end if;
    v_t := public.fn_support_touch('email', 'in', 'unknown', null, m.from_email, null,
                                   coalesce(m.subject, '') || ' ' || left(coalesce(m.body, ''), 1000));
    v_ref := v_t->>'case_ref';
    if v_ref is null then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture) values ('email', m.id, 'no identity: ' || coalesce(v_t->>'reason', '?'), v_fx);
      n_noid := n_noid + 1; continue;
    end if;
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_ref,
      jsonb_build_object('case_ref', v_ref, 'channel', 'email', 'message_id', m.id,
                         'waiting_for', 'an answer to email #' || m.id || ' (case ' || v_ref || '), owed within ' || v_sla || ' h of ' || m.created_at));
    insert into public.customer_support_inbound_drive (channel, message_id, case_ref, acknowledged, handoff_id, outcome, fixture)
    values ('email', m.id, v_ref, false, v_h, left('case opened (' || v_state || ': ' || v_why || '); the reply is the model''s (ruling 1339)', 500), v_fx);
    n_email := n_email + 1;
  end loop;

  -- 3. WhatsApp still unanswered past the drive threshold (a reserved fixture number is a fixture, whatever its profile name)
  for w in select x.* from public.wa_messages x
            where x.created_at < v_cut and x.created_at > now() - interval '30 days'
              and coalesce(btrim(x.inbound), '') <> '' and (x.reply is null or not coalesce(x.sent, false))
              and coalesce(btrim(x.meta->>'no_autoreply_reason'), '') = ''
              and not (right(regexp_replace(coalesce(x.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
              and (coalesce(x.profile_name, '') like 'ZZ DEMO%' or public.fn_is_demo_phone(x.wa_from)) = v_fx
              and not exists (select 1 from public.customer_support_inbound_drive i where i.channel = 'whatsapp' and i.message_id = x.id)
            order by x.id limit 50 loop
    v_t := public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, w.wa_from, w.inbound);
    v_ref := v_t->>'case_ref';
    if v_ref is null then
      insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture) values ('whatsapp', w.id, 'no identity: ' || coalesce(v_t->>'reason', '?'), v_fx);
      n_noid := n_noid + 1; continue;
    end if;
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_ref,
      jsonb_build_object('case_ref', v_ref, 'channel', 'whatsapp', 'message_id', w.id,
                         'waiting_for', 'an answer to WhatsApp #' || w.id || ' (case ' || v_ref || '), owed within ' || v_sla || ' h of ' || w.created_at));
    insert into public.customer_support_inbound_drive (channel, message_id, case_ref, handoff_id, outcome, fixture)
    values ('whatsapp', w.id, v_ref, v_h, 'case opened', v_fx);
    n_wa := n_wa + 1;
  end loop;

  return jsonb_build_object('ok', true, 'fixture', v_fx, 'email_driven', n_email, 'whatsapp_driven', n_wa,
                            'answered_since', n_answered, 'closed_no_reply_needed', n_closed, 'cases_closed', n_cases_closed,
                            'second_readings_asked', n_reread, 'with_sales_engineer', n_sales, 'escalated_to_ceo', n_escalated,
                            'no_identity', n_noid);
end $fn$;
revoke execute on function public.fn_customer_support_unanswered_inbound_tick() from public, anon, authenticated;

select jsonb_build_object('kind', (select to_jsonb(k) - 'meaning' from public.seat_handoff_kind k where k.type = 'mail.unanswered')) as registered;
