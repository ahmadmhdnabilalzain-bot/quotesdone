-- PROBE: the sales engineer forecasts 30/90 days of demand. Pure probe, no DDL: run AFTER its .sql in the
-- SAME query through node scripts/qsql.mjs; it always ends in raise exception CHK<<...>>, so nothing survives.
-- It touches no person: two probe customers with no reachable address (one plainly a fixture: ZZ DEMO name and an
-- @example.invalid email; the other a non-fixture with no email or phone at all), their inquiries, searches and
-- five Dubai supply-gap rows, all written and rolled back.
-- PROBE OK only if:
--   1. searches are counted for the trade in Dubai and in the UAE roll-up, labelled 'estimate';
--   2. searches ALONE move nothing: three identical searches leave a deferred gap deferred (review of #1182:
--      an anonymous visitor could otherwise start supplier recruitment);
--   3. one inquiry from a NON-FIXTURE customer moves its below-target gap to 'recruit' by rule:forecast_demand;
--   4. an inquiry from a FIXTURE customer (ZZ DEMO / @example.invalid) and an inquiry with NO
--      customer are not counted and move nothing (review of #1182, 26 Oct 2026: the convention of
--      a_demo_request_is_never_supply_gap_demand.sql);
--   5. a gap with nobody left to invite, deferred by rule:no_uninvited_leads, stays deferred by that rule;
--   6. fn_sales_engineer_supply_gap releases a rule:forecast_demand gap once no forecast shows demand there;
--   7. fn_demand_search_record refuses a malformed category and drops an unknown emirate, and a search older
--      than 90 days is purged by the tick.
do $probe$
declare
  t text[]; f record; v_fail text := ''; v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_real uuid; v_fixture uuid; v_inq uuid;
begin
  select array_agg(code order by code) into t from (select code from public.taxonomy_trade where active order by code limit 5) x;
  if coalesce(cardinality(t), 0) < 5 then raise exception 'CHK<<PROBE FAILED: fewer than 5 active trades>>'; end if;
  -- t[1] searched only, t[2] real customer, t[3] fixture customer, t[4] no customer, t[5] real customer but no lead left
  insert into public.supply_gap (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, status, decided_by, measured_at)
  select tr, 'Dubai', 0, 10, 0, 0, case when tr = t[5] then 0 else 5 end, 'deferred',
         case when tr = t[5] then 'rule:no_uninvited_leads' else 'rule:nobody_waiting' end, now()
    from unnest(t) tr
  on conflict (trade, emirate) do update set status = 'deferred', matchable = 0, target = 10,
    uninvited_pool = excluded.uninvited_pool, decided_by = excluded.decided_by, decided_at = now();

  insert into public.customers (full_name) values ('Forecast probe customer') returning id into v_real;
  insert into public.customers (full_name, email) values ('ZZ DEMO forecast probe', 'forecast-probe@example.invalid') returning id into v_fixture;
  if exists (select 1 from public.customers c where c.id = v_real and public.fn_seat_clock_customer_is_fixture(c))
    then v_fail := v_fail || ' the real probe customer reads as a fixture;'; end if;
  -- customers.is_demo is a GENERATED column on production (fn_is_demo_email / fn_is_demo_phone / a ZZ DEMO name), so a
  -- fixture customer always has it set and "a fixture without is_demo" cannot exist there. Asserting it did fail the
  -- production run of 27 Oct (independent review of #1182); the fixture predicate is what is under test, so assert that.
  if not exists (select 1 from public.customers c where c.id = v_fixture and public.fn_seat_clock_customer_is_fixture(c))
    then v_fail := v_fail || ' the fixture probe customer does not read as a fixture;'; end if;

  insert into public.demand_search (category, trades, emirate) select t[1], array[t[1]], 'Dubai' from generate_series(1, 3);
  insert into public.demand_search (category, trades, emirate, searched_at) values (t[1], array[t[1]], 'Dubai', now() - interval '91 days');
  perform public.fn_demand_search_record('Bad Category!', 'Dubai');
  perform public.fn_demand_search_record(t[1], 'Atlantis');
  if exists (select 1 from public.demand_search where category = 'Bad Category!') then v_fail := v_fail || ' malformed category kept;'; end if;
  if not exists (select 1 from public.demand_search where category = t[1] and emirate is null) then v_fail := v_fail || ' unknown emirate not dropped;'; end if;

  insert into public.inquiries (category, trades, emirate, raw_input, status, customer_id)
  values (t[2], array[t[2]], 'Dubai', 'forecast probe inquiry', 'quoted', v_real) returning id into v_inq;
  insert into public.inquiries (category, trades, emirate, raw_input, status, customer_id)
  values (t[3], array[t[3]], 'Dubai', 'ZZ DEMO forecast probe inquiry', 'quoted', v_fixture),
         (t[4], array[t[4]], 'Dubai', 'forecast probe inquiry with no customer', 'quoted', null),
         (t[5], array[t[5]], 'Dubai', 'forecast probe inquiry, no lead left', 'quoted', v_real);

  perform public.fn_demand_forecast_tick();

  -- 1, 2 searches
  select * into f from public.demand_forecast where run_on = v_today and trade = t[1] and emirate = 'Dubai';
  if f is null then v_fail := v_fail || ' no Dubai row;';
  else
    if f.searches_30d <> 3 then v_fail := v_fail || ' searches_30d=' || f.searches_30d || ';'; end if;
    if f.basis <> 'estimate' then v_fail := v_fail || ' basis;'; end if;
    if f.acted is not null then v_fail := v_fail || ' searches alone acted;'; end if;
  end if;
  if not exists (select 1 from public.demand_forecast where run_on = v_today and trade = t[1] and emirate = 'UAE' and searches_30d = 4)
    then v_fail := v_fail || ' UAE roll-up wrong;'; end if;
  if not exists (select 1 from public.supply_gap where trade = t[1] and emirate = 'Dubai' and status = 'deferred')
    then v_fail := v_fail || ' 3 identical searches moved the gap;'; end if;
  if exists (select 1 from public.demand_search where searched_at < now() - interval '90 days')
    then v_fail := v_fail || ' a search older than 90 days survived the tick;'; end if;
  -- 3 a real customer's inquiry acts
  if not exists (select 1 from public.supply_gap where trade = t[2] and emirate = 'Dubai' and status = 'recruit' and decided_by = 'rule:forecast_demand')
    then v_fail := v_fail || ' a real inquiry did not start recruitment;'; end if;
  if not exists (select 1 from public.demand_forecast where run_on = v_today and trade = t[2] and emirate = 'Dubai' and acted is not null and inquiries_30d = 1)
    then v_fail := v_fail || ' act not recorded;'; end if;
  -- 4 fixture and customer-less inquiries are not demand
  if exists (select 1 from public.demand_forecast where run_on = v_today and trade in (t[3], t[4]) and emirate = 'Dubai' and inquiries_90d > 0)
    then v_fail := v_fail || ' a fixture or customer-less inquiry was counted;'; end if;
  if exists (select 1 from public.supply_gap where trade in (t[3], t[4]) and emirate = 'Dubai' and status <> 'deferred')
    then v_fail := v_fail || ' a fixture or customer-less inquiry moved its gap;'; end if;
  -- 5 nobody left to invite
  if not exists (select 1 from public.supply_gap where trade = t[5] and emirate = 'Dubai' and status = 'deferred' and decided_by = 'rule:no_uninvited_leads')
    then v_fail := v_fail || ' a gap with no lead left was recruited for;'; end if;

  -- 6 released: the real request goes, no forecast shows demand any more, the canonical tick undoes the rule
  update public.inquiries set customer_id = v_fixture where id = v_inq;   -- now a fixture request: not demand
  delete from public.demand_forecast where run_on = v_today and trade = t[2];
  perform public.fn_sales_engineer_supply_gap();
  if exists (select 1 from public.supply_gap where trade = t[2] and emirate = 'Dubai' and (status = 'recruit' or decided_by = 'rule:forecast_demand'))
    then v_fail := v_fail || ' a forecast recruitment was not released;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK searched=' || t[1] || ' inquired=' || t[2] else 'PROBE FAILED:' || v_fail end;
end $probe$;
