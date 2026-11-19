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
-- NOT CHANGED: review.requested and its handler, the CEO's routines, fn_seat_handoff. The support drive's own SLA escalation
-- (fn_customer_support_unanswered_inbound_tick, review.requested to the CEO) is a separate routine and is not changed here.
-- prevented by: an_unanswered_mail_is_handed_to_its_seat_with_its_facts_probe.sql (LOCAL), email_triage/unanswered_mail.test.ts
-- APPLY: node scripts/apply_sql.mjs scripts/sql/an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql --apply --ddl
--   BEFORE deploying email_triage from the same PR (before it, fn_seat_handoff files the new kind as 'failed', unregistered).
-- ROLLBACK: delete from public.seat_handoff_kind where type = 'mail.unanswered'; delete from public.event_subscription where
--   event_type like 'handoff.mail.unanswered.%'; drop function
--   public.fn_customer_support_holds_an_unanswered_mail(bigint); and redeploy email_triage from main.
-- LOCKS: one seat_handoff_kind row, five event_subscription seed rows and one new routine.
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

select jsonb_build_object('kind', (select to_jsonb(k) - 'meaning' from public.seat_handoff_kind k where k.type = 'mail.unanswered')) as registered;
