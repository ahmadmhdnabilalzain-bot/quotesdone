-- PROBE: the sales engineer forecasts 30/90 days of demand. Pure probe, no DDL: run AFTER its .sql in the
-- SAME query through node scripts/qsql.mjs; it always ends in raise exception CHK<<...>>, so nothing survives.
-- It touches no person: three brief-box searches for one deferred trade in Dubai, written and rolled back.
-- PROBE OK only if:
--   1. the three searches are counted for that trade in Dubai and in the UAE roll-up, labelled 'estimate';
--   2. the deferred supply_gap row below target is moved to 'recruit' by rule:forecast_demand, and the
--      forecast row records that it acted;
--   3. demo inquiries (customers.is_demo) are not counted anywhere;
--   4. fn_demand_search_record refuses a malformed category and drops an unknown emirate.
do $probe$
declare v_trade text; f record; v_fail text := ''; v_demo int;
begin
  select g.trade into v_trade from public.supply_gap g
   where g.emirate = 'Dubai' and g.status = 'deferred' and g.matchable < g.target order by g.trade limit 1;
  if v_trade is null then
    select g.trade into v_trade from public.supply_gap g where g.emirate = 'UAE' and g.status = 'deferred' and g.matchable < g.target order by g.trade limit 1;
    insert into public.supply_gap (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, status, measured_at)
    values (v_trade, 'Dubai', 0, 10, 0, 0, 0, 'deferred', now()) on conflict (trade, emirate) do nothing;
  end if;
  insert into public.demand_search (category, trades, emirate) select v_trade, array[v_trade], 'Dubai' from generate_series(1, 3);
  perform public.fn_demand_search_record('Bad Category!', 'Dubai');
  perform public.fn_demand_search_record(v_trade, 'Atlantis');
  if exists (select 1 from public.demand_search where category = 'Bad Category!') then v_fail := v_fail || ' malformed category kept;'; end if;
  if not exists (select 1 from public.demand_search where category = v_trade and emirate is null) then v_fail := v_fail || ' unknown emirate not dropped;'; end if;

  perform public.fn_demand_forecast_tick();

  select * into f from public.demand_forecast where run_on = (now() at time zone 'Asia/Dubai')::date and trade = v_trade and emirate = 'Dubai';
  if f is null then v_fail := v_fail || ' no Dubai row;';
  else
    if f.searches_30d <> 3 then v_fail := v_fail || ' searches_30d=' || f.searches_30d || ';'; end if;
    if f.basis <> 'estimate' then v_fail := v_fail || ' basis;'; end if;
    if f.acted is null then v_fail := v_fail || ' did not act;'; end if;
  end if;
  if not exists (select 1 from public.demand_forecast where run_on = (now() at time zone 'Asia/Dubai')::date and trade = v_trade and emirate = 'UAE' and searches_30d = 4)
    then v_fail := v_fail || ' UAE roll-up wrong;'; end if;
  if not exists (select 1 from public.supply_gap where trade = v_trade and emirate = 'Dubai' and status = 'recruit' and decided_by = 'rule:forecast_demand')
    then v_fail := v_fail || ' supply_gap not recruit;'; end if;

  select count(*) into v_demo from public.demand_forecast f2
   where f2.run_on = (now() at time zone 'Asia/Dubai')::date and f2.inquiries_90d > 0
     and not exists (select 1 from public.inquiries i left join public.customers c on c.id = i.customer_id
                      where not coalesce(c.is_demo, false) and i.created_at > now() - interval '90 days');
  if v_demo > 0 then v_fail := v_fail || ' demo inquiries counted;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK trade=' || v_trade else 'PROBE FAILED:' || v_fail end;
end $probe$;
