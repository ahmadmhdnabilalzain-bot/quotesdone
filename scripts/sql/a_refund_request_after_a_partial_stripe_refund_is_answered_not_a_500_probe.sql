-- PROBE: A REFUND REQUEST AFTER A PARTIAL STRIPE REFUND IS ANSWERED, NOT A 500.
--
-- Assigned: accountant. 3 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_refund_request_after_a_partial_stripe_refund_is_answered_not_a_500.sql. It always raises, so every row it writes
-- (two ZZ DEMO reveals on @example.invalid, one recorded dashboard refund) is rolled back.
--
-- PROBE OK only if
--   1. a request on a reveal AED 10.00 of whose AED 30.00 was refunded in Stripe answers ok:false, code
--      already_refunded, names AED 10.00, raises nothing, and opens no second refund row;
--   2. a request on an untouched reveal still opens its case for everything paid (the control);
--   3. anon and authenticated cannot execute fn_refund_open_from_customer.
do $probe$
declare
  c uuid := gen_random_uuid(); l bigint; i uuid; i2 uuid; q1 uuid; q2 uuid; t1 uuid; t2 uuid; r1 jsonb; r2 jsonb; fails text := '';
begin
  insert into public.customers (id, email, full_name, email_verified, locale)
  values (c, 'qd-probepartial-cust1@example.invalid', 'ZZ DEMO probe customer', true, 'en');
  insert into public.leads (company_name, emirate, email, source, tags)
  values ('ZZ DEMO probe supplier', 'Dubai', 'qd-probepartial-sup1@example.invalid', 'demo_factory', array['qd_demo']) returning id into l;
  insert into public.inquiries (customer_id, category, emirate, raw_input, summary, status, provenance)
  values (c, 'aluminium', 'Dubai', 'ZZ DEMO probe', 'ZZ DEMO probe', 'sent', '{"source":"probe"}') returning id into i;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, notes, status, source)
  values (i, l, 1000, 'ZZ DEMO probe partial', 'submitted', 'form') returning id into q1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged,
                                   customer_price, paid_by, payment_ref, fee_status, revealed_at)
  values (q1, i, l, c, 1000, 30, 30, 1000, 'customer', 'pi_probe_partial_1', 'paid', now()) returning id into t1;
  -- What stripe_webhook records for a refund issued in the dashboard: no transaction, the payment's reference.
  insert into public.refunds (stripe_refund_id, stripe_payment_intent, amount_fils, reason_code, status, requested_by, amount_source, customer_id)
  values ('re_probe_partial_1', 'pi_probe_partial_1', 1000, 'other', 'succeeded', 'stripe_webhook', 'webhook_event', c);

  begin
    r1 := public.fn_refund_open_from_customer(t1, 'customer');
  exception when others then
    fails := fails || ' 1:raised(' || left(sqlerrm, 120) || ')';
  end;
  if r1 is not null and (coalesce((r1->>'ok')::boolean, true) or r1->>'code' is distinct from 'already_refunded') then
    fails := fails || ' 1:not_already_refunded(' || left((r1 - 'message_ar')::text, 160) || ')'; end if;
  if r1 is not null and position('AED 10.00' in coalesce(r1->>'message_en', '')) = 0 then fails := fails || ' 1:amount_not_named'; end if;
  if (select count(*) from public.refunds where stripe_payment_intent = 'pi_probe_partial_1') <> 1 then fails := fails || ' 1:second_row'; end if;

  insert into public.inquiries (customer_id, category, emirate, raw_input, summary, status, provenance)
  values (c, 'aluminium', 'Dubai', 'ZZ DEMO probe 2', 'ZZ DEMO probe 2', 'sent', '{"source":"probe"}') returning id into i2;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, notes, status, source)
  values (i2, l, 2000, 'ZZ DEMO probe control', 'submitted', 'form') returning id into q2;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged,
                                   customer_price, paid_by, payment_ref, fee_status, revealed_at)
  values (q2, i2, l, c, 2000, 60, 60, 2000, 'customer', 'pi_probe_partial_2', 'paid', now()) returning id into t2;
  r2 := public.fn_refund_open_from_customer(t2, 'customer');
  if coalesce((r2->>'ok')::boolean, false) is not true
     or (select amount_fils from public.refunds where transaction_id = t2) is distinct from 6000 then
    fails := fails || ' 2:control_case_not_opened(' || left((r2 - 'message_ar')::text, 160) || ')'; end if;

  if has_function_privilege('anon', 'public.fn_refund_open_from_customer(uuid,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_refund_open_from_customer(uuid,text,text)', 'execute') then
    fails := fails || ' 3:client_can_execute'; end if;

  raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK partial=' || coalesce(r1->>'code', 'null') || ' control=' || coalesce(r2->>'refund_id', 'null')
                                    else 'PROBE FAILED:' || fails end;
end $probe$;
