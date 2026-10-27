-- PROBE: the 24-hour quote promise. Pure probe, no DDL: run AFTER
-- a_request_with_no_quote_in_24_hours_is_widened_and_no_supplier_is_nudged_twice_a_day.sql; it always ends in raise
-- exception CHK<<...>>, so nothing it writes survives. Everyone in it is ZZ DEMO on @example.invalid (a fixture customer,
-- two fixture suppliers it inserts); the clock runs in fixture mode, and a fixture subject may only ever write to a
-- fixture address (fn_seat_clock_refusal), so it cannot reach a real person even before the rollback.
-- PROBE OK only if, for two requests sent 25 hours ago with 0 quotes, S1 invited to both and S2 to one:
--   1. both requests are widened once (routing.short_sweep written);
--   2. S1 gets ONE reminder, not two, and S2 gets one;
--   3. the customer is told once per request;
--   4. a second tick adds no reminder and no customer notice.
do $probe$
declare cu uuid := gen_random_uuid(); i1 uuid; i2 uuid; s1 bigint; s2 bigint; v jsonb; v2 jsonb;
        r1 int; r2 int; r1b int; r2b int; t1 int; t2 int; w int; v_fail text := '';
begin
  insert into public.customers (id, email, full_name, email_verified, locale)
  values (cu, 'qd-qspeed-c@example.invalid', 'ZZ DEMO Quote Speed Customer', true, 'en');
  insert into public.leads (company_name, email, emirate, tags, source) values
    ('ZZ DEMO Quote Speed S1', 'qd-qspeed-s1@example.invalid', 'Dubai', array['qd_demo'], 'qd_demo_fixture') returning id into s1;
  insert into public.leads (company_name, email, emirate, tags, source) values
    ('ZZ DEMO Quote Speed S2', 'qd-qspeed-s2@example.invalid', 'Dubai', array['qd_demo'], 'qd_demo_fixture') returning id into s2;
  insert into public.inquiries (customer_id, category, trades, emirate, raw_input, status, provenance)
  values (cu, 'aluminium', array['aluminium'], 'Dubai', 'ZZ DEMO quote-speed probe request one', 'sent', '{"qd_run":"qspeed"}') returning id into i1;
  insert into public.inquiries (customer_id, category, trades, emirate, raw_input, status, provenance)
  values (cu, 'aluminium', array['aluminium'], 'Dubai', 'ZZ DEMO quote-speed probe request two', 'sent', '{"qd_run":"qspeed"}') returning id into i2;
  insert into public.inquiry_matches (inquiry_id, supplier_id, sent_at, match_reason) values
    (i1, s1, now() - interval '25 hours', 'probe'), (i2, s1, now() - interval '25 hours', 'probe'),
    (i1, s2, now() - interval '25 hours', 'probe');

  v := public.fn_rfq_short_of_quotes_tick(true);
  select count(*) into r1 from public.notifications where lead_id = s1 and type = 'rfq_quote_reminder';
  select count(*) into r2 from public.notifications where lead_id = s2 and type = 'rfq_quote_reminder';
  select count(*) filter (where inquiry_id = i1), count(*) filter (where inquiry_id = i2) into t1, t2
    from public.notifications where inquiry_id in (i1, i2) and type = 'rfq_short_of_quotes';
  select count(*) into w from public.inquiries where id in (i1, i2) and routing ? 'short_sweep';

  v2 := public.fn_rfq_short_of_quotes_tick(true);
  select count(*) into r1b from public.notifications where lead_id = s1 and type = 'rfq_quote_reminder';
  select count(*) into r2b from public.notifications where lead_id = s2 and type = 'rfq_quote_reminder';

  if w <> 2 then v_fail := v_fail || ' widened ' || w || ' of 2;'; end if;
  if r1 <> 1 then v_fail := v_fail || ' S1 (two requests) reminded ' || r1 || ' times in one day;'; end if;
  if r2 <> 1 then v_fail := v_fail || ' S2 reminded ' || r2 || ' times;'; end if;
  if t1 <> 1 or t2 <> 1 then v_fail := v_fail || ' customer told ' || t1 || '/' || t2 || ' (want 1/1);'; end if;
  if r1b <> r1 or r2b <> r2 then v_fail := v_fail || ' the second tick nudged again (' || r1b || '/' || r2b || ');'; end if;
  if (select count(*) from public.notifications where (lead_id in (s1, s2) or inquiry_id in (i1, i2))
        and to_email is not null and not public.fn_is_demo_email(to_email)) > 0 then
    v_fail := v_fail || ' a message to a non-demo address;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK widened 2/2; S1 reminded once across two requests, S2 once; customer told 1/1; second tick added nothing; swept '
      || coalesce(v->>'swept', '?')
    else 'PROBE FAILED:' || v_fail || ' tick=' || left(v::text, 300) end;
end $probe$;
