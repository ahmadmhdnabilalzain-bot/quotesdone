-- PROBE: A CUSTOMER'S FOLLOW-UP ANSWER IS IN EVERY READING OF HIS REQUEST. Seat: customer_support. Agent: W3_PEOPLE, 16 Nov 2026.
-- Pure probe: no DDL, never applied; run after a_customers_follow_up_answer_is_in_every_reading_of_his_request.sql on a LOCAL
-- Postgres 16. It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. fn_customer_inquiry_facts carries, on the request he revealed on, his LATEST follow-up answer (not decided yet, his own words
--      "site visit Tuesday", the day he answered): the reading WhatsApp, the widget, the portal chat and the e-mail reply all hand
--      the model, so "any news?" is answered from it;
--   2. a follow-up that was asked and not answered is not presented as an answer;
--   3. another customer's follow-up on another request never appears in his facts.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); s bigint; i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid();
  q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); t1 uuid := gen_random_uuid(); t2 uuid := gen_random_uuid(); j jsonb; r jsonb;
begin
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO FU Customer', 'zz-demo-w3fu-c@example.invalid', '+971500000771', true, true, 'demo://terms', 'en', now() - interval '40 days'),
         (c2, 'ZZ DEMO FU Other', 'zz-demo-w3fu-c2@example.invalid', '+971500000772', true, true, 'demo://terms', 'en', now() - interval '40 days');
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_email_verified)
  values ('ZZ DEMO W3FU Supplier', 'zz-demo-w3fu-s@example.invalid', 'zz-demo-w3fu-s@example.invalid', 'Dubai', '+971500000773', true) returning id into s;
  insert into public.inquiries (id, customer_id, category, emirate, summary, raw_input, budget, scope_type, trades, spec, status, lang, created_at)
  values (i1, c, 'plumbing', 'Dubai', 'ZZ DEMO replace two water heaters', 'ZZ DEMO', 'AED 5,000', 'single', array['plumbing'], '{}'::jsonb, 'revealed', 'en', now() - interval '20 days'),
         (i2, c2, 'plumbing', 'Dubai', 'ZZ DEMO other job', 'ZZ DEMO', null, 'single', array['plumbing'], '{}'::jsonb, 'revealed', 'en', now() - interval '20 days');
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, lead_time, status)
  values (q1, i1, s, 4200, 4000, '5 days', 'submitted'), (q2, i2, s, 1050, 1000, '2 days', 'submitted');
  insert into public.transactions (id, quote_id, inquiry_id, supplier_id, customer_id, revealed_at)
  values (t1, q1, i1, s, c, now() - interval '15 days'), (t2, q2, i2, s, c2, now() - interval '15 days');

  -- 2. asked, not answered: no answer is presented
  insert into public.customer_followup (transaction_id, stage, lang, asked_at) values (t1, 'day_three', 'en', now() - interval '12 days');
  select x into r from jsonb_array_elements(public.fn_customer_inquiry_facts(c, 10)) x where x->>'id' = i1::text;
  if r is null then fails := fails || ' 2:no_request_row'; end if;
  if jsonb_typeof(r->'his_follow_up_answer') = 'object' then fails := fails || ' 2:unanswered_presented(' || (r->'his_follow_up_answer')::text || ')'; end if;

  -- 1. day 14: "not yet, site visit Tuesday"; the day-3 answer is older
  update public.customer_followup set answered_at = now() - interval '11 days', hired = 'not_yet', comment = 'ZZ DEMO still comparing'
   where transaction_id = t1 and stage = 'day_three';
  insert into public.customer_followup (transaction_id, stage, lang, asked_at, answered_at, hired, comment)
  values (t1, 'day_fourteen', 'en', now() - interval '2 days', now() - interval '1 day', 'not_yet', 'ZZ DEMO not yet, site visit Tuesday');
  select x into r from jsonb_array_elements(public.fn_customer_inquiry_facts(c, 10)) x where x->>'id' = i1::text;
  j := r->'his_follow_up_answer';
  if jsonb_typeof(j) is distinct from 'object' then fails := fails || ' 1:missing';
  else
    if coalesce(j->>'his_words', '') !~ 'site visit Tuesday' then fails := fails || ' 1:not_latest(' || coalesce(j::text, '') || ')'; end if;
    if coalesce(j->>'hired', '') !~* 'not decided' then fails := fails || ' 1:hired(' || coalesce(j::text, '') || ')'; end if;
    if j->>'answered_on' is null then fails := fails || ' 1:no_date'; end if;
  end if;

  -- 3. another customer's answer never appears in his facts
  insert into public.customer_followup (transaction_id, stage, lang, answered_at, hired, comment)
  values (t2, 'day_three', 'en', now(), 'yes', 'ZZ DEMO other customers words');
  if public.fn_customer_inquiry_facts(c, 10)::text ~ 'other customers words' then fails := fails || ' 3:leaked'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: the latest follow-up answer (not decided yet, his words, its date) rides in the request facts every channel reads; an unanswered ask is not an answer; no other customer''s answer appears>>';
end $probe$;
