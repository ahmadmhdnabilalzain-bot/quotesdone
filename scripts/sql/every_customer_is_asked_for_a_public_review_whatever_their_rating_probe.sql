-- PROBE for every_customer_is_asked_for_a_public_review_whatever_their_rating.sql. Seat: marketing.
-- A pure probe: it always raises CHK<<...>>, so every row it writes is rolled back. ZZ DEMO customers on
-- example.invalid only; the review link is example.invalid, so nothing can reach a real person.
-- Every ZZ DEMO customer is is_demo (generated column), so the chooser is run with p_include_fixtures => true
-- to prove the rating plays no part, and with its default to prove fixtures are never asked.
-- Expected verdict: PROBE OK.
do $$
declare
  k text := 'zz-demo-review-gating-' || substr(md5(random()::text), 1, 8);
  c uuid[] := array[]::uuid[]; t uuid[] := array[]::uuid[]; i int; o jsonb; w uuid[];
begin
  -- 1 rated 1 star, 2 rated 5 stars, 3 never rated, 4 revealed only 5 days ago, 5 refunded, 6 unsubscribed.
  for i in 1..6 loop
    c := c || gen_random_uuid(); t := t || gen_random_uuid();
    insert into public.customers (id, full_name, email) values (c[i], 'ZZ DEMO review ' || i, k || '-' || i || '@example.invalid');
    insert into public.transactions (id, customer_id, revealed_at)
      values (t[i], c[i], now() - case when i = 4 then interval '5 days' else interval '30 days' end);
  end loop;
  update public.transactions set refund_status = 'refunded' where id = t[5];
  insert into public.reviews (customer_id, transaction_id, rating) values (c[1], t[1], 1), (c[2], t[2], 5);
  insert into public.email_suppressions (email, reason, source) values (k || '-6@example.invalid', 'unsubscribe', 'probe');

  select coalesce(array_agg(transaction_id), '{}') into w from public.fn_marketing_review_ask_candidates(true) where transaction_id = any (t);
  o := jsonb_build_object('low', t[1] = any (w), 'high', t[2] = any (w), 'unrated', t[3] = any (w),
                          'early', t[4] = any (w), 'refunded', t[5] = any (w), 'suppressed', t[6] = any (w));

  -- The duty itself: fixtures are never queued, and a queued job is not chosen twice.
  delete from public.app_secrets where key = 'public_review_url';
  insert into public.app_secrets (key, value) values ('public_review_url', 'https://example.invalid/review');
  perform public.fn_marketing_reputation();
  o := o || jsonb_build_object('demo_queued', (select count(*) from public.company_review_ask where transaction_id = any (t)));
  insert into public.company_review_ask (customer_id, transaction_id, status) values (c[1], t[1], 'asked');
  o := o || jsonb_build_object('again', exists (select 1 from public.fn_marketing_review_ask_candidates(true) where transaction_id = t[1]));

  o := o || jsonb_build_object('verdict', case when o = '{"low":true,"high":true,"unrated":true,"early":false,"refunded":false,"suppressed":false,"demo_queued":0,"again":false}'::jsonb
                                               then 'PROBE OK' else 'PROBE FAILED' end);
  raise exception 'CHK<<%>>', o::text;
end $$;
