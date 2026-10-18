-- SUPPLY GAP DEMAND NEVER COUNTS A DEMO REQUEST (sales_engineer, 5 Oct 2026; found by the #1192 market report review).
-- Assigned: sales_engineer
--
-- MEASURED 5 Oct 2026: fn_sales_engineer_supply_gap counted every inquiry of the last 90 days as demand. The only 3
-- inquiries on production are founder-demo requests (customers.is_demo, @example.invalid), and they had moved five gaps
-- to recruit by rule:customer_waiting on 24 Sep 2026: painting/Sharjah, painting/UAE, gypsum/Abu Dhabi, gypsum/Dubai,
-- gypsum/UAE. That rule is how REAL supplier recruitment starts (marketing.gap_recruitment_plans, the recruitment
-- funnel), so a founder demo could start real outreach.
--
-- THE FIX: demand and short_open read only requests whose customer is not a fixture
-- (fn_seat_clock_customer_is_fixture, the predicate fn_sales_engineer_stalled_inquiry_rescue already uses). And the
-- five demo-only gaps are settled the proper way, by the routine itself on its next run: a gap held in recruit by
-- rule:customer_waiting with no counted request left goes back to open and is decided again like any gap nobody waits
-- on (deferred by rule when no lead is left, otherwise filed for the sales engineer's reasoning, held under the model
-- hold). Nothing is back-dated or deleted.
--
-- Based on the canonical body in a_supply_gap_with_no_leads_left_is_deferred_by_rule.sql (MANIFEST 1865); only the inq
-- filter, the settle step and one return key change.
--
-- prevented by: scripts/checks/a_demo_request_is_never_supply_gap_demand.test.mjs

create or replace function public.fn_sales_engineer_supply_gap(p_reason_limit integer default 10)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_target int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  g record; v_filed int := 0; v_rule int; v_closed int; v_reopened int; v_settled int; v_month text := to_char(now(), 'YYYY-MM');
  v_emirates text[] := array['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
begin
  with sup as materialized (   -- every matchable supplier with his trades and the emirates he states (none stated = UAE-wide)
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
  ), inq as materialized (
    select i.id, i.emirate, i.trades, i.created_at,
           (i.created_at > now() - interval '30 days' and i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
            and (select count(*) from public.quotes q where q.inquiry_id = i.id) < 3) as short
      from public.inquiries i left join public.customers c on c.id = i.customer_id
     where i.created_at > now() - interval '90 days'
       -- DEMO IS NEVER DEMAND: a fixture customer's request never starts real recruitment (the predicate the
       -- stalled-inquiry rescue already uses)
       and not coalesce(public.fn_seat_clock_customer_is_fixture(c), false)
  ), pool as materialized (
    select t, l.emirate, count(*) as n from public.leads l, unnest(l.invite_trades) t
     where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and coalesce(l.is_demo, false) = false
     group by t, l.emirate
  ), keys as (
    select tt.code as trade, 'UAE'::text as emirate from public.taxonomy_trade tt where tt.active
    union
    select distinct t, i.emirate from inq i, unnest(i.trades) t
     where i.emirate = any(v_emirates) and t in (select code from public.taxonomy_trade where active)
  ), m as (
    select k.trade, k.emirate,
           (select count(*) from sup s where k.trade = any(s.trades)
             and (k.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(k.emirate) = any(s.stated)))::int as matchable,
           (select count(*) from inq i where k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as demand,
           (select count(*) from inq i where i.short and k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as short,
           (select coalesce(sum(p.n), 0) from pool p where p.t = k.trade and (k.emirate = 'UAE' or p.emirate = k.emirate))::int as pool
      from keys k
  )
  insert into public.supply_gap as sg (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, measured_at)
  select trade, emirate, matchable, v_target, demand, short, pool, now() from m
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target,
    demand_90d = excluded.demand_90d, short_open = excluded.short_open, uninvited_pool = excluded.uninvited_pool, measured_at = now();

  -- An area row that no counted request names any more (its only requests were demo) was not re-measured above:
  -- it has no demand now, not the demand it had last run.
  update public.supply_gap set demand_90d = 0, short_open = 0, measured_at = now()
   where measured_at < now() and (demand_90d <> 0 or short_open <> 0);

  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  get diagnostics v_closed = row_count;
  update public.supply_gap set status = 'open', opened_at = now(), closed_at = null, decided_by = null, decided_at = null, held_id = null
   where (status = 'closed' and matchable < target) or (status = 'deferred' and decided_at < now() - interval '30 days');
  get diagnostics v_reopened = row_count;

  -- A decision whose reasoning failed five times goes back to open, so it is filed again (fn_reason_hold reopens it).
  update public.supply_gap sgp set status = 'open'
   where sgp.status = 'deciding' and exists (select 1 from public.reasoning_held_question h where h.id = sgp.held_id and h.status in ('failed', 'expired'));

  -- A RULE WHOSE CUSTOMER IS GONE IS UNDONE: a gap recruited for because a customer was waiting, where no counted
  -- (non-demo) request remains, goes back to open and is decided again below like any gap nobody waits on.
  update public.supply_gap set status = 'open', decided_by = null, decided_at = null, held_id = null
   where status = 'recruit' and decided_by = 'rule:customer_waiting' and short_open = 0 and demand_90d = 0;
  get diagnostics v_settled = row_count;

  -- A CUSTOMER IS ALREADY WAITING: recruited for at once, by rule. No judgement to make, so nothing waits on one.
  update public.supply_gap set status = 'recruit', decided_by = 'rule:customer_waiting', decided_at = now()
   where status in ('open', 'deciding', 'deferred') and (short_open > 0 or demand_90d > 0);
  get diagnostics v_rule = row_count;

  -- NO UNINVITED LEAD LEFT: nobody for marketing to recruit, so "defer" is the only answer - by rule, at no cost.
  update public.supply_gap set status = 'deferred', decided_by = 'rule:no_uninvited_leads', decided_at = now()
   where status = 'open' and uninvited_pool = 0;

  -- NOBODY IS WAITING: recruit now or defer is a judgement, reasoned by the sales engineer (stakes high).
  for g in
    select s.*, tt.label from public.supply_gap s join public.taxonomy_trade tt on tt.code = s.trade
     where s.status = 'open' order by s.uninvited_pool desc, s.matchable, s.trade limit greatest(0, least(coalesce(p_reason_limit, 10), 50))
  loop
    update public.supply_gap set status = 'deciding', held_id = public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.supply_gap',
      'Supplier supply for one trade is below the level at which we open requests to customers. Nobody is waiting on it '
        || 'today. Decide whether marketing should spend recruitment effort on this trade and area now, or defer it for a month.',
      '[{"id":"recruit","meaning":"recruit suppliers for this trade and area now"},{"id":"defer","meaning":"defer for a month; other gaps matter more"}]'::jsonb,
      jsonb_build_object('trade', g.trade, 'trade_label', g.label, 'area', g.emirate, 'matchable_suppliers', g.matchable,
                         'suppliers_needed_to_open', g.target, 'uninvited_leads_in_pool', g.uninvited_pool, 'requests_90d', g.demand_90d),
      jsonb_build_object('trade', g.trade, 'emirate', g.emirate), 'supply_gap:' || g.trade || ':' || g.emirate || ':' || v_month)
     where trade = g.trade and emirate = g.emirate;
    v_filed := v_filed + 1;
  end loop;

  return jsonb_build_object('target', v_target, 'closed', v_closed, 'reopened', v_reopened, 'recruit_by_rule', v_rule, 'customer_rule_undone', v_settled,
    'filed_for_reasoning', v_filed,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $fn$;
revoke execute on function public.fn_sales_engineer_supply_gap(integer) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supply_gap(integer) to service_role;

