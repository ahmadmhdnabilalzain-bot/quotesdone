-- PROBE (pure, no DDL): fn_sales_engineer_reveal_followup_tick writes once to a quoted, unrevealed demo request,
-- never twice, and never to a request whose quote was revealed. ZZ DEMO + @example.invalid only, fixture mode, and
-- every row it makes is rolled back by the raise at the end.
--   node scripts/apply_sql.mjs scripts/sql/a_customer_with_quotes_who_has_not_revealed_is_nudged_and_offered_help_probe.sql --apply
do $probe$
declare
  v_c uuid := gen_random_uuid(); v_open uuid; v_rev uuid; v_q uuid; v_q1 uuid; v_lead bigint;
  v_real_before int; v_real_after int; r1 jsonb; r2 jsonb; n_open int; n_rev int;
begin
  select min(id) into v_lead from public.leads where is_demo and email ilike '%@example.invalid';
  if v_lead is null then raise exception 'CHK<<no demo lead to quote with>>'; end if;
  select count(*) into v_real_before from public.customer_support_duty_message m join public.customers k on k.id = m.customer_id where m.stage like 'reveal.%' and not (coalesce(k.is_demo, false) or public.fn_is_demo_email(k.email));
  set local qd.duty_fixtures = 'on';
  insert into public.customers (id, email, full_name, email_verified, locale)
  values (v_c, 'zz-demo-reveal-' || left(v_c::text, 8) || '@example.invalid', 'ZZ DEMO reveal probe', true, 'en');
  insert into public.inquiries (customer_id, category, emirate, status, lang, created_at)
  values (v_c, 'tiling', 'Dubai', 'quoted', 'en', now() - interval '4 days') returning id into v_open;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at)
  values (v_open, v_lead, 10000, 'submitted', now() - interval '3 days') returning id into v_q1;
  insert into public.inquiries (customer_id, category, emirate, status, lang, created_at)
  values (v_c, 'painting', 'Dubai', 'quoted', 'en', now() - interval '4 days') returning id into v_rev;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at)
  values (v_rev, v_lead, 8000, 'submitted', now() - interval '3 days') returning id into v_q;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, revealed_at)
  values (v_q, v_rev, v_lead, v_c, 8000, now() - interval '1 day');

  -- the quality gate holds a line-less demo quote as a draft; release it as its clock would, so the customer sees it
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (v_q1, v_q);
  update public.quotes set status = 'submitted' where id in (v_q1, v_q);
  r1 := public.fn_sales_engineer_reveal_followup_tick();
  r2 := public.fn_sales_engineer_reveal_followup_tick();
  select count(*) into n_open from public.customer_support_duty_message where stage = 'reveal.day_two' and subject_key = v_open::text;
  select count(*) into n_rev from public.customer_support_duty_message where subject_key = v_rev::text;
  select count(*) into v_real_after from public.customer_support_duty_message m join public.customers k on k.id = m.customer_id where m.stage like 'reveal.%' and not (coalesce(k.is_demo, false) or public.fn_is_demo_email(k.email));
  raise exception 'CHK<<%>>', case
    when n_open = 1 and n_rev = 0 and (r2->>'sent')::int = 0 and v_real_after = v_real_before
    then 'PROBE OK open=1 revealed=0 second_run_sent=0 first=' || r1::text
    else 'PROBE FAILED open=' || n_open || ' revealed=' || n_rev || ' r1=' || r1::text || ' r2=' || r2::text || ' real ' || v_real_before || '->' || v_real_after end;
end $probe$;
