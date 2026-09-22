-- PROBE: OUR OWN TEST TRAFFIC NEVER REACHES A PAID MODEL, AND NOBODY ELSE CAN LOOK LIKE IT.
--
-- Assigned: it_engineer. 22 Sep 2026. Pure probe: no DDL, no write. Run AFTER
-- our_own_test_traffic_never_reaches_a_paid_model.sql, as ONE query through the Management API.
--
-- VERDICT: PROBE OK only if
--   1. every harness auth user (qd-<tag>-*@example.*) whose run tag has a rehearsal_window row is a fixture,
--      by email and, where one exists, by its customers row;
--   2. what a person can type on sign-up is NOT a fixture: an @example.invalid address with no harness shape,
--      a harness-shaped address whose tag no run ever opened, and a ZZ DEMO lead no harness identity claimed;
--   3. no real (non-demo) customer is a fixture; an empty subject and a malformed id are not fixtures.
select case when n_harness > 0 and n_harness_missed = 0 and n_harness_cust_missed = 0
             and not b_typed_domain and not b_unopened_tag and n_zz_lead_typed = 0
             and n_real_cust_stubbed = 0 and not b_empty and not b_bad_id
            then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       jsonb_build_object('harness_users', n_harness, 'harness_missed', n_harness_missed,
                          'harness_customers_missed', n_harness_cust_missed,
                          'typed_example_invalid', b_typed_domain, 'unopened_tag', b_unopened_tag,
                          'zz_demo_leads_not_harness_but_stubbed', n_zz_lead_typed,
                          'real_customers_stubbed', n_real_cust_stubbed,
                          'empty_subject', b_empty, 'malformed_id', b_bad_id)::text as detail
  from (select
    (select count(*) from auth.users u
      where u.email ~ '^qd-[a-z0-9]+-[^@]*@example[.]'
        and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || substring(u.email from '^qd-([a-z0-9]+)-'))) as n_harness,
    (select count(*) from auth.users u
      where u.email ~ '^qd-[a-z0-9]+-[^@]*@example[.]'
        and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || substring(u.email from '^qd-([a-z0-9]+)-'))
        and (public.fn_ai_subject_is_fixture(jsonb_build_object('email', u.email)) ->> 'fixture')::boolean is not true) as n_harness_missed,
    (select count(*) from public.customers c
      where c.email ~ '^qd-[a-z0-9]+-[^@]*@example[.]'
        and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || substring(c.email from '^qd-([a-z0-9]+)-'))
        and (public.fn_ai_subject_is_fixture(jsonb_build_object('customer_id', c.id)) ->> 'fixture')::boolean is not true) as n_harness_cust_missed,
    (public.fn_ai_subject_is_fixture('{"email":"zz-demo-someone@example.invalid"}') ->> 'fixture')::boolean as b_typed_domain,
    (public.fn_ai_subject_is_fixture('{"email":"qd-zzneveropened0-cust1@example.invalid"}') ->> 'fixture')::boolean as b_unopened_tag,
    (select count(*) from (select l.id from public.leads l
       where l.company_name ilike 'ZZ DEMO%'
         and coalesce(lower(l.claimed_by), '') !~ '^qd-[a-z0-9]+-' and coalesce(lower(l.email), '') !~ '^qd-[a-z0-9]+-'
       order by l.id limit 50) z
      where (public.fn_ai_subject_is_fixture(jsonb_build_object('supplier_id', z.id)) ->> 'fixture')::boolean) as n_zz_lead_typed,
    (select count(*) from public.customers c
      where not coalesce(c.is_demo, false)
        and (public.fn_ai_subject_is_fixture(jsonb_build_object('customer_id', c.id)) ->> 'fixture')::boolean) as n_real_cust_stubbed,
    (public.fn_ai_subject_is_fixture('{}') ->> 'fixture')::boolean as b_empty,
    (public.fn_ai_subject_is_fixture('{"inquiry_id":"fx-1"}') ->> 'fixture')::boolean as b_bad_id
  ) p;
