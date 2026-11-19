-- EVERY SEAT WITH A STEP HEARS OF ITS EVENT. Seat: ceo. Assigned: ceo. Agent: workflow-wiring. 19 Nov 2026.
-- Founder ruling 1685: "all the agents who are relevant and have a step ... know it" (a paid reveal: the accountant, the
-- books, the CEO, the sales engineer, the refund timer).
--
-- MEASURED (production SELECTs and catalog reads, 19 Nov 2026):
--   * A PAID REVEAL IS ALREADY HEARD. reveal_sale.ts inserts the transactions row with fee_status 'paid', and
--     trg_event_transaction (fn_emit_event('transaction', 'payment.received')) emits payment.received once per sale
--     (transactions.quote_id is unique). event_subscription already routes payment.received AND handoff.reveal.paid.sent
--     to the ceo and customer_support by digest (4 + 4 rows, written 16 Nov 2026), and fn_seat_pool_digest_build counts
--     both and names payment.received among the notable lines with its amount. The refund timer is trg_reveal_window
--     (refund_deadline) and z25_reveal_opens_response_watch (supplier_response_watch). So this file emits NO third event for
--     a paid reveal (it would print the same sale twice more in the CEO's day); its probe proves the existing route instead.
--   * A BOUNCE OR A COMPLAINT WAS HEARD BY NOBODY. It is recorded on public.notifications: resend_webhook writes
--     provider_status 'undelivered' + provider_error_code 'bounce:<type>' (or 'complained' on a delivered row), and
--     fn_mail_bounce_marks_its_send writes 'undelivered' + 'bounce:<RFC 3463 code | gmail:Reason>' for an M365 NDR. 74 rows
--     are undelivered: 58 delivery_feedback_canary (to_role 'system', built to bounce) and 16 supplier_invite (latest
--     18 Nov 10:00). No company_event type existed for either, and customer.complaint (emitted by t_emit_customer_complaint
--     on feedback and trg_emit_customer_complaint_review on reviews rated 2 or below) had 0 rows and 0 subscriptions.
--   * AN INVITATION SENT, A REQUEST COMPLETED AND A RATING LANDED EMITTED NOTHING. z81 counts a sent invitation for the
--     schedule only; a hire writes inquiries.status 'completed' (hire.ts, fn_customer_followup_answer) and no event; a
--     rating opens the sales engineer's task (t60_sales_rating_landed) and nothing else. Marketing and the CEO heard none.
--
-- WHAT THIS DOES (nobody is sent anything: every new event is delivered by 'digest', which only builds a seat's day):
--   1. fn_emit_once(key, ...): fn_emit, once per key (company_event.dedupe_key, unique), under an advisory lock on the key.
--   2. z83 on notifications: an invitation that left -> invite.sent; a hard bounce of an e-mail to a person -> mail.bounced;
--      a spam complaint -> mail.complained. Canaries (to_role 'system', type delivery_feedback_canary) and soft or transient
--      bounces are not events. Once per notification.
--   3. z34 on inquiries: status becomes 'completed' -> request.completed, once per request.
--   4. t61 on reviews: a rating is inserted -> rating.landed, once per review.
--   5. event_subscription: one row per seat for each new type (and for customer.complaint), each with its reason; one owner.
--        mail.bounced / mail.complained: it_engineer (owner), ceo, marketing by digest.
--        invite.sent:                    marketing (owner), ceo by digest.
--        request.completed:              sales_engineer (owner), ceo, marketing, customer_support by digest.
--        rating.landed:                  ceo, marketing, customer_support by digest; sales_engineer owns it by his t60 task.
--        customer.complaint:             customer_support (owner), ceo, sales_engineer by digest.
--   6. THE PROBE (section 6): ZZ DEMO rows in a sub-block that always raises, so every row it writes is rolled back; it
--      returns ONE verdict row. A failure is 'PROBE FAILED: ...' (apply_sql exits 3).
-- Prevented by: scripts/checks/every_seat_with_a_step_hears_of_its_event.test.mjs, and this file's probe.
-- APPLY (release session; outside the invitation sending minutes, the triggers take SHARE ROW EXCLUSIVE on notifications,
-- inquiries and reviews for milliseconds):
--   node scripts/apply_sql.mjs scripts/sql/every_seat_with_a_step_hears_of_its_event.sql --apply --ddl --seat ceo
--   then delete scripts/sql/pending/every_seat_with_a_step_hears_of_its_event.txt and append this file as the LAST line of
--   scripts/sql/MANIFEST.txt.
-- ROLLBACK (one transaction): drop trigger z83_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint on notifications,
-- z34_a_completed_request_is_a_company_event on inquiries, t61_a_rating_is_a_company_event on reviews; drop the three trigger
-- functions and fn_emit_once(text,text,text,text,text,jsonb); delete from event_subscription where edited_by =
-- 'every_seat_with_a_step_hears_of_its_event.sql'. Events already emitted stay as history.
set local lock_timeout = '1500ms';
select set_config('qd.edited_by', 'every_seat_with_a_step_hears_of_its_event.sql', true);

-- ── 1. ONCE PER KEY ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- fn_emit is the one emitter (its column defaults carry the correlation chain); it has no dedupe parameter, so the key is
-- written onto the row it returns. The advisory lock makes a racing second writer wait and then see the first one's row.
create or replace function public.fn_emit_once(p_dedupe_key text, p_event_type text, p_entity_type text, p_entity_id text,
                                               p_actor text default 'system', p_payload jsonb default '{}'::jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  if nullif(btrim(coalesce(p_dedupe_key, '')), '') is null then
    raise exception 'fn_emit_once: an event emitted once needs its key (%)', p_event_type;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('company_event.dedupe_key:' || p_dedupe_key, 0));
  if exists (select 1 from public.company_event e where e.dedupe_key = p_dedupe_key) then return null; end if;
  v_id := public.fn_emit(p_event_type, p_entity_type, p_entity_id, p_actor, p_payload);
  update public.company_event set dedupe_key = p_dedupe_key where id = v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_emit_once(text, text, text, text, text, jsonb) from public, anon, authenticated;
comment on function public.fn_emit_once(text, text, text, text, text, jsonb) is
  'ceo: fn_emit once per dedupe key (company_event.dedupe_key). Returns the new event id, or null when the key was already emitted. every_seat_with_a_step_hears_of_its_event.sql, 19 Nov 2026.';

-- ── 2. AN INVITATION LEFT, A MAIL BOUNCED, A READER COMPLAINED (notifications) ────────────────────────────────────────────
-- Never in the sender's way: a failure to emit is an IT finding, and the send, the bounce or the complaint is recorded as it was.
create or replace function public.fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_type text;
begin
  begin
    if new.type = 'supplier_invite' and new.sent_at is not null and old.sent_at is null then
      perform public.fn_emit_once('invite.sent:notification:' || new.id, 'invite.sent',
        case when new.lead_id is not null then 'lead' else 'notification' end, coalesce(new.lead_id::text, new.id::text), 'marketing',
        jsonb_build_object('notification_id', new.id, 'lead_id', new.lead_id, 'email', lower(btrim(coalesce(new.to_email, ''))),
                           'lane', coalesce(new.kind, new.sender), 'lang', new.lang, 'sent_at', new.sent_at));
    end if;

    -- an e-mail to a person (a canary is built to bounce); a soft or transient bounce may still arrive
    if coalesce(new.channel, 'email') = 'email' and coalesce(new.to_role, '') <> 'system'
       and coalesce(new.type, '') <> 'delivery_feedback_canary'
       and (new.provider_status is distinct from old.provider_status or new.provider_error_code is distinct from old.provider_error_code) then
      if new.provider_status = 'undelivered' and coalesce(new.provider_error_code, '') like 'bounce:%'
         and new.provider_error_code !~* '^bounce:(transient|soft)' then
        v_type := 'mail.bounced';
      elsif new.provider_error_code = 'complained' then
        v_type := 'mail.complained';
      end if;
      if v_type is not null then
        perform public.fn_emit_once(v_type || ':notification:' || new.id, v_type, 'notification', new.id::text, 'system',
          jsonb_build_object('notification_id', new.id, 'type', new.type, 'kind', new.kind, 'to_role', new.to_role,
                             'lead_id', new.lead_id, 'inquiry_id', new.inquiry_id, 'quote_id', new.quote_id,
                             'email', lower(btrim(coalesce(new.to_email, ''))), 'code', new.provider_error_code,
                             'at', coalesce(new.provider_status_at, now()), 'sender', new.sender));
      end if;
    end if;
  exception when others then
    begin
      perform public.fn_it_engineer_finding_upsert(
        'monitor:notification_event_not_emitted:' || new.id,
        'A send, bounce or complaint on notification ' || new.id || ' was recorded but its company_event was not: ' || left(sqlerrm, 200),
        'public.fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint (caller: ceo)', 'agent_facing', 1,
        jsonb_build_object('notification_id', new.id, 'error', left(sqlerrm, 500), 'owner_seat', 'ceo'),
        '{}'::text[], array['why fn_emit_once refused this notification''s event'], 'fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint');
    exception when others then null;
    end;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint() from public, anon, authenticated;

create or replace trigger z83_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint
  after update of sent_at, provider_status, provider_error_code on public.notifications
  for each row
  when ((new.type = 'supplier_invite' and new.sent_at is not null and old.sent_at is null)
        or ((new.provider_status = 'undelivered' or new.provider_error_code = 'complained')
            and (new.provider_status is distinct from old.provider_status or new.provider_error_code is distinct from old.provider_error_code)))
  execute function public.fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint();

-- ── 3. A REQUEST WAS COMPLETED (inquiries) ───────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_inquiries_a_completed_request_is_a_company_event()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  begin
    perform public.fn_emit_once('request.completed:inquiry:' || new.id, 'request.completed', 'inquiry', new.id::text, 'system',
      jsonb_build_object('inquiry_id', new.id, 'customer_id', new.customer_id, 'outcome', new.outcome,
                         'supplier_id', new.hired_supplier_id, 'hired_supplier_id', new.hired_supplier_id,
                         'completed_at', coalesce(new.completed_at, now())));
  exception when others then
    begin
      perform public.fn_it_engineer_finding_upsert(
        'monitor:request_completed_not_emitted:' || new.id,
        'Request ' || new.id || ' was completed but request.completed was not emitted: ' || left(sqlerrm, 200),
        'public.fn_inquiries_a_completed_request_is_a_company_event (caller: ceo)', 'agent_facing', 1,
        jsonb_build_object('inquiry_id', new.id, 'error', left(sqlerrm, 500), 'owner_seat', 'ceo'),
        '{}'::text[], array['why fn_emit_once refused this request''s event'], 'fn_inquiries_a_completed_request_is_a_company_event');
    exception when others then null;
    end;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_inquiries_a_completed_request_is_a_company_event() from public, anon, authenticated;

create or replace trigger z34_a_completed_request_is_a_company_event
  after update of status on public.inquiries
  for each row when (new.status = 'completed' and old.status is distinct from 'completed')
  execute function public.fn_inquiries_a_completed_request_is_a_company_event();

-- ── 4. A RATING LANDED (reviews) ─────────────────────────────────────────────────────────────────────────────────────────
-- A changed rating updates the sales engineer's t60 task; it is not a new event (once per review).
create or replace function public.fn_reviews_a_rating_is_a_company_event()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  begin
    perform public.fn_emit_once('rating.landed:review:' || new.id, 'rating.landed', 'review', new.id::text, 'customer',
      jsonb_build_object('review_id', new.id, 'rating', new.rating, 'supplier_id', new.supplier_id, 'customer_id', new.customer_id,
                         'inquiry_id', new.inquiry_id, 'transaction_id', new.transaction_id,
                         'has_comment', nullif(btrim(coalesce(new.comment, '')), '') is not null));
  exception when others then
    begin
      perform public.fn_it_engineer_finding_upsert(
        'monitor:rating_landed_not_emitted:' || new.id,
        'Rating ' || new.id || ' landed but rating.landed was not emitted: ' || left(sqlerrm, 200),
        'public.fn_reviews_a_rating_is_a_company_event (caller: ceo)', 'agent_facing', 1,
        jsonb_build_object('review_id', new.id, 'error', left(sqlerrm, 500), 'owner_seat', 'ceo'),
        '{}'::text[], array['why fn_emit_once refused this rating''s event'], 'fn_reviews_a_rating_is_a_company_event');
    exception when others then null;
    end;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_reviews_a_rating_is_a_company_event() from public, anon, authenticated;

create or replace trigger t61_a_rating_is_a_company_event
  after insert on public.reviews
  for each row execute function public.fn_reviews_a_rating_is_a_company_event();

-- ── 5. WHO HEARS IT (one row per seat, a reason each, one owner; 'digest' builds the seat's day and sends nothing) ─────────
-- ON CONFLICT DO NOTHING: a re-apply keeps a row a seat has since edited, and never takes an owner from another seat.
insert into public.event_subscription (agent_key, event_type, delivery, owns, reason) values
  ('it_engineer',      'mail.bounced', 'digest', true,  'sender health is IT''s (it_sender_health_daily, v_invite_deliverability_daily): a hard bounce is an address we must not write to again and a point on the bounce rate'),
  ('ceo',              'mail.bounced', 'digest', false, 'the CEO''s plan names email deliverability (bounces above 5%) as a constraint; founder 1685: every seat with a step knows'),
  ('marketing',        'mail.bounced', 'digest', false, 'the invitation list is marketing''s: 16 of the 16 bounces to a person up to 19 Nov 2026 were supplier invitations'),
  ('sales_engineer',   'mail.bounced', 'none',   false, 'nobody: a bounce moves no request; IT, the CEO and marketing carry it'),
  ('customer_support', 'mail.bounced', 'none',   false, 'nobody: support answers people who write in, and a bounced address has not'),
  ('accountant',       'mail.bounced', 'none',   false, 'nobody: a bounce moves no money'),

  ('it_engineer',      'mail.complained', 'digest', true,  'a spam complaint is the sender-health signal the warm-up brakes on (complaint rate, it_sender_health_daily)'),
  ('ceo',              'mail.complained', 'digest', false, 'deliverability is a constraint in the CEO''s plan; founder 1685: every seat with a step knows'),
  ('marketing',        'mail.complained', 'digest', false, 'a complaint is about what we sent and to whom: the copy and the list are marketing''s'),
  ('sales_engineer',   'mail.complained', 'none',   false, 'nobody: a complaint about a mail moves no request'),
  ('customer_support', 'mail.complained', 'none',   false, 'nobody: the address is suppressed (email_suppressions) and is not written to again'),
  ('accountant',       'mail.complained', 'none',   false, 'nobody: a complaint about a mail moves no money'),

  ('marketing',        'invite.sent', 'digest', true,  'the supplier invitation campaign is marketing''s (marketing.whatsapp_supplier_invites, marketing.invite_copy_readout)'),
  ('ceo',              'invite.sent', 'digest', false, 'invitations sent is a daily number (ceo.invite_brake_review judges the brake on them)'),
  ('sales_engineer',   'invite.sent', 'none',   false, 'nobody: the sales engineer verifies a supplier when it applies (supplier.applied), not when it is invited'),
  ('customer_support', 'invite.sent', 'none',   false, 'nobody: an invited supplier who writes in reaches support as his own message'),
  ('it_engineer',      'invite.sent', 'none',   false, 'nobody: a send fault reaches IT as a finding and a bounce as mail.bounced'),
  ('accountant',       'invite.sent', 'none',   false, 'nobody: an invitation moves no money'),

  ('sales_engineer',   'request.completed', 'digest', true,  'the sales engineer closes the request: a hire writes status completed and outcome hired, and he tells the suppliers not chosen'),
  ('ceo',              'request.completed', 'digest', false, 'a hire is the company''s outcome: a daily number; founder 1685'),
  ('marketing',        'request.completed', 'digest', false, 'a completed request is the result the marketing funnel is measured to'),
  ('customer_support', 'request.completed', 'digest', false, 'the customer and the hired supplier may write in next'),
  ('accountant',       'request.completed', 'none',   false, 'nobody: the reveal fee was booked when it was paid; a hire moves no money'),
  ('it_engineer',      'request.completed', 'none',   false, 'nobody: a completed request is not a surface fault'),

  ('sales_engineer',   'rating.landed', 'none',   true,  'the sales engineer holds every rating as his t60_sales_rating_landed task (the task itself, not this echo)'),
  ('ceo',              'rating.landed', 'digest', false, 'supplier quality as customers rate it is a daily number; founder 1685'),
  ('marketing',        'rating.landed', 'digest', false, 'ratings are what marketing shows and asks customers to make public'),
  ('customer_support', 'rating.landed', 'digest', false, 'a rating of 2 or below is also a customer.complaint; support answers the customer who rated'),
  ('accountant',       'rating.landed', 'none',   false, 'nobody: a rating moves no money (a refund request is its own event)'),
  ('it_engineer',      'rating.landed', 'none',   false, 'nobody: a rating is not a surface fault'),

  ('customer_support', 'customer.complaint', 'digest', true,  'complaints are customer support''s (complaint_tickets and the complaint clock); 0 subscribers until 19 Nov 2026'),
  ('ceo',              'customer.complaint', 'digest', false, 'a complaint is a daily number; founder 1685: every seat with a step knows'),
  ('sales_engineer',   'customer.complaint', 'digest', false, 'a complaint about a supplier bears on his standing, which the sales engineer judges'),
  ('marketing',        'customer.complaint', 'none',   false, 'nobody: marketing hears the rating itself (rating.landed)'),
  ('accountant',       'customer.complaint', 'none',   false, 'nobody: a complaint moves no money until a refund is requested'),
  ('it_engineer',      'customer.complaint', 'none',   false, 'nobody: a complaint about service is not a surface fault')
on conflict do nothing;

-- ── 6. THE PROBE: one verdict row ─────────────────────────────────────────────────────────────────────────────────────────
-- The sub-block ALWAYS raises CHK<<...>> at its end, so every ZZ DEMO row it writes (people @example.invalid, a request, a
-- sale in test mode, four notifications that are never queued for a channel, a review) is rolled back with it, and the
-- definitions above stay. It proves, for each event: emitted once (a repeat, a changed code and a flip back emit nothing more),
-- routed by digest to exactly the seats named in section 5, classed as rehearsal traffic and counted in those seats' day by
-- the real digest builder; a canary, a soft bounce and a WhatsApp row emit nothing; the paid reveal reaches the ceo and
-- customer_support through payment.received. On production only at release (it rebuilds the seats' digests inside the
-- rolled-back block, which holds seat_pool_digest for about a second).
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  v_fail text := '';
  v_verdict text;
  v_cust uuid; v_lead bigint; v_inq uuid; v_tx uuid; v_rev bigint;
  v_n1 bigint; v_n2 bigint; v_n3 bigint; v_n4 bigint; v_n5 bigint;
  v_n int; v_rows int; v_s text; v_owner text; r record; v_d jsonb;
  v_body text := 'ZZ DEMO invitation from the every-seat probe. Reply "stop" and we will not write again.';
begin
  begin
    insert into public.customers (full_name, email) values ('ZZ DEMO Every Seat Probe Customer', 'every-seat-' || v_tag || '@example.invalid')
      returning id into v_cust;
    insert into public.leads (company_name, email) values ('ZZ DEMO Every Seat Probe Supplier', 'every-seat-s-' || v_tag || '@example.invalid')
      returning id into v_lead;
    insert into public.inquiries (customer_id, category, emirate, summary, status)
      values (v_cust, 'painting', 'Dubai', 'ZZ DEMO every-seat probe', 'revealed') returning id into v_inq;

    -- A. a paid reveal: one payment.received, heard by the ceo and customer_support (existing route, no new event)
    insert into public.transactions (inquiry_id, customer_id, supplier_id, quote_amount, reveal_fee, fee_status, livemode, paid_at)
      values (v_inq, v_cust, v_lead, 4500, 135.00, 'paid', false, now()) returning id into v_tx;
    select count(*) into v_n from public.company_event where event_type = 'payment.received' and entity_id = v_tx::text;
    if v_n <> 1 then v_fail := v_fail || 'A: payment.received x' || v_n || '; '; end if;
    select string_agg(agent_key, ',' order by agent_key) into v_s from public.event_subscription
     where event_type = 'payment.received' and active and delivery = 'digest' and agent_key in ('ceo', 'customer_support');
    if v_s is distinct from 'ceo,customer_support' then v_fail := v_fail || 'A: payment.received reaches ' || coalesce(v_s, 'nobody') || ' of ceo,customer_support; '; end if;

    -- B. an invitation that left: once, however often sent_at is written
    insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, channel, lang)
      values ('supplier_invite', 'every-seat-s-' || v_tag || '@example.invalid', 'supplier', v_lead, 'ZZ DEMO probe invite ' || v_tag, v_body, 'queued', 'email', 'en')
      returning id into v_n1;
    update public.notifications set sent_at = now() where id = v_n1;
    update public.notifications set sent_at = now() + interval '1 second' where id = v_n1;     -- already sent: no event
    update public.notifications set sent_at = null where id = v_n1;
    update public.notifications set sent_at = now() where id = v_n1;                           -- sent again: still once
    select count(*) into v_n from public.company_event where event_type = 'invite.sent' and payload->>'notification_id' = v_n1::text;
    if v_n <> 1 then v_fail := v_fail || 'B: invite.sent x' || v_n || '; '; end if;

    -- C. a hard bounce of that invitation: once, whatever code arrives after the first
    update public.notifications set provider_status = 'undelivered', provider_error_code = 'bounce:5.1.1', provider_status_at = now() where id = v_n1;
    update public.notifications set provider_error_code = 'bounce:permanent' where id = v_n1;
    update public.notifications set provider_status = 'undelivered' where id = v_n1;           -- no change: the trigger does not fire
    select count(*) into v_n from public.company_event where event_type = 'mail.bounced' and entity_id = v_n1::text;
    if v_n <> 1 then v_fail := v_fail || 'C: mail.bounced x' || v_n || '; '; end if;

    -- D. a spam complaint on a mail to a customer: once
    insert into public.notifications (type, to_email, to_role, inquiry_id, subject, body, status, channel, lang, sent_at)
      values ('quote_received', 'every-seat-' || v_tag || '@example.invalid', 'customer', v_inq, 'ZZ DEMO probe mail ' || v_tag, 'ZZ DEMO body', 'sent', 'email', 'en', now())
      returning id into v_n2;
    update public.notifications set provider_status = 'delivered', provider_status_at = now() where id = v_n2;
    update public.notifications set provider_error_code = 'complained' where id = v_n2;
    update public.notifications set provider_error_code = 'complained', provider_status_checked_at = now() where id = v_n2;
    select count(*) into v_n from public.company_event where event_type = 'mail.complained' and entity_id = v_n2::text;
    if v_n <> 1 then v_fail := v_fail || 'D: mail.complained x' || v_n || '; '; end if;

    -- E. not events: a soft bounce, a canary built to bounce, a WhatsApp message not delivered
    insert into public.notifications (type, to_email, to_role, subject, body, status, channel, lang, sent_at) values
      ('quote_received', 'every-seat-soft-' || v_tag || '@example.invalid', 'customer', 'ZZ DEMO soft ' || v_tag, 'ZZ DEMO body', 'sent', 'email', 'en', now())
      returning id into v_n3;
    insert into public.notifications (type, to_email, to_role, subject, body, status, channel, lang, sent_at) values
      ('delivery_feedback_canary', 'every-seat-canary-' || v_tag || '@example.invalid', 'system', 'ZZ DEMO canary ' || v_tag, 'ZZ DEMO body', 'sent', 'email', 'en', now())
      returning id into v_n4;
    insert into public.notifications (type, to_phone, to_role, subject, body, status, channel, lang, sent_at) values
      ('quote_received', '+971500000000', 'customer', 'ZZ DEMO wa ' || v_tag, 'ZZ DEMO body', 'sent', 'whatsapp', 'en', now())
      returning id into v_n5;
    update public.notifications set provider_status = 'undelivered', provider_error_code = 'bounce:transient' where id = v_n3;
    update public.notifications set provider_status = 'undelivered', provider_error_code = 'bounce:permanent' where id = v_n4;
    update public.notifications set provider_status = 'undelivered', provider_error_code = '63016' where id = v_n5;
    select count(*) into v_n from public.company_event where event_type in ('mail.bounced', 'mail.complained') and entity_id in (v_n3::text, v_n4::text, v_n5::text);
    if v_n <> 0 then v_fail := v_fail || 'E: a soft bounce, canary or WhatsApp row emitted ' || v_n || '; '; end if;

    -- F. a request completed: once, even if it is completed again after a step back
    update public.inquiries set status = 'completed', outcome = 'hired', hired_supplier_id = v_lead, completed_at = now() where id = v_inq;
    update public.inquiries set status = 'revealed' where id = v_inq;
    update public.inquiries set status = 'completed' where id = v_inq;
    select count(*) into v_n from public.company_event where event_type = 'request.completed' and entity_id = v_inq::text;
    if v_n <> 1 then v_fail := v_fail || 'F: request.completed x' || v_n || '; '; end if;

    -- G. a rating landed (2/5, so also the existing customer.complaint): once each, a changed rating adds none
    insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
      values (v_lead, v_cust, v_inq, v_tx, 2, 'ZZ DEMO every-seat probe rating') returning id into v_rev;
    update public.reviews set rating = 1 where id = v_rev;
    select count(*) into v_n from public.company_event where event_type = 'rating.landed' and entity_id = v_rev::text;
    if v_n <> 1 then v_fail := v_fail || 'G: rating.landed x' || v_n || '; '; end if;
    select count(*) into v_n from public.company_event where event_type = 'customer.complaint' and entity_type = 'review' and entity_id = v_rev::text;
    if v_n <> 1 then v_fail := v_fail || 'G: customer.complaint x' || v_n || '; '; end if;

    -- H. routed to exactly the seats named, one owner each, by digest only (nothing is handed over or sent)
    for r in select * from (values
        ('mail.bounced', 'ceo,it_engineer,marketing', 'it_engineer'),
        ('mail.complained', 'ceo,it_engineer,marketing', 'it_engineer'),
        ('invite.sent', 'ceo,marketing', 'marketing'),
        ('request.completed', 'ceo,customer_support,marketing,sales_engineer', 'sales_engineer'),
        ('rating.landed', 'ceo,customer_support,marketing', 'sales_engineer'),
        ('customer.complaint', 'ceo,customer_support,sales_engineer', 'customer_support')) t(ev, seats, owner) loop
      select string_agg(agent_key, ',' order by agent_key) filter (where active and delivery = 'digest'),
             string_agg(agent_key, ',') filter (where owns),
             count(*) filter (where delivery = 'handover'), count(*)
        into v_s, v_owner, v_n, v_rows
        from public.event_subscription where event_type = r.ev;
      if v_s is distinct from r.seats then v_fail := v_fail || 'H: ' || r.ev || ' reaches ' || coalesce(v_s, 'nobody') || ', not ' || r.seats || '; '; end if;
      if v_owner is distinct from r.owner then v_fail := v_fail || 'H: ' || r.ev || ' is owned by ' || coalesce(v_owner, 'nobody') || ', not ' || r.owner || '; '; end if;
      if v_n <> 0 then v_fail := v_fail || 'H: ' || r.ev || ' is handed over to ' || v_n || ' seat(s); '; end if;
      if v_rows <> 6 then v_fail := v_fail || 'H: ' || r.ev || ' has ' || v_rows || ' seat rows, not 6; '; end if;
      if exists (select 1 from public.event_subscription es where es.event_type = r.ev
                  and not exists (select 1 from public.org_role o where o.role_id = es.agent_key and o.status = 'active')) then
        v_fail := v_fail || 'H: ' || r.ev || ' names a seat that is not an active org_role; ';
      end if;
    end loop;

    -- I. the real digest builder classes every probe event as rehearsal traffic and counts it in each named seat's day
    perform public.fn_seat_pool_digest_build(null);
    for r in select e.id, e.event_type from public.company_event e
              where (e.event_type = 'payment.received' and e.entity_id = v_tx::text)
                 or (e.event_type in ('invite.sent') and e.payload->>'notification_id' = v_n1::text)
                 or (e.event_type in ('mail.bounced', 'mail.complained') and e.entity_id in (v_n1::text, v_n2::text))
                 or (e.event_type = 'request.completed' and e.entity_id = v_inq::text)
                 or (e.event_type in ('rating.landed', 'customer.complaint') and e.entity_id = v_rev::text) loop
      if not exists (select 1 from public.pool_event_class c where c.event_id = r.id and c.demo) then
        v_fail := v_fail || 'I: ' || r.event_type || ' was not classed as rehearsal traffic; ';
      end if;
      for v_s in select es.agent_key from public.event_subscription es where es.event_type = r.event_type and es.active and es.delivery = 'digest' loop
        select d.counts into v_d from public.seat_pool_digest d where d.seat = v_s and d.scope = 'demo';
        if coalesce((v_d->'heard'->>r.event_type)::int, 0) < 1 then
          v_fail := v_fail || 'I: ' || v_s || '''s day does not count ' || r.event_type || '; ';
        end if;
      end loop;
    end loop;
    select count(*) into v_n from public.company_event e
     where e.dedupe_key like any (array['invite.sent:notification:' || v_n1, 'mail.bounced:notification:' || v_n1,
                                        'mail.complained:notification:' || v_n2, 'request.completed:inquiry:' || v_inq,
                                        'rating.landed:review:' || v_rev]);
    if v_n <> 5 then v_fail := v_fail || 'I: ' || v_n || ' of the 5 new events carry their dedupe key; '; end if;

    -- J. the new routines are closed to callers and pin their search_path
    for r in select p.oid::regprocedure::text as sig, p.proconfig, p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('fn_emit_once', 'fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint',
                                                           'fn_inquiries_a_completed_request_is_a_company_event', 'fn_reviews_a_rating_is_a_company_event') loop
      if has_function_privilege('anon', r.oid, 'execute') or has_function_privilege('authenticated', r.oid, 'execute') then
        v_fail := v_fail || 'J: ' || r.sig || ' is executable by a caller; ';
      end if;
      if not coalesce(r.proconfig::text ~ 'search_path=public, pg_temp', false) then v_fail := v_fail || 'J: ' || r.sig || ' has no pinned search_path; '; end if;
    end loop;

    raise exception 'CHK<<%>>', case when v_fail = '' then 'OK' else v_fail end;
  exception when others then
    v_verdict := case when sqlerrm like 'CHK<<%>>' then substring(sqlerrm from 'CHK<<(.*)>>') else 'the probe stopped: ' || sqlerrm end;
  end;
  -- nothing it wrote is left
  if exists (select 1 from public.customers where email = 'every-seat-' || v_tag || '@example.invalid')
     or exists (select 1 from public.leads where email = 'every-seat-s-' || v_tag || '@example.invalid')
     or exists (select 1 from public.notifications where subject like 'ZZ DEMO % ' || v_tag) then
    v_verdict := coalesce(nullif(v_verdict, 'OK'), '') || ' a probe row was left behind;';
  end if;
  perform set_config('qd.every_seat_hears_verdict', case when v_verdict = 'OK' then 'PROBE OK' else 'PROBE FAILED: ' || v_verdict end, true);
end $probe$;

select current_setting('qd.every_seat_hears_verdict', true) as verdict;
