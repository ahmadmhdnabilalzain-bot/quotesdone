-- Probe for a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one.sql (pure probe: it raises its
-- verdict, so everything it wrote is rolled back). Touches only its own ZZ DEMO customers (@example.invalid, the reserved
-- test identity), selected by id: the sweep is called with p_customer_id, so no real customer is ever posted for. A
-- net.http_post queued inside a rolled-back transaction is never sent.
do $probe$
declare v_unsigned uuid := gen_random_uuid(); v_signed uuid := gen_random_uuid(); r1 jsonb; r2 jsonb; r3 jsonb; v_rows int; v_gap jsonb;
begin
  insert into public.customers (id, full_name, email, email_verified, is_demo, tos_accepted_at, tos_version)
  values (v_unsigned, 'ZZ DEMO probe acceptance', 'zz-demo-acceptance-' || left(v_unsigned::text, 8) || '@example.invalid', true, true,
          now() - interval '6 minutes', 'v3'),
         (v_signed, 'ZZ DEMO probe signed', 'zz-demo-signed-' || left(v_signed::text, 8) || '@example.invalid', true, true,
          now() - interval '6 minutes', 'v3');
  update public.customers set signed_terms_path = 'customers/zz-demo.pdf', signed_terms_at = now() where id = v_signed;

  r1 := public.fn_customer_support_resigns_unsigned_terms(v_unsigned);
  r2 := public.fn_customer_support_resigns_unsigned_terms(v_unsigned);
  r3 := public.fn_customer_support_resigns_unsigned_terms(v_signed);
  select count(*) into v_rows from public.agent_actions where kind = 'customer_terms_resign' and target_id = v_unsigned::text and status = 'auto_done';
  v_gap := public.fn_it_engineer_finds_people_working_without_an_acceptance();

  raise exception 'CHK<<%>>', case
    when (r1 ->> 'posted')::int <> 1 then 'PROBE FAILED: an unsigned acceptance 6 minutes old was not signed again: ' || r1
    when (r2 ->> 'posted')::int <> 0 or (r2 ->> 'waiting')::int <> 1 then 'PROBE FAILED: signed again within 5 minutes: ' || r2
    when (r3 ->> 'posted')::int <> 0 then 'PROBE FAILED: a signed acceptance was signed again: ' || r3
    when v_rows <> 1 then 'PROBE FAILED: ' || v_rows || ' audit rows for one re-sign'
    when not (v_gap ? 'states') then 'PROBE FAILED: the acceptance count did not answer: ' || v_gap
    else 'PROBE OK: re-signed once, audited once, not again within 5 minutes, a signed one left alone; gap states ' || (v_gap -> 'states')::text
  end;
end
$probe$;
