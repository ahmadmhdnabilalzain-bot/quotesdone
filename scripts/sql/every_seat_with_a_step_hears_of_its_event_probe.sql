-- PROBE for every_seat_with_a_step_hears_of_its_event.sql. Seat: ceo. Agent: workflow-wiring. 19 Nov 2026.
-- A pure probe, never applied: it ALWAYS ends by raising CHK<<PROBE OK>> or CHK<<PROBE FAILED: ...>>, so every row it writes
-- is rolled back. Its people are ZZ DEMO with @example.invalid addresses, and every id it names is its own; nothing is sent
-- (four notifications it writes are never queued for a channel and die with the rollback).
-- Run LOCALLY (node scripts/db/local_pg16.mjs start; docs/runbooks/local-database.md), never on production: it writes
-- notifications and rebuilds the seats' digests, and on production that would hold the outbox (review of #2074, 19 Nov 2026).
-- It proves, for each event: emitted once (a repeat, a changed code and a flip back emit nothing more), routed by digest to
-- exactly the seats named (H), classed as rehearsal traffic and counted in those seats' day by the real digest builder (I);
-- a canary, a soft bounce, a 4.x.x bounce and a WhatsApp row emit nothing (E); the paid reveal reaches the ceo and
-- customer_support through payment.received (A); the new routines are closed to callers and pin search_path (J).
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  v_fail text := '';
  v_verdict text;
  v_cust uuid; v_lead bigint; v_inq uuid; v_tx uuid; v_rev bigint;
  v_n1 bigint; v_n2 bigint; v_n3 bigint; v_n4 bigint; v_n5 bigint; v_n6 bigint;
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
    insert into public.notifications (type, to_email, to_role, subject, body, status, channel, lang, sent_at) values
      ('quote_received', 'every-seat-4xx-' || v_tag || '@example.invalid', 'customer', 'ZZ DEMO 4xx ' || v_tag, 'ZZ DEMO body', 'sent', 'email', 'en', now())
      returning id into v_n6;
    update public.notifications set provider_status = 'undelivered', provider_error_code = 'bounce:4.4.7' where id = v_n6;
    update public.notifications set provider_status = 'undelivered', provider_error_code = 'bounce:permanent' where id = v_n4;
    update public.notifications set provider_status = 'undelivered', provider_error_code = '63016' where id = v_n5;
    select count(*) into v_n from public.company_event where event_type in ('mail.bounced', 'mail.complained') and entity_id in (v_n3::text, v_n4::text, v_n5::text, v_n6::text);
    if v_n <> 0 then v_fail := v_fail || 'E: a soft or 4.x.x bounce, canary or WhatsApp row emitted ' || v_n || '; '; end if;

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
  raise exception 'CHK<<%>>', case when v_verdict = 'OK' then 'PROBE OK' else 'PROBE FAILED: ' || v_verdict end;
end $probe$;

