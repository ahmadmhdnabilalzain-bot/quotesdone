-- PROBE for the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql. Seat: ceo. It always raises CHK<<...>>, so
-- every row it writes is rolled back. Its world is its own: qd.duty_fixtures = 'on' makes every reading see ONLY demo rows
-- (production's suppliers, requests and invitations are invisible to it, so no production row decides the outcome), its
-- people are ZZ DEMO at @example.invalid, the live targets are retired inside it, and it calls no sender: the founder's
-- summary is proved on its text and on both early returns, never sent. Run LOCALLY during work; on production only at release.
-- It proves: the proposal comes only from recorded demand (inquiries by trade and emirate, the waitlist), with its source,
-- and is confirmed by the CEO's run with a reason; coverage counts verified, matchable suppliers per trade and emirate (a
-- supplier with no stated emirate covers the UAE) and not a proposal; the funnel reads the stages from what is recorded;
-- the run orders the invitation seat (only while invitations are on), the sales engineer (the half-finished registrations)
-- and customer support (the held ones), each with its leads, a measured outcome and a due date, in the seat's Waiting on
-- you; it runs once a day; no second order on an open measure; a report closes an order and its measure is written beside
-- it; a met outcome nobody reported is closed a day later; the CEO sets a target with a reason; the summary says the day,
-- the decisions with their reasons, the limits, and asks nothing.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8); v_fail text := ''; v_r jsonb; v_t1 text; v_t2 text;
  v_cust uuid; v_sup bigint; v_stuck bigint; v_held bigint; v_inv bigint; v_at timestamptz; v_day date;
  v_o_inv bigint; v_o_stuck bigint; v_o_held bigint; v_txt text; v_n int; v_seat text;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  v_day := (now() at time zone 'Asia/Dubai')::date;
  v_at := (v_day + time '10:00') at time zone 'Asia/Dubai';
  delete from public.ceo_supply_decision where decided_on >= v_day;                   -- the probe's own days
  update public.supplier_coverage_target set status = 'retired', retired_at = now() where status <> 'retired';
  select code into v_t1 from public.taxonomy_trade where active order by code limit 1;
  select code into v_t2 from public.taxonomy_trade where active and code <> v_t1 order by code limit 1;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  update public.app_secrets set value = '3' where key = 'invite_daily_cap';
  insert into public.app_secrets (key, value) select 'invite_enabled', 'true' where not exists (select 1 from public.app_secrets where key = 'invite_enabled');
  insert into public.app_secrets (key, value) select 'invite_daily_cap', '3' where not exists (select 1 from public.app_secrets where key = 'invite_daily_cap');

  -- fixtures: demand (two requests in t1/Dubai, one in t2/Sharjah, one customer waiting for t2), one verified supplier in
  -- t1 covering Dubai, one half-finished registration, one held registration
  insert into public.customers (full_name, email) values ('ZZ DEMO Coverage Probe', 'coverage-probe-' || v_tag || '@example.invalid') returning id into v_cust;
  insert into public.inquiries (customer_id, category, emirate, summary, status, trades) values
    (v_cust, v_t1, 'Dubai', 'ZZ DEMO coverage probe 1', 'draft', array[v_t1]),
    (v_cust, v_t1, 'Dubai', 'ZZ DEMO coverage probe 2', 'draft', array[v_t1]),
    (v_cust, v_t2, 'Sharjah', 'ZZ DEMO coverage probe 3', 'draft', array[v_t2]);
  insert into public.customer_trade_waitlist (customer_id, channel, trade) values (v_cust, 'portal', v_t2);
  -- (his six mandatory items first, as a registered supplier has them: the gate refuses a verification without them)
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'zz-demo-coverage-probe/' || v_tag || '/licence.pdf'), ('supplier-docs', 'zz-demo-coverage-probe/' || v_tag || '/profile.pdf');
  insert into public.leads (company_name, email, phone, owner_phone_verified, owner_email_verified, signed_terms_path, license_doc_path, company_profile_doc_path, service_emirates)
  values ('ZZ DEMO Coverage Probe Supplier', 'coverage-probe-sup-' || v_tag || '@example.invalid', '+971500000000', true, true, 'zz-demo-coverage-probe/' || v_tag || '/terms.pdf',
          'zz-demo-coverage-probe/' || v_tag || '/licence.pdf', 'zz-demo-coverage-probe/' || v_tag || '/profile.pdf', array['Dubai']) returning id into v_sup;
  update public.leads set verified = true, approval_status = 'approved', approval_decided_by = 'sales_engineer' where id = v_sup;
  insert into public.supplier_capabilities (supplier_id, trades, confirmed_at) values (v_sup, array[v_t1], now());
  insert into public.leads (company_name, email, owner_email_verified, portal_updated_at)
  values ('ZZ DEMO Coverage Probe Started', 'coverage-probe-st-' || v_tag || '@example.invalid', true, now() - interval '5 days') returning id into v_stuck;
  insert into public.leads (company_name, email, registration_submitted_at)
  values ('ZZ DEMO Coverage Probe Held', 'coverage-probe-held-' || v_tag || '@example.invalid', now() - interval '3 days') returning id into v_held;
  insert into public.leads (company_name, email, invite_trades)
  values ('ZZ DEMO Coverage Probe Invitee', 'coverage-probe-inv-' || v_tag || '@example.invalid', array[v_t1]) returning id into v_inv;

  -- 1. THE PROPOSAL: from recorded demand only, each row saying where it comes from; not yet counted
  v_r := public.fn_supplier_coverage_target_propose();
  if (v_r->>'proposed_from_inquiries')::int <> 2 or (v_r->>'proposed_from_waitlist')::int <> 1 or (v_r->>'proposed_from_recruitment_decisions')::int <> 0
    then v_fail := v_fail || 'the proposal is not read from recorded demand: ' || v_r::text || '; '; end if;
  if (select source from public.supplier_coverage_target where trade = v_t1 and emirate = 'Dubai' and status = 'proposed') not like 'demand: 2 real inquiries in % / Dubai%trade_opening_rule.open_at_suppliers%'
    then v_fail := v_fail || 'a proposed row does not say where its numbers come from; '; end if;
  if (select target_suppliers from public.supplier_coverage_target where trade = v_t1 and emirate = 'Dubai' and status = 'proposed')
       is distinct from (select open_at_suppliers from public.trade_opening_rule where id = 1)
    then v_fail := v_fail || 'the proposed target is not the company''s opening level; '; end if;
  if (public.fn_supplier_coverage_target_propose()->>'proposed_from_inquiries')::int <> 0 then v_fail := v_fail || 'a second proposal duplicated rows; '; end if;
  v_r := public.fn_supplier_coverage(10);
  if (v_r->>'targets_proposed')::int <> 3 or (v_r->>'targets_confirmed')::int <> 0 or (v_r->>'target_suppliers')::int <> 0
    then v_fail := v_fail || 'a proposal counted before the CEO confirmed it: ' || v_r::text || '; '; end if;

  -- 2. THE FUNNEL, from what is recorded
  v_r := public.fn_supplier_funnel_reading(30);
  if (v_r->>'started_and_stopped')::int <> 1 or (v_r->>'submitted_and_held')::int <> 1 or (v_r->>'started')::int < 1
    then v_fail := v_fail || 'the funnel does not read the recorded stages: ' || v_r::text || '; '; end if;

  -- 3. THE RUN: confirms with a reason, reads, orders three seats with leads, outcome and date
  v_r := public.fn_ceo_grows_supply(v_at);
  if not coalesce((v_r->>'ran')::boolean, false) or (v_r->>'confirmed')::int <> 3 then v_fail := v_fail || 'the run did not confirm the proposal: ' || v_r::text || '; '; end if;
  if not exists (select 1 from public.ceo_supply_decision where decided_on = v_day and kind = 'confirm_targets' and length(reason) > 40)
    then v_fail := v_fail || 'the confirmation has no recorded reason; '; end if;
  v_r := public.fn_supplier_coverage(10);
  if (v_r->>'targets_confirmed')::int <> 3 or (v_r->>'covered_suppliers')::int <> 1
     or (select (g->>'verified')::int from jsonb_array_elements(v_r->'gaps') g where g->>'trade' = v_t1 and g->>'emirate' = 'Dubai') <> 1
     or (select (g->>'verified')::int from jsonb_array_elements(v_r->'gaps') g where g->>'trade' = v_t2 and g->>'emirate' = 'Sharjah') <> 0
    then v_fail := v_fail || 'coverage does not count the verified supplier where he works: ' || v_r::text || '; '; end if;
  v_seat := public.fn_ceo_invitation_seat();
  select id into v_o_inv from public.agent_actions where kind = 'handoff' and agent = v_seat and detail->>'type' = 'ceo.order' and detail->>'measure' = 'invitations' and status = 'pending';
  select id into v_o_stuck from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer' and detail->>'type' = 'ceo.order' and detail->>'measure' = 'stuck_followed_up' and status = 'pending';
  select id into v_o_held from public.agent_actions where kind = 'handoff' and agent = 'customer_support' and detail->>'type' = 'ceo.order' and detail->>'measure' = 'held_unblocked' and status = 'pending';
  if v_o_inv is null or v_o_stuck is null or v_o_held is null then v_fail := v_fail || 'the run did not order the three seats (' || coalesce(v_o_inv::text, '-') || ',' || coalesce(v_o_stuck::text, '-') || ',' || coalesce(v_o_held::text, '-') || '); ';
  else
    if (select (detail->>'target')::int from public.agent_actions where id = v_o_inv) <> least(29, 9)
       or (select detail->'trades' from public.agent_actions where id = v_o_inv) ->> 0 <> v_t1
       or (select detail->>'how' from public.agent_actions where id = v_o_inv) not like '%placement bar%'
      then v_fail := v_fail || 'the invitation order does not carry its trades, target and gates: ' || (select detail::text from public.agent_actions where id = v_o_inv) || '; '; end if;
    if (select detail->'lead_ids' from public.agent_actions where id = v_o_stuck) <> jsonb_build_array(v_stuck)
       or (select (detail->>'target')::int from public.agent_actions where id = v_o_stuck) <> 1
       or (select detail->'lead_ids' from public.agent_actions where id = v_o_held) <> jsonb_build_array(v_held)
       or (select detail->>'due_at' from public.agent_actions where id = v_o_held) is null
       or (select detail->>'how' from public.agent_actions where id = v_o_stuck) not like '%opted in%'
      then v_fail := v_fail || 'a registration order does not name its leads, outcome, date and channels; '; end if;
    if coalesce(public.fn_seat_pool_context('customer_support', null, 'internal')->>'block', '') not like '%Waiting on you%'
      then v_fail := v_fail || 'the order is not in the seat''s Waiting on you; '; end if;
  end if;
  if (select count(*) from public.ceo_supply_decision where decided_on = v_day and kind = 'order') <> 3 then v_fail := v_fail || 'an order has no recorded decision; '; end if;
  if (public.fn_ceo_grows_supply(v_at)->>'ran')::boolean then v_fail := v_fail || 'the loop ran twice in a day; '; end if;

  -- 4. THE NEXT DAY'S RUN (a new Dubai day, so a new order would have a new key): no second order on an open measure; the
  -- report closes an order and its measure is written beside it
  v_at := v_at + interval '1 day';
  update public.leads set registration_submitted_at = now() where id = v_stuck;
  v_r := public.fn_seat_reports_done(v_o_stuck, 'sales_engineer', 'Wrote to the probe supplier; he finished his registration.');
  if (select status from public.agent_actions where id = v_o_stuck) <> 'done' then v_fail := v_fail || 'the seat''s report did not close the order: ' || v_r::text || '; '; end if;
  update public.leads set approval_status = 'rejected' where id = v_held;     -- the held one is decided; nobody reports it
  insert into public.notifications (type, lead_id, to_email, subject, body, status, channel, sent_at)
  values ('supplier_invite', v_inv, 'coverage-probe-inv-' || v_tag || '@example.invalid', 'probe', 'ZZ DEMO probe invitation. Reply "stop" and we will not write again.', 'sent', 'email', now());
  v_r := public.fn_ceo_grows_supply(v_at);
  if (select count(*) from public.agent_actions where kind = 'handoff' and detail->>'type' = 'ceo.order' and detail->>'measure' = 'invitations' and status = 'pending') <> 1
    then v_fail := v_fail || 'a second invitation order while one is open; '; end if;
  if (select detail->'outcome_measured'->>'met' from public.agent_actions where id = v_o_stuck) is distinct from 'true'
     or not exists (select 1 from public.ceo_supply_decision where handoff_id = v_o_stuck and kind = 'order_measured')
    then v_fail := v_fail || 'the reported order''s measure is not written beside the report; '; end if;
  if (select detail->'reading_now'->>'value' from public.agent_actions where id = v_o_inv) is distinct from '1'
    then v_fail := v_fail || 'the invitation order does not read the outbox''s sends: ' || coalesce((select detail->>'reading_now' from public.agent_actions where id = v_o_inv), '-') || '; '; end if;
  if (select status from public.agent_actions where id = v_o_held) <> 'pending' or not (select detail ? 'met_at' from public.agent_actions where id = v_o_held)
    then v_fail := v_fail || 'a met order was closed before the seat had a day to report, or its met time is not kept; '; end if;
  -- an hour after it was met, still unreported: left to the seat
  update public.agent_actions set detail = detail || jsonb_build_object('met_at', (now() - interval '1 hour')::text) where id = v_o_held;
  delete from public.ceo_supply_decision where kind = 'run';
  perform public.fn_ceo_grows_supply(v_at);
  if (select status from public.agent_actions where id = v_o_held) <> 'pending' then v_fail := v_fail || 'a met order was closed an hour after it was met; '; end if;
  -- a day later, still unreported: closed by its measure, on the record
  update public.agent_actions set detail = detail || jsonb_build_object('met_at', (now() - interval '2 days')::text) where id = v_o_held;
  delete from public.ceo_supply_decision where kind = 'run';
  perform public.fn_ceo_grows_supply(v_at);
  if (select status || ' ' || coalesce(evidence->>'outcome', '') from public.agent_actions where id = v_o_held) is distinct from 'done met'
     or not exists (select 1 from public.ceo_supply_decision where handoff_id = v_o_held and kind = 'order_closed')
    then v_fail := v_fail || 'a met order nobody reported was not closed by its measure; '; end if;

  -- 5. INVITATIONS OFF: no invitation order, and the reason is recorded
  update public.agent_actions set status = 'done', decided_at = now(), evidence = jsonb_build_object('not_cited', jsonb_build_object('reason', 'probe', 'by', 'probe'))
   where id = v_o_inv;
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  v_at := v_at + interval '1 day';
  perform public.fn_ceo_grows_supply(v_at);
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'ceo.order' and detail->>'measure' = 'invitations' and status = 'pending')
     or not exists (select 1 from public.ceo_supply_decision where decided_on = (v_at at time zone 'Asia/Dubai')::date and kind = 'no_order' and reason like 'invitations are switched off%')
    then v_fail := v_fail || 'an invitation order went out while invitations were off, or the reason is not recorded; '; end if;

  -- 6. THE CEO SETS A TARGET with a reason
  if coalesce((public.fn_ceo_sets_coverage_target(v_t1, 'Dubai', 12, 'short')->>'ok')::boolean, true) then v_fail := v_fail || 'a target changed with no reason; '; end if;
  v_r := public.fn_ceo_sets_coverage_target(v_t1, 'Dubai', 12, 'probe: two requests a month in Dubai need more choice than ten');
  if not coalesce((v_r->>'ok')::boolean, false) or (select target_suppliers from public.supplier_coverage_target where trade = v_t1 and emirate = 'Dubai' and status = 'confirmed') <> 12
     or (select count(*) from public.supplier_coverage_target where trade = v_t1 and emirate = 'Dubai' and status = 'retired') < 1
    then v_fail := v_fail || 'the CEO could not set a target: ' || v_r::text || '; '; end if;

  -- 7. THE FOUNDER'S SUMMARY: the day, the decisions with their reasons, the limits; nothing asked; never sent by this probe
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, evidence, decided_at, decided_by)
  values ('ceo', 'handoff', 'done', 'ceo.authority probe ' || v_tag,
          jsonb_build_object('type', 'ceo.authority', 'from', 'marketing', 'to', 'ceo', 'what', 'boost the probe post ' || v_tag),
          'ceo_grant_once', 'ceo.authority:probe:' || v_tag,
          jsonb_build_object('ceo_decision', jsonb_build_object('choice', 'refuse', 'reason', 'The probe post has no audience yet ' || v_tag, 'decided_at', now()),
                             'not_cited', jsonb_build_object('reason', 'probe', 'by', 'probe')), now(), 'ceo');
  v_txt := public.fn_ceo_daily_summary_text(now() - interval '1 day');
  if v_txt not like 'SUPPLIER COVERAGE (founder ledger 1701): 1 of %' or v_txt not like '%FUNNEL, 30 days:%' or v_txt not like '%COMPANY LIMITS: AED%'
     or v_txt not like '%marketing asked boost the probe post ' || v_tag || ': refuse - The probe post has no audience yet ' || v_tag || '%'
     or v_txt not like '%supply confirm_targets%' or v_txt not like '%supply set_target%' or v_txt not like '%Nothing here waits on you.'
    then v_fail := v_fail || 'the summary does not say the day and the decisions: ' || left(v_txt, 900) || '; '; end if;
  if v_txt ~* '(please (approve|confirm)|your approval|reply (yes|with)|do you (approve|agree))' then v_fail := v_fail || 'the summary asks the founder something; '; end if;
  if (public.fn_ceo_daily_summary_to_the_founder((v_day + time '06:30') at time zone 'Asia/Dubai')->>'reason') <> 'before 07:00 Dubai'
    then v_fail := v_fail || 'the summary would go before 07:00; '; end if;
  insert into public.founder_alerts (level, event, detail, channel, dedupe_key) values ('info', 'probe', 'probe', 'email', 'ceo_daily_summary:' || to_char(v_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'));
  if (public.fn_ceo_daily_summary_to_the_founder(v_at)->>'reason') <> 'already told today' then v_fail := v_fail || 'the summary would go twice in a day; '; end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: coverage % >>', public.fn_supplier_coverage(3)->>'coverage_pct';
end $probe$;
