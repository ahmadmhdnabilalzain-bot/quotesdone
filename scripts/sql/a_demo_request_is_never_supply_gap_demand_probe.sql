-- PROBE: a demo request is never supply-gap demand. Pure probe, no DDL: run AFTER its .sql in the SAME query through
-- node scripts/qsql.mjs; it always ends in raise exception CHK<<...>>, so nothing survives. Contacts no one
-- (p_reason_limit 0: nothing is filed for reasoning inside the probe).
-- PROBE OK only if:
--   1. a NEW ZZ DEMO request (an existing fixture customer) for a deferred trade and area moves nothing;
--   2. the five gaps the founder-demo requests put in recruit (rule:customer_waiting) are no longer held there and
--      count 0 demand;
--   3. a non-demo request (no customer) for another deferred gap still recruits it by rule:customer_waiting.
do $probe$
declare v_demo_cust uuid; v_t1 text; v_t2 text; v_fail text := ''; v jsonb; v_left int;
begin
  select i.customer_id into v_demo_cust from public.inquiries i join public.customers c on c.id = i.customer_id
   where c.is_demo and c.email like '%@example.invalid' limit 1;
  select trade into v_t1 from public.supply_gap where emirate = 'UAE' and status = 'deferred' and matchable < target order by trade limit 1;
  select trade into v_t2 from public.supply_gap where emirate = 'UAE' and status = 'deferred' and matchable < target and trade <> v_t1 order by trade limit 1;

  insert into public.inquiries (customer_id, category, trades, emirate, raw_input, status)
  values (v_demo_cust, v_t1, array[v_t1], 'Dubai', 'ZZ DEMO probe request', 'quoted'),
         (null,        v_t2, array[v_t2], 'Dubai', 'ZZ DEMO probe request without a customer', 'quoted');

  v := public.fn_sales_engineer_supply_gap(0);

  if exists (select 1 from public.supply_gap where trade = v_t1 and status = 'recruit') then v_fail := v_fail || ' a demo request started recruitment;'; end if;
  if exists (select 1 from public.supply_gap where trade = v_t1 and demand_90d > 0) then v_fail := v_fail || ' demo counted as demand;'; end if;
  select count(*) into v_left from public.supply_gap
   where (trade, emirate) in (('painting', 'Sharjah'), ('painting', 'UAE'), ('gypsum', 'Abu Dhabi'), ('gypsum', 'Dubai'), ('gypsum', 'UAE'))
     and (status = 'recruit' or demand_90d > 0);
  if v_left > 0 then v_fail := v_fail || ' ' || v_left || ' demo-only gap(s) still recruit or count demand;'; end if;
  if not exists (select 1 from public.supply_gap where trade = v_t2 and emirate = 'Dubai' and status = 'recruit' and decided_by = 'rule:customer_waiting')
    then v_fail := v_fail || ' a real request no longer recruits;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK demo=' || v_t1 || ' real=' || v_t2 || ' undone=' || coalesce(v->>'customer_rule_undone', '?')
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
