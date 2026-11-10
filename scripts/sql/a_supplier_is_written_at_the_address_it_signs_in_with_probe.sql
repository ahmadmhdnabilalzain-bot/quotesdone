-- PROBE: THE LOSS NOTICE GOES TO THE ADDRESS THE SUPPLIER SIGNS IN WITH. Seat: customer_support. 10 Nov 2026. Pure probe:
-- no DDL, never applied; run after (or concatenated after) a_supplier_is_written_at_the_address_it_signs_in_with.sql.
-- It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if the losing supplier, whose claimed_by differs from its listed email, is told at claimed_by, and the
-- winner is told nothing.
do $probe$
declare c uuid := gen_random_uuid(); i uuid := gen_random_uuid(); sw bigint; sl bigint; v jsonb; n_claimed int; n_listed int; n_winner int;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Address Customer', 'zz-demo-address@example.invalid', '+971500000147', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email, claimed_by) values ('ZZ DEMO Address Winner', 'zz-demo-addr-w@example.invalid', 'zz-demo-addr-w@example.invalid') returning id into sw;
  insert into public.leads (company_name, email, claimed_by) values ('ZZ DEMO Address Loser', 'zz-demo-addr-listed@example.invalid', 'zz-demo-addr-signin@example.invalid') returning id into sl;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type, rfq_no)
  values (i, c, 'joinery', 'Dubai', 'ZZ DEMO address probe', 'quoted', 'en', now() - interval '5 days', 'single', 990001);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at)
  values (gen_random_uuid(), i, sw, 9000, 'submitted', now() - interval '2 days'), (gen_random_uuid(), i, sl, 9500, 'submitted', now() - interval '2 days');
  v := public.fn_sales_engineer_tells_losing_suppliers(i, sw);
  select count(*) filter (where coalesce(x.to_email, x.detail->>'to_email') = 'zz-demo-addr-signin@example.invalid'),
         count(*) filter (where coalesce(x.to_email, x.detail->>'to_email') = 'zz-demo-addr-listed@example.invalid'),
         count(*) filter (where coalesce(x.to_email, x.detail->>'to_email') = 'zz-demo-addr-w@example.invalid')
    into n_claimed, n_listed, n_winner
    from (select n.to_email, null::jsonb as detail from public.notifications n where n.type = 'job_awarded_other' and n.inquiry_id = i
          union all
          select null, a.detail->'prepared' from public.agent_actions a where a.kind = 'handoff' and a.detail->>'msg_type' = 'job_awarded_other' and a.detail->>'inquiry_id' = i::text) x;
  if n_claimed < 1 or n_listed <> 0 or n_winner <> 0 then
    raise exception 'CHK<<PROBE FAILED: sign-in % listed % winner % (%)>>', n_claimed, n_listed, n_winner, v; end if;
  raise exception 'CHK<<PROBE OK: the loser was told at its sign-in address (% row(s)), never at the listing; the winner nothing (%)>>', n_claimed, v;
end $probe$;
