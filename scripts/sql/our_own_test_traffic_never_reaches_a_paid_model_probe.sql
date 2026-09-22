-- PROBE: OUR OWN TEST TRAFFIC NEVER REACHES A PAID MODEL.
--
-- Assigned: it_engineer. 22 Sep 2026. Pure probe: no DDL, no write. Run AFTER
-- our_own_test_traffic_never_reaches_a_paid_model.sql, as ONE query through the Management API.
--
-- VERDICT: PROBE OK only if
--   1. a reserved address, a reserved number, and a real ZZ DEMO lead are each judged a fixture;
--   2. every customer and every lead the estate itself calls a fixture is judged one here (0 disagreements),
--      and every customer it calls real is judged real (0 disagreements) -- one definition, not two;
--   3. an empty subject, a malformed inquiry id and an address on no reserved domain with no row are
--      judged NOT a fixture (a customer is never stubbed by accident).
select case when a_email and a_phone and a_lead is not false
             and n_cust_disagree = 0 and n_lead_disagree = 0
             and not b_empty and not b_bad_id and not b_nobody
            then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       jsonb_build_object('reserved_email', a_email, 'reserved_phone', a_phone, 'zz_demo_lead', a_lead,
                          'customers_disagreeing', n_cust_disagree, 'leads_disagreeing', n_lead_disagree,
                          'empty_subject', b_empty, 'malformed_id', b_bad_id, 'unknown_address', b_nobody)::text as detail
  from (select
    (public.fn_ai_subject_is_fixture('{"email":"qd-probe-customer1@example.invalid"}') ->> 'fixture')::boolean as a_email,
    (public.fn_ai_subject_is_fixture('{"phone":"+971500000094"}') ->> 'fixture')::boolean as a_phone,
    (select (public.fn_ai_subject_is_fixture(jsonb_build_object('supplier_id', l.id)) ->> 'fixture')::boolean
       from public.leads l where l.company_name ilike 'ZZ DEMO%' order by l.id limit 1) as a_lead,
    (select count(*) from public.customers c
      where (public.fn_ai_subject_is_fixture(jsonb_build_object('customer_id', c.id)) ->> 'fixture')::boolean
            is distinct from public.fn_seat_clock_customer_is_fixture(c)) as n_cust_disagree,
    (select count(*) from public.leads l
      where coalesce(l.is_demo, false)
        and (public.fn_ai_subject_is_fixture(jsonb_build_object('supplier_id', l.id)) ->> 'fixture')::boolean is not true) as n_lead_disagree,
    (public.fn_ai_subject_is_fixture('{}') ->> 'fixture')::boolean as b_empty,
    (public.fn_ai_subject_is_fixture('{"inquiry_id":"fx-1"}') ->> 'fixture')::boolean as b_bad_id,
    (public.fn_ai_subject_is_fixture('{"email":"zz-probe-nobody-7f3a@quotesdone-probe-unregistered.ae"}') ->> 'fixture')::boolean as b_nobody
  ) p;
