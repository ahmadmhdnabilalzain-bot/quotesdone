-- PROBE: the sales engineer forecasts 30/90 days of demand. Pure probe, no DDL: run AFTER its .sql in the
-- SAME query through node scripts/qsql.mjs; it always ends in raise exception CHK<<...>>, so nothing survives.
-- It touches no person: searches and one ZZ DEMO-worded inquiry with no customer, written and rolled back.
-- PROBE OK only if:
--   1. searches are counted for the trade in Dubai and in the UAE roll-up, labelled 'estimate';
--   2. searches ALONE move nothing: three identical searches leave a deferred gap deferred (review of #1182:
--      an anonymous visitor could otherwise start supplier recruitment);
--   3. one real (non-demo) inquiry does move the below-target gap to 'recruit' by rule:forecast_demand;
--   4. demo inquiries (customers.is_demo) are not counted anywhere;
--   5. fn_demand_search_record refuses a malformed category and drops an unknown emirate.
do $probe$
declare v_trade text; v_trade2 text; f record; v_fail text := ''; v_demo int; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  select g.trade into v_trade from public.supply_gap g where g.emirate = 'UAE' and g.status = 'deferred' and g.matchable < g.target order by g.trade limit 1;
  select g.trade into v_trade2 from public.supply_gap g where g.emirate = 'UAE' and g.status = 'deferred' and g.matchable < g.target and g.trade <> v_trade order by g.trade limit 1;
  insert into public.supply_gap (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, status, measured_at)
  values (v_trade, 'Dubai', 0, 10, 0, 0, 0, 'deferred', now()), (v_trade2, 'Dubai', 0, 10, 0, 0, 0, 'deferred', now())
  on conflict (trade, emirate) do update set status = 'deferred', matchable = 0, target = 10;

  insert into public.demand_search (category, trades, emirate) select v_trade, array[v_trade], 'Dubai' from generate_series(1, 3);
  perform public.fn_demand_search_record('Bad Category!', 'Dubai');
  perform public.fn_demand_search_record(v_trade, 'Atlantis');
  if exists (select 1 from public.demand_search where category = 'Bad Category!') then v_fail := v_fail || ' malformed category kept;'; end if;
  if not exists (select 1 from public.demand_search where category = v_trade and emirate is null) then v_fail := v_fail || ' unknown emirate not dropped;'; end if;

  insert into public.inquiries (category, trades, emirate, raw_input, status)
  values (v_trade2, array[v_trade2], 'Dubai', 'ZZ DEMO probe inquiry', 'quoted');

  perform public.fn_demand_forecast_tick();

  select * into f from public.demand_forecast where run_on = v_today and trade = v_trade and emirate = 'Dubai';
  if f is null then v_fail := v_fail || ' no Dubai row;';
  else
    if f.searches_30d <> 3 then v_fail := v_fail || ' searches_30d=' || f.searches_30d || ';'; end if;
    if f.basis <> 'estimate' then v_fail := v_fail || ' basis;'; end if;
    if f.acted is not null then v_fail := v_fail || ' searches alone acted;'; end if;
  end if;
  if not exists (select 1 from public.demand_forecast where run_on = v_today and trade = v_trade and emirate = 'UAE' and searches_30d = 4)
    then v_fail := v_fail || ' UAE roll-up wrong;'; end if;
  if not exists (select 1 from public.supply_gap where trade = v_trade and emirate = 'Dubai' and status = 'deferred')
    then v_fail := v_fail || ' 3 identical searches moved the gap;'; end if;
  if not exists (select 1 from public.supply_gap where trade = v_trade2 and emirate = 'Dubai' and status = 'recruit' and decided_by = 'rule:forecast_demand')
    then v_fail := v_fail || ' a real inquiry did not start recruitment;'; end if;
  if not exists (select 1 from public.demand_forecast where run_on = v_today and trade = v_trade2 and emirate = 'Dubai' and acted is not null)
    then v_fail := v_fail || ' act not recorded;'; end if;

  select count(*) into v_demo from public.demand_forecast f2
   where f2.run_on = v_today and f2.inquiries_90d > 0 and f2.trade <> v_trade2;
  if v_demo > 0 and not exists (select 1 from public.inquiries i left join public.customers c on c.id = i.customer_id
                                 where not coalesce(c.is_demo, false) and i.created_at > now() - interval '90 days' and i.category <> v_trade2)
    then v_fail := v_fail || ' demo inquiries counted;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK searched=' || v_trade || ' inquired=' || v_trade2 else 'PROBE FAILED:' || v_fail end;
end $probe$;
