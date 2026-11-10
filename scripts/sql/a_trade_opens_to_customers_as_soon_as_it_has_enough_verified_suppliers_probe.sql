-- PROBE for a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql. Seat: ceo. Never applied: it always
-- raises CHK<<...>> and rolls back everything it wrote. Every subject is its own ZZ DEMO fixture (@example.invalid, is_demo),
-- and it counts what it would have sent to anyone else: a fixture is marked told without a message, so it reaches nobody.
-- The trade is one with no verified supplier today (abrasives_surface_finishing, measured 10 Nov 2026: 0), so its counts
-- are the probe's own.
do $probe$
declare t text := 'abrasives_surface_finishing'; v_cust uuid; g jsonb; j jsonb; k jsonb; v_inq uuid; v_tick jsonb; v_lr jsonb; v_demo_trade text; v_real_inq uuid;
  v_real_wait_before int; v_founder_before int; v_mail_before int; v_bad text := ''; v_floor_refused boolean := false; i int;
begin
  -- the real counting path, unseamed: no demo supplier counts, and today no real one is verified
  if (select count(*) from public.trade_customer_opening) = 0 and exists (select 1 from public.taxonomy_trade tt where tt.active and public.fn_trade_verified_suppliers(tt.code) > 0 and tt.code in ('aluminium', 'gypsum', 'painting')) then
    v_bad := v_bad || ' demo-supplier-counted?'; end if;
  if public.fn_trade_verified_suppliers(t) <> 0 then raise exception 'CHK<<PROBE FAILED: % already has verified suppliers>>', t; end if;
  select count(*) into v_real_wait_before from public.customer_trade_waitlist w where w.customer_id is null or not public.fn_customer_is_demo(w.customer_id);
  select count(*) into v_founder_before from public.notifications where to_role in ('founder', 'admin');
  select count(*) into v_mail_before from public.notifications;

  insert into public.customers (full_name, email, phone, locale)   -- is_demo is generated from the ZZ DEMO name and the address
  values ('ZZ DEMO Trade Opening Customer', 'zz-demo-trade-opening@example.invalid', '+971500000097', 'en') returning id into v_cust;

  -- 1. the door, before: not open, honest words in both languages
  g := public.fn_trade_customer_gate(array[t], 'en');
  if g->>'state' <> 'not_open' then v_bad := v_bad || ' gate-before=' || (g->>'state'); end if;
  if coalesce(g->>'message', '') !~ 'onboarding verified suppliers' then v_bad := v_bad || ' no-en-message'; end if;
  if coalesce(public.fn_trade_customer_gate(array[t], 'ar')->>'message', '') !~ (select label_ar from public.taxonomy_trade where code = t) then v_bad := v_bad || ' no-ar-label'; end if;
  if public.fn_trade_customer_gate(array['general'], 'en')->>'state' <> 'unclassified' then v_bad := v_bad || ' general-not-unclassified'; end if;

  -- 2. the waiting list: one row, asking twice is still one
  j := public.fn_trade_waitlist_join(array[t], 'portal', v_cust, null, 'en', null);
  perform public.fn_trade_waitlist_join(array[t], 'portal', v_cust, null, 'en', null);
  if not coalesce((j->>'waitlisted')::boolean, false) then v_bad := v_bad || ' not-waitlisted'; end if;
  if (select count(*) from public.customer_trade_waitlist where customer_id = v_cust and status = 'waiting') <> 1 then v_bad := v_bad || ' waitlist-not-one'; end if;
  -- a WhatsApp visitor with no account is told to register (the platform may not write first)
  k := public.fn_trade_waitlist_join(array[t], 'whatsapp', null, '+971500000098', 'en', null);
  if coalesce(k->>'message', '') !~ 'Register here' then v_bad := v_bad || ' visitor-not-asked-to-register'; end if;

  -- 3. no paid reveal under the floor
  insert into public.inquiries (customer_id, category, trades, status, summary, lang, role_needed)
  values (v_cust, t, array[t], 'draft', 'ZZ DEMO trade opening probe', 'en', 'supplier') returning id into v_inq;
  if coalesce((public.fn_trade_reveal_allowed(v_inq)->>'allowed')::boolean, true) then v_bad := v_bad || ' reveal-allowed-at-0'; end if;

  -- 4. ten verified suppliers (the count seam: a verified supplier cannot be faked, see the main file): the trade opens,
  --    the reveal is allowed, the waiting fixture is told without a message
  perform set_config('qd.trade_opening_fixture_counts', jsonb_build_object(t, 10, t || '@fixture', 10)::text, true);
  if public.fn_trade_verified_suppliers(t) <> 10 then v_bad := v_bad || ' seam-count=' || public.fn_trade_verified_suppliers(t); end if;
  if public.fn_trade_customer_gate(array[t], 'en')->>'state' <> 'open' then v_bad := v_bad || ' gate-at-10-not-open'; end if;
  if not coalesce((public.fn_trade_reveal_allowed(v_inq)->>'allowed')::boolean, false) then v_bad := v_bad || ' reveal-refused-at-10'; end if;
  v_tick := public.fn_ceo_trade_opening_tick();
  if not (select is_open from public.trade_customer_opening where trade = t) then v_bad := v_bad || ' tick-did-not-open'; end if;
  if (select status from public.customer_trade_waitlist where customer_id = v_cust) <> 'notified' then v_bad := v_bad || ' fixture-not-told'; end if;
  if (select notice->>'fixture' from public.customer_trade_waitlist where customer_id = v_cust) is distinct from 'true' then v_bad := v_bad || ' fixture-told-for-real'; end if;
  if (select status from public.customer_trade_waitlist where phone = '+971500000098') not in ('withdrawn', 'notified') then v_bad := v_bad || ' visitor-row-left-waiting'; end if;

  -- 5. hysteresis: 6 left stays open (>= the floor of 5); 4 left closes
  perform set_config('qd.trade_opening_fixture_counts', jsonb_build_object(t, 6, t || '@fixture', 6)::text, true);
  perform public.fn_ceo_trade_opening_tick();
  if not (select is_open from public.trade_customer_opening where trade = t) then v_bad := v_bad || ' closed-at-6'; end if;
  perform set_config('qd.trade_opening_fixture_counts', jsonb_build_object(t, 4, t || '@fixture', 4)::text, true);
  perform public.fn_ceo_trade_opening_tick();
  if (select is_open from public.trade_customer_opening where trade = t) then v_bad := v_bad || ' open-at-4'; end if;
  if coalesce((public.fn_trade_reveal_allowed(v_inq)->>'allowed')::boolean, true) then v_bad := v_bad || ' reveal-allowed-at-4'; end if;

  -- 6. the floor is the schema; the odds the threshold is chosen on; the tune does not move on no evidence
  begin update public.trade_opening_rule set open_at_suppliers = 4 where id = 1; exception when check_violation then v_floor_refused := true; end;
  if not v_floor_refused then v_bad := v_bad || ' floor-4-accepted'; end if;
  if public.fn_trade_quote_odds(10, 0.40) <> 0.8327 or public.fn_trade_quote_odds(5, 0.60) <> 0.6826 then
    v_bad := v_bad || ' odds=' || public.fn_trade_quote_odds(10, 0.40) || '/' || public.fn_trade_quote_odds(5, 0.60); end if;
  if coalesce((public.fn_ceo_trade_opening_tune(now())->>'changed')::boolean, true) and (select count(*) from public.inquiry_matches) < 30 then v_bad := v_bad || ' tuned-on-nothing'; end if;

  -- 7. the launch gate is per trade and mails nobody
  v_lr := public.fn_ceo_launch_readiness(now());
  if v_lr->>'rule' <> 'trade by trade (ledger 1614)' then v_bad := v_bad || ' launch-rule=' || coalesce(v_lr->>'rule', 'null'); end if;
  if (select count(*) from public.notifications where to_role in ('founder', 'admin')) <> v_founder_before then v_bad := v_bad || ' founder-mailed'; end if;

  -- 8. nothing reached anybody: no notification row at all, and the real waiting list untouched
  if (select count(*) from public.notifications) <> v_mail_before then v_bad := v_bad || ' notifications+' || ((select count(*) from public.notifications) - v_mail_before); end if;
  if (select count(*) from public.customer_trade_waitlist w where w.customer_id is null and w.phone <> '+971500000098' or (w.customer_id is not null and not public.fn_customer_is_demo(w.customer_id))) <> v_real_wait_before then v_bad := v_bad || ' real-waitlist-touched'; end if;

  -- 9. DEMO SUPPLIERS COUNT ONLY FOR A DEMO CUSTOMER (coordinator review). Unseamed, on today's rows: the one ZZ DEMO
  --    matchable supplier counts for a demo request in its trade and never for a real one.
  perform set_config('qd.trade_opening_fixture_counts', '', true);
  select tt.code into v_demo_trade from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id, unnest(sc.trades) tt(code)
   where l.is_demo and sc.confirmed_at is not null
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes) limit 1;
  if v_demo_trade is not null and (public.fn_trade_verified_suppliers(v_demo_trade, true) < 1 or public.fn_trade_verified_suppliers(v_demo_trade, false) >= public.fn_trade_verified_suppliers(v_demo_trade, true)) then
    v_bad := v_bad || ' demo-supplier-direction(' || v_demo_trade || ')'; end if;
  --    Seamed, both directions: 5 demo suppliers and 0 real ones in the trade.
  perform set_config('qd.trade_opening_fixture_counts', jsonb_build_object(t, 0, t || '@fixture', 5)::text, true);
  update public.customer_trade_waitlist set status = 'withdrawn' where customer_id = v_cust and status = 'waiting';
  j := public.fn_trade_waitlist_join(array[t], 'portal', v_cust, null, 'en', null);              -- a ZZ DEMO customer
  if j->>'state' <> 'open' or coalesce((j->>'waitlisted')::boolean, true) then v_bad := v_bad || ' demo-customer-not-open:' || (j->>'state'); end if;
  if not coalesce((public.fn_trade_reveal_allowed(v_inq)->>'allowed')::boolean, false) then v_bad := v_bad || ' demo-reveal-refused'; end if;
  if public.fn_trade_customer_gate(array[t], 'en', false)->>'state' <> 'not_open' then v_bad := v_bad || ' real-door-open-on-demo-suppliers'; end if;
  begin   -- a request no customer owns reads as real (fn_inquiry_is_demo false): its reveal must be refused
    insert into public.inquiries (customer_id, category, trades, status, summary, lang, role_needed)
    values (null, t, array[t], 'draft', 'ZZ DEMO trade opening probe, ownerless', 'en', 'supplier') returning id into v_real_inq;
  exception when others then v_real_inq := null; end;
  if v_real_inq is not null then
    if public.fn_inquiry_is_demo(v_real_inq) then v_bad := v_bad || ' ownerless-read-as-demo'; end if;
    if coalesce((public.fn_trade_reveal_allowed(v_real_inq)->>'allowed')::boolean, true) then v_bad := v_bad || ' real-reveal-allowed-on-demo-suppliers'; end if;
  end if;

  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK trade opens at 10 (odds 0.8327), stays open at 6, closes at 4, floor 4 refused, reveal refused under 5, fixture told without a message, visitor asked to register, launch gate per trade, 0 notifications; demo suppliers count for a demo customer only (real door closed, ownerless reveal %); tick %>>', case when v_real_inq is null then 'not insertable' else 'refused' end, v_tick;
end $probe$;
