-- Probe for a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.sql (pure probe: it raises its
-- verdict, so everything it wrote is rolled back). It touches only rows it creates itself, selected by id: the sweep is called
-- with p_customer_id, so no other customer is ever posted for. A net.http_post queued inside a rolled-back transaction is never
-- sent. Its customers cannot be reached by anything: the demo ones are on @example.invalid (the reserved test identity), and the
-- one that must count as REAL (is_demo is generated from the e-mail, phones and name, so a real-counted fixture cannot carry a
-- reserved address) has no e-mail and no phone at all.
--
-- REVIEW OF 13 NOV 2026 (run on a local Postgres 16 built from the mirror): the first version could not pass on production
-- (it inserted into customers.is_demo, a generated column; and 'PROBE FAILED: …' || r1 resolves to jsonb and raised "invalid
-- input syntax for type json"), and five mutants of the file passed it. Each fixture below exists to catch one:
--   M1 demo counted as real              -> a demo customer with a request and no acceptance moves only the demo count
--   M2 the hourly finding re-keyed       -> the real fixture's finding is filed under exactly acceptance_gap:<state>
--   M3 a customer with no acceptance re-signed -> a customer with tos_accepted_at null is never posted for
--   M4 escalation never fires            -> an acceptance with 3 earlier re-signs goes to customer_support once
--   M5 the escalation row duplicated     -> a second sweep after the escalation adds no second needs_review row
do $probe$
declare
  v_unsigned uuid := gen_random_uuid(); v_signed uuid := gen_random_uuid(); v_none uuid := gen_random_uuid();
  v_esc uuid := gen_random_uuid(); v_demo_req uuid := gen_random_uuid(); v_real uuid := gen_random_uuid();
  v_acc timestamptz := now() - interval '40 minutes';
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb; v_rows int; v_review int; v_none_rows int;
  g0 jsonb; g1 jsonb; v_keys text[]; v_ids jsonb; v_out text;
  dn int; rn int;
begin
  g0 := public.fn_it_engineer_finds_people_working_without_an_acceptance() -> 'states';

  insert into public.customers (id, full_name, email, email_verified, tos_accepted_at, tos_version) values
    (v_unsigned, 'ZZ DEMO probe acceptance', 'zz-demo-acceptance-' || left(v_unsigned::text, 8) || '@example.invalid', true, now() - interval '6 minutes', 'v3'),
    (v_signed,   'ZZ DEMO probe signed',     'zz-demo-signed-'     || left(v_signed::text, 8)   || '@example.invalid', true, now() - interval '6 minutes', 'v3'),
    (v_none,     'ZZ DEMO probe no acceptance', 'zz-demo-none-'    || left(v_none::text, 8)     || '@example.invalid', true, null, null),
    (v_esc,      'ZZ DEMO probe escalation', 'zz-demo-esc-'        || left(v_esc::text, 8)      || '@example.invalid', true, v_acc, 'v3'),
    (v_demo_req, 'ZZ DEMO probe request',    'zz-demo-request-'    || left(v_demo_req::text, 8) || '@example.invalid', true, null, null),
    -- counted as REAL by is_demo, and unreachable: no e-mail, no phone. Accepted 40 minutes ago, no certificate.
    (v_real,     'Probe fixture without contact ' || left(v_real::text, 8), null, false, v_acc, 'v3');
  update public.customers set signed_terms_path = 'customers/zz-demo.pdf', signed_terms_at = now() where id = v_signed;
  insert into public.inquiries (customer_id, summary, status) values (v_demo_req, 'ZZ DEMO probe request', 'draft');
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  select 'customer_support', 'customer_terms_resign', 'auto_done', 'low', 'ZZ DEMO probe earlier re-sign ' || n,
         jsonb_build_object('customer_id', v_esc, 'tos_accepted_at', v_acc, 'attempt', n), 'customers', v_esc::text, now() - (40 - n) * interval '1 minute'
    from generate_series(1, 3) n;

  r1 := public.fn_customer_support_resigns_unsigned_terms(v_unsigned);
  r2 := public.fn_customer_support_resigns_unsigned_terms(v_unsigned);
  r3 := public.fn_customer_support_resigns_unsigned_terms(v_signed);
  r4 := public.fn_customer_support_resigns_unsigned_terms(v_none);
  r5 := public.fn_customer_support_resigns_unsigned_terms(v_esc);
  r6 := public.fn_customer_support_resigns_unsigned_terms(v_esc);
  select count(*) into v_rows from public.agent_actions where kind = 'customer_terms_resign' and target_id = v_unsigned::text and status = 'auto_done';
  select count(*) into v_none_rows from public.agent_actions where kind = 'customer_terms_resign' and target_id = v_none::text;
  select count(*) into v_review from public.agent_actions where kind = 'customer_terms_resign' and target_id = v_esc::text and status = 'needs_review';
  g1 := public.fn_it_engineer_finds_people_working_without_an_acceptance() -> 'states';
  dn := coalesce((g1 #>> '{customer_active_without_acceptance,demo}')::int, 0) - coalesce((g0 #>> '{customer_active_without_acceptance,demo}')::int, 0);
  rn := coalesce((g1 #>> '{customer_active_without_acceptance,real}')::int, 0) - coalesce((g0 #>> '{customer_active_without_acceptance,real}')::int, 0);
  -- the findings this transaction filed or touched: their keys, and the real fixture's id under the one fixed key
  select coalesce(array_agg(f.issue_key order by f.issue_key), '{}') into v_keys
    from public.it_engineer_finding f where f.issue_key like 'acceptance_gap:%' and f.last_seen_at = now();
  select f.evidence -> 'ids' into v_ids from public.it_engineer_finding f where f.issue_key = 'acceptance_gap:customer_acceptance_without_certificate';

  v_out := case
    when (r1 ->> 'posted')::int is distinct from 1 then 'PROBE FAILED: an unsigned acceptance 6 minutes old was not signed again: ' || r1::text
    when (r2 ->> 'posted')::int <> 0 or (r2 ->> 'waiting')::int <> 1 then 'PROBE FAILED: signed again within 5 minutes: ' || r2::text
    when (r3 ->> 'posted')::int <> 0 then 'PROBE FAILED: a signed acceptance was signed again: ' || r3::text
    when v_rows <> 1 then 'PROBE FAILED: ' || v_rows || ' audit rows for one re-sign'
    when (r4 ->> 'posted')::int <> 0 or v_none_rows <> 0 then 'PROBE FAILED (M3): a customer with no acceptance was signed: ' || r4::text
    when (r5 ->> 'escalated')::int is distinct from 1 or (r5 ->> 'posted')::int <> 0 then 'PROBE FAILED (M4): three re-signs did not go to customer_support: ' || r5::text
    when (r6 ->> 'escalated')::int <> 0 or v_review <> 1 then 'PROBE FAILED (M5): ' || v_review || ' needs_review rows for one acceptance: ' || r6::text
    when g1 is null then 'PROBE FAILED: the acceptance count did not answer'
    when dn <> 1 or rn <> 0 then 'PROBE FAILED (M1): a demo customer with a request moved the counts by demo ' || dn || ', real ' || rn
    when v_keys <> array['acceptance_gap:customer_acceptance_without_certificate'] then 'PROBE FAILED (M2): the real gap was filed under ' || array_to_string(v_keys, ', ')
    when not coalesce(v_ids ? v_real::text, false) then 'PROBE FAILED (M2): the finding acceptance_gap:customer_acceptance_without_certificate does not carry the real fixture: ' || coalesce(v_ids::text, 'null')
    else 'PROBE OK: re-signed once, audited once, not again within 5 minutes, a signed one and an unaccepted one left alone, '
      || 'three re-signs escalated once, demo kept apart, the real gap filed under its one key' end;
  raise exception 'CHK<<%>>', v_out;
end
$probe$;
