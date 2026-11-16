-- PROBE: THE COMPARISON HANDS ITS OPEN POINTS TO THE SALES ENGINEER (sales_engineer, 15 Nov 2026; COMPARE4). A PURE probe:
-- no DDL, never applied; run after the_comparison_hands_its_open_points_to_the_sales_engineer.sql (or concatenated after
-- it) on the LOCAL Postgres 16 built from the mirror (scripts/db/local_pg16.mjs), never on production. It always raises
-- CHK<<...>>, so every row it writes is rolled back. Every party is a ZZ DEMO fixture on @example.invalid, so even a
-- committed row could reach nobody (fn_seat_clock_refusal lets a fixture request write only to a fixture address, and the
-- demo capture suppresses the row). It counts the rows that are not its own before and after.
-- PROBE OK only if
--   1. a hand-over on a quote whose supplier SUBMITTED his conversation records its points open and queues exactly ONE
--      English notice to that supplier (type quote_comparison_points, requested_by sales_engineer, no Arabic, nothing of the
--      customer's: not his name, not his e-mail, not the points' text), keyed by the quote and the point set;
--   2. the same hand-over again, the notice routine again, and the supplier's second option with the same points queue
--      nothing more (one notice per quote per point set, never repeated);
--   3. a conversation that is NOT submitted gets its points and no notice;
--   4. a reveal on the request closes every open point as superseded with its reason, closes the hand-overs with it, and
--      cancels a notice still queued; a hand-over filed after the reveal records nothing and tells nobody;
--   5. a request that ends (expired) closes its open points and hand-over the same way, with that reason;
--   6. no row that is not the probe's changed.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); s1 bigint; s2 bigint;
  i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid();
  q1 uuid := gen_random_uuid(); q1b uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid(); q4 uuid := gen_random_uuid();
  r1 uuid; r2 uuid; r4 uuid; h1 bigint; h1again bigint; h1b bigint; h2 bigint; h3 bigint; h4 bigint; n int; v jsonb; nt record;
  v_points jsonb := jsonb_build_array(
    jsonb_build_object('key', 'comparison:is_the_price_final', 'supplier', 'Is this price final, or subject to the site visit?', 'en', 'Is the price final?', 'ar', 'هل السعر نهائي؟'),
    jsonb_build_object('key', 'comparison:delivery_included', 'supplier', 'Is delivery to site included in the price?', 'en', 'Is delivery included?', 'ar', 'هل التوصيل مشمول؟'));
  v_other_rr bigint := (select count(*) from public.quote_review_request);
  v_other_n bigint := (select count(*) from public.notifications where coalesce(to_email, '') not like 'zz-demo-cmp4-%');
  v_other_h bigint := (select count(*) from public.agent_actions where kind = 'handoff' and status = 'done');
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);   -- this transaction only; it always rolls back
  -- the delivery conversations as production has them (SELECT on seat_handoff_kind, 15 Nov 2026); the mirror holds the table,
  -- not its rows, so the local database lacks them. Rolled back with everything else.
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('delivery.request', 'sales_engineer', 'customer_support', 'local stand-in: deliver these words through the outbox',
          'fn_customer_support_acts_on_handoff', null, false, 'scripts/sql/every_send_comes_back_to_whoever_asked.sql'),
         ('delivery.result', 'customer_support', 'sales_engineer', 'local stand-in: what became of the send',
          'fn_delivery_result_acts', null, false, 'scripts/sql/every_send_comes_back_to_whoever_asked.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Pointsasker Customer', 'zz-demo-cmp4-customer@example.invalid', '+971500000147', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Points Supplier One', 'zz-demo-cmp4-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Points Supplier Two', 'zz-demo-cmp4-s2@example.invalid') returning id into s2;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  values (i1, c, 'joinery', 'Dubai', 'ZZ DEMO points probe one', 'quoted', 'en', now() - interval '5 days', 'single'),
         (i2, c, 'joinery', 'Dubai', 'ZZ DEMO points probe two', 'quoted', 'en', now() - interval '5 days', 'single');
  insert into public.quotes (id, inquiry_id, supplier_id, option_no, quote_amount, status, created_at)
  values (q1, i1, s1, 1, 9000, 'draft', now() - interval '2 days'), (q1b, i1, s1, 2, 9500, 'draft', now() - interval '2 days'),
         (q2, i1, s2, 1, 8800, 'draft', now() - interval '2 days'), (q3, i1, s2, 2, 8700, 'draft', now() - interval '1 day'),
         (q4, i2, s1, 1, 7000, 'draft', now() - interval '2 days');
  insert into public.quote_reviews (inquiry_id, supplier_id, status, completed_at, submitted_quote_ids)
  values (i1, s1, 'submitted', now() - interval '1 day', array[q1, q1b]) returning id into r1;
  insert into public.quote_reviews (inquiry_id, supplier_id, status) values (i1, s2, 'open') returning id into r2;
  insert into public.quote_reviews (inquiry_id, supplier_id, status, completed_at, submitted_quote_ids)
  values (i2, s1, 'submitted', now() - interval '1 day', array[q4]) returning id into r4;

  -- 1. a submitted conversation: the points open, and ONE English notice to the supplier
  h1 := public.fn_seat_handoff('sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', q1::text,
          jsonb_build_object('inquiry_id', i1, 'quote_id', q1, 'label', 'Supplier A', 'points', v_points,
                             'summary', 'two points Supplier A''s quotation leaves open', 'waiting_for', 'the supplier'));
  if h1 is null then fails := fails || ' 1:no_handoff'; end if;
  select count(*) into n from public.quote_review_request where review_id = r1 and code = 'comparison_point' and state = 'open';
  if n <> 2 then fails := fails || ' 1:open_points(' || n || ')'; end if;
  if (select status from public.agent_actions where id = h1) in ('done', 'failed') then
    fails := fails || ' 1:handoff_' || (select status || ':' || coalesce(detail ->> 'error', '') from public.agent_actions where id = h1);
  end if;
  if coalesce((select (detail -> 'notice' ->> 'sent')::boolean from public.agent_actions where id = h1), false) is not true then
    fails := fails || ' 1:notice_not_sent(' || coalesce((select detail ->> 'notice' from public.agent_actions where id = h1), 'none') || ')';
  end if;
  select count(*) into n from public.notifications where type = 'quote_comparison_points' and lead_id = s1 and channel = 'email';
  if n <> 1 then fails := fails || ' 1:notices(' || n || ')'; end if;
  select * into nt from public.notifications where type = 'quote_comparison_points' and lead_id = s1 and channel = 'email' order by id limit 1;
  if found then
    if nt.lang is distinct from 'en' or nt.to_role is distinct from 'supplier' or nt.requested_by is distinct from 'sales_engineer'
       or nt.to_email is distinct from 'zz-demo-cmp4-s1@example.invalid' or nt.quote_id is distinct from q1 or nt.inquiry_id is distinct from i1 then
      fails := fails || ' 1:row(' || coalesce(nt.lang, '-') || ',' || coalesce(nt.to_role, '-') || ',' || coalesce(nt.requested_by, '-') || ')';
    end if;
    if coalesce(nt.subject, '') || coalesce(nt.body, '') ~ '[؀-ۿ]' then fails := fails || ' 1:arabic'; end if;
    if position('Pointsasker' in coalesce(nt.subject, '') || coalesce(nt.body, '')) > 0
       or position('zz-demo-cmp4-customer' in coalesce(nt.subject, '') || coalesce(nt.body, '')) > 0 then fails := fails || ' 1:customer_named'; end if;
    if position('site visit' in coalesce(nt.body, '')) > 0 or position('delivery to site' in coalesce(nt.body, '')) > 0 then fails := fails || ' 1:point_text'; end if;
    if nt.subject not like 'The sales engineer has a question about your quotation%' or position('2 points' in coalesce(nt.body, '')) = 0 then
      fails := fails || ' 1:wording';
    end if;
    -- the key is the delivery request's subject (fn_seat_clock_asked reads it there and on the row)
    if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
                    and target_id like 'delivery.request:quote_comparison_points:' || q1 || ':%' and status <> 'failed') then
      fails := fails || ' 1:key';
    end if;
  end if;

  -- 2. never repeated: the same hand-over, the routine itself, and the second option with the same points
  h1again := public.fn_seat_handoff('sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', q1::text,
          jsonb_build_object('inquiry_id', i1, 'quote_id', q1, 'label', 'Supplier A', 'points', v_points, 'summary', 'again'));
  if h1again is distinct from h1 then fails := fails || ' 2:second_handoff'; end if;
  v := public.fn_sales_engineer_comparison_points_notice(h1, r1, array['comparison:delivery_included', 'comparison:is_the_price_final']);
  if coalesce((v ->> 'sent')::boolean, true) or v ->> 'reason' <> 'already sent' then fails := fails || ' 2:resend(' || v::text || ')'; end if;
  h1b := public.fn_seat_handoff('sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', q1b::text,
          jsonb_build_object('inquiry_id', i1, 'quote_id', q1b, 'label', 'Supplier A option 2', 'points', v_points, 'summary', 'option 2'));
  select count(*) into n from public.notifications where type = 'quote_comparison_points' and lead_id = s1 and inquiry_id = i1;
  if n <> 1 then fails := fails || ' 2:notices(' || n || ')'; end if;

  -- 3. a conversation that is not submitted: the points, no notice
  h2 := public.fn_seat_handoff('sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', q2::text,
          jsonb_build_object('inquiry_id', i1, 'quote_id', q2, 'label', 'Supplier B', 'points', v_points, 'summary', 'Supplier B'));
  select count(*) into n from public.quote_review_request where review_id = r2 and code = 'comparison_point' and state = 'open';
  if n <> 2 then fails := fails || ' 3:open_points(' || n || ')'; end if;
  select count(*) into n from public.notifications where type = 'quote_comparison_points' and lead_id = s2;
  if n <> 0 then fails := fails || ' 3:notified(' || n || ')'; end if;
  if (select detail -> 'notice' ->> 'reason' from public.agent_actions where id = h2) not like 'the conversation is not submitted%' then
    fails := fails || ' 3:reason';
  end if;

  -- 4. the reveal: every open point superseded with its reason, the hand-overs closed, a queued notice cancelled
  update public.notifications set status = 'queued', last_error = null
   where type = 'quote_comparison_points' and lead_id = s1 and inquiry_id = i1;   -- as if the outbox had not sent it yet
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (q2, i1, s2, c, 8800, 'paid', now(), now() + interval '7 days');
  select count(*) into n from public.quote_review_request x join public.quote_reviews r on r.id = x.review_id
   where r.inquiry_id = i1 and x.code = 'comparison_point' and x.state = 'open';
  if n <> 0 then fails := fails || ' 4:still_open(' || n || ')'; end if;
  select count(*) into n from public.quote_review_request x join public.quote_reviews r on r.id = x.review_id
   where r.inquiry_id = i1 and x.state = 'superseded' and x.answered_at is not null and x.closed_reason = 'the customer revealed a supplier on this request';
  if n <> 4 then fails := fails || ' 4:superseded(' || n || ')'; end if;
  select count(*) into n from public.agent_actions where id in (h1, h1b, h2) and status = 'done'
     and (evidence ->> 'superseded')::boolean and evidence ->> 'reason' = 'the customer revealed a supplier on this request';
  if n <> 3 then fails := fails || ' 4:handoffs(' || n || ')'; end if;
  if exists (select 1 from public.notifications where type = 'quote_comparison_points' and inquiry_id = i1 and status in ('queued', 'held')) then
    fails := fails || ' 4:notice_still_queued';
  end if;
  h3 := public.fn_seat_handoff('sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', q3::text,
          jsonb_build_object('inquiry_id', i1, 'quote_id', q3, 'label', 'Supplier B option 2',
                             'points', jsonb_build_array(jsonb_build_object('key', 'comparison:new_after_reveal', 'supplier', 'A new point?', 'en', 'x', 'ar', 'x')),
                             'summary', 'after the reveal'));
  if exists (select 1 from public.quote_review_request where key = 'comparison:new_after_reveal') then fails := fails || ' 4:asked_after_reveal'; end if;
  if coalesce((select (evidence ->> 'raised')::int from public.agent_actions where id = h3), -1) <> 0 then fails := fails || ' 4:raised_after_reveal'; end if;
  select count(*) into n from public.notifications where type = 'quote_comparison_points' and inquiry_id = i1;
  if n <> 1 then fails := fails || ' 4:notices(' || n || ')'; end if;

  -- 5. a request that ends: its open points and hand-over close, with that reason
  h4 := public.fn_seat_handoff('sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', q4::text,
          jsonb_build_object('inquiry_id', i2, 'quote_id', q4, 'label', 'Supplier A', 'points', v_points, 'summary', 'request two'));
  select count(*) into n from public.quote_review_request where review_id = r4 and state = 'open';
  if n <> 2 then fails := fails || ' 5:open_points(' || n || ')'; end if;
  update public.inquiries set status = 'expired' where id = i2;
  select count(*) into n from public.quote_review_request where review_id = r4 and state = 'superseded' and closed_reason = 'the request is expired';
  if n <> 2 then fails := fails || ' 5:superseded(' || n || ')'; end if;
  if (select status || ':' || coalesce(evidence ->> 'reason', '') from public.agent_actions where id = h4) <> 'done:the request is expired' then
    fails := fails || ' 5:handoff(' || coalesce((select status || ':' || coalesce(evidence ->> 'reason', '') from public.agent_actions where id = h4), 'none') || ')';
  end if;

  -- 6. nobody else's rows
  if (select count(*) from public.quote_review_request x join public.quote_reviews r on r.id = x.review_id where r.inquiry_id not in (i1, i2)) <> v_other_rr then
    fails := fails || ' 6:other_points';
  end if;
  if (select count(*) from public.notifications where coalesce(to_email, '') not like 'zz-demo-cmp4-%') <> v_other_n then fails := fails || ' 6:other_notifications'; end if;
  if (select count(*) from public.agent_actions where kind = 'handoff' and status = 'done' and not (id in (h1, h1b, h2, h3, h4))
        and coalesce(detail ->> 'type', '') <> 'delivery.request') <> v_other_h then fails := fails || ' 6:other_handoffs'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: one notice per quote per point set to a submitted supplier, none to an open conversation, none twice; the reveal and the end supersede every open point and hand-over with the reason, and cancel a queued notice>>';
end
$probe$;
