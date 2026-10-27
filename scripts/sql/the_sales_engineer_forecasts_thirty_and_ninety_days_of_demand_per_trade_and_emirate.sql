-- THE SALES ENGINEER FORECASTS 30 AND 90 DAYS OF DEMAND PER TRADE AND EMIRATE (backlog T4, ledger 1019).
-- Assigned: sales_engineer (owns inquiries and the supply gap; seat-ownership map, 24 Sep 2026).
--
-- Measured 5 Oct 2026 before writing this: nothing forecast demand per trade. fn_customer_forecast is per
-- customer, fn_ceo_target_forecast is per target, fn_accountant_cash_forecast is cash. No table recorded what
-- visitors search for: the homepage brief box (public_site route_brief) routes a visitor's words to a trade
-- and kept nothing. supply_gap counts the last 90 days of inquiries, demo ones included.
--
-- What this adds:
--   demand_search          one row per brief-box text the router recognised (trade + emirate, no text kept).
--   demand_forecast        one row per run, trade and emirate (and a 'UAE' roll-up): 30/90-day counts,
--                          the projection, basis = 'estimate' always (a CHECK), method and sample size.
--   fn_demand_forecast_tick  code only, no model. Only an inquiry with a customer who is not a fixture is counted
--                          (fn_seat_clock_customer_is_fixture: is_demo, a ZZ DEMO name or an @example.invalid email),
--                          the rule a_demo_request_is_never_supply_gap_demand.sql set for the supply gap.
--                          demand_search rows older than 90 days are purged on every run: nothing reads them.
--   seat_duty sales_engineer.demand_forecast, daily.
--
-- THE METHOD (stated in every row): daily rate r30 over the last 30 days and r90 over the last 90; the
-- blended rate 0.6*r30 + 0.4*r90 times 30 and 90 days. Fewer than 10 inquiries in 90 days is
-- sufficient = false and the row says 'insufficient_data' - it still projects, labelled. Searches are
-- projected the same way in their own columns and never added to inquiries: no conversion rate is known
-- yet, and inventing one would be a number nobody measured.
--
-- IT ACTS: a trade and area whose projected 90-day demand is >= 1 inquiry (searches never act on their own:
-- they are anonymous, and public_site records at most 5 per IP per day), while its supply_gap row is below target and not already being recruited for, is
-- moved to 'recruit' (decided_by 'rule:forecast_demand') - the same path a waiting customer takes, so
-- marketing.gap_recruitment_plans and the recruitment funnel start before the customer arrives.
-- It never recruits where nobody is left to invite (uninvited_pool = 0) and never overrides a deferral made by
-- rule:no_uninvited_leads (review of #1182, 26 Oct 2026).
--
-- IT IS RELEASED: fn_sales_engineer_supply_gap (redefined at the end of this file from its canonical
-- a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model.sql, MANIFEST 1951; only the release
-- step is new) sends a rule:forecast_demand gap back to 'open' once no forecast from the last two days still
-- shows demand there, so it is decided again like any gap nobody waits on. Before this, the canonical release
-- undid only rule:customer_waiting and a forecast recruitment was permanent (review of #1182, 26 Oct 2026).

create table if not exists public.demand_search (
  id          bigserial primary key,
  category    text not null,
  trades      text[] not null default '{}',
  emirate     text,
  source      text not null default 'route_brief' check (source in ('route_brief', 'fixture')),
  searched_at timestamptz not null default now()
);
create index if not exists demand_search_at_idx on public.demand_search (searched_at);
alter table public.demand_search enable row level security;
drop policy if exists demand_search_service_role_only on public.demand_search;
create policy demand_search_service_role_only on public.demand_search as permissive for all to public using (false) with check (false);
revoke all on public.demand_search from anon, authenticated;
revoke all on sequence public.demand_search_id_seq from anon, authenticated;

create table if not exists public.demand_forecast (
  run_on          date not null,
  trade           text not null,
  emirate         text not null,
  inquiries_30d   int not null,
  inquiries_90d   int not null,
  searches_30d    int not null,
  searches_90d   int not null,
  forecast_30d    numeric not null,
  forecast_90d    numeric not null,
  searches_forecast_30d numeric not null,
  searches_forecast_90d numeric not null,
  basis           text not null default 'estimate' check (basis = 'estimate'),
  method          text not null,
  sufficient_data boolean not null,
  matchable       int,
  target          int,
  acted           text,
  created_at      timestamptz not null default now(),
  primary key (run_on, trade, emirate)
);
alter table public.demand_forecast enable row level security;
drop policy if exists demand_forecast_service_role_only on public.demand_forecast;
create policy demand_forecast_service_role_only on public.demand_forecast as permissive for all to public using (false) with check (false);
revoke all on public.demand_forecast from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('demand_search', true, 'company', 'brief-box searches the router recognised: trade and emirate only, no text (backlog T4)', 'sales_engineer'),
  ('demand_forecast', true, 'decision', 'the sales engineer''s daily 30/90-day demand estimate per trade and emirate (backlog T4)', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

-- The brief box's recorder, called by public_site with the service role after the router recognised a trade.
create or replace function public.fn_demand_search_record(p_category text, p_emirate text)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  insert into public.demand_search (category, trades, emirate)
  select p_category, public.fn_taxonomy_trades_for(array[p_category]),
         case when p_emirate in ('Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah') then p_emirate end
   where p_category ~ '^[a-z][a-z0-9_-]{1,59}$';
$fn$;
revoke execute on function public.fn_demand_search_record(text, text) from public, anon, authenticated;

create or replace function public.fn_demand_forecast_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_method constant text := 'blended daily rate 0.6*r30 + 0.4*r90, times 30 / 90 days; searches projected separately, never added';
  v_rows int; v_acted int;
begin
  delete from public.demand_forecast where run_on = v_today;   -- a re-run the same day replaces its own rows
  delete from public.demand_search where searched_at < now() - interval '90 days';   -- nothing reads older rows

  with inq as (
    -- distinct: an inquiry's trades usually already contain its category's code, and must count once
    select i.created_at, array(select distinct t from unnest(coalesce(i.trades, '{}') || public.fn_taxonomy_trades_for(array[i.category])) t) as trades, i.emirate
      from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.created_at > now() - interval '90 days' and i.parent_inquiry_id is null
       -- DEMO IS NEVER DEMAND (a_demo_request_is_never_supply_gap_demand.sql): a request with no customer, or a
       -- fixture customer's (is_demo, ZZ DEMO name, @example.invalid email), never starts real recruitment
       and i.customer_id is not null and not coalesce(public.fn_seat_clock_customer_is_fixture(c), false)
  ), srch as (
    select s.searched_at as created_at, s.trades, s.emirate
      from public.demand_search s where s.searched_at > now() - interval '90 days' and s.source <> 'fixture'
  ), ev as (
    select 'i' as k, created_at, t as trade, emirate from inq, unnest(trades) t
    union all
    select 's', created_at, t, emirate from srch, unnest(trades) t
  ), ev2 as (                                  -- each event counts for its emirate and for the UAE roll-up
    select k, created_at, trade, emirate from ev where emirate is not null
    union all
    select k, created_at, trade, 'UAE' from ev
  ), agg as (
    select trade, emirate,
           count(*) filter (where k = 'i' and created_at > now() - interval '30 days')::int as i30,
           count(*) filter (where k = 'i')::int as i90,
           count(*) filter (where k = 's' and created_at > now() - interval '30 days')::int as s30,
           count(*) filter (where k = 's')::int as s90
      from ev2 group by trade, emirate
  )
  insert into public.demand_forecast (run_on, trade, emirate, inquiries_30d, inquiries_90d, searches_30d, searches_90d,
         forecast_30d, forecast_90d, searches_forecast_30d, searches_forecast_90d, method, sufficient_data, matchable, target)
  select v_today, a.trade, a.emirate, a.i30, a.i90, a.s30, a.s90,
         round((0.6 * a.i30 / 30.0 + 0.4 * a.i90 / 90.0) * 30, 1), round((0.6 * a.i30 / 30.0 + 0.4 * a.i90 / 90.0) * 90, 1),
         round((0.6 * a.s30 / 30.0 + 0.4 * a.s90 / 90.0) * 30, 1), round((0.6 * a.s30 / 30.0 + 0.4 * a.s90 / 90.0) * 90, 1),
         v_method || case when a.i90 < 10 then '; insufficient_data (' || a.i90 || ' inquiries in 90 days)' else '' end,
         a.i90 >= 10, g.matchable, g.target
    from agg a left join public.supply_gap g on g.trade = a.trade and g.emirate = a.emirate;
  get diagnostics v_rows = row_count;

  -- ACT: recruit ahead of forecast demand, on the supply-gap path the sales engineer already owns.
  with hit as (
    update public.supply_gap g set status = 'recruit', decided_by = 'rule:forecast_demand', decided_at = now()
      from public.demand_forecast f
     where f.run_on = v_today and f.trade = g.trade and f.emirate = g.emirate
       and g.matchable < g.target and g.status in ('open', 'deciding', 'deferred')
       and g.uninvited_pool > 0 and g.decided_by is distinct from 'rule:no_uninvited_leads'   -- nobody to invite: stays deferred
       and f.forecast_90d >= 1   -- real inquiries only: searches are anonymous and never start recruitment
    returning g.trade, g.emirate
  )
  update public.demand_forecast f set acted = 'supply_gap -> recruit (rule:forecast_demand)'
    from hit where f.run_on = v_today and f.trade = hit.trade and f.emirate = hit.emirate;
  get diagnostics v_acted = row_count;

  return jsonb_build_object('run_on', v_today, 'basis', 'estimate', 'method', v_method, 'rows', v_rows,
    'recruit_started', v_acted,
    'top', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
              select trade, emirate, forecast_30d, forecast_90d, searches_30d, sufficient_data from public.demand_forecast
               where run_on = v_today order by forecast_90d desc, searches_30d desc limit 10) x));
end $fn$;
revoke execute on function public.fn_demand_forecast_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled)
values ('sales_engineer.demand_forecast', 'sales_engineer', '1 day', 'fn_demand_forecast_tick',
  '30/90-day demand per trade and emirate from inquiries and brief-box searches, labelled an estimate; a trade below target with forecast demand is recruited for before the customer arrives.',
  'scripts/sql/the_sales_engineer_forecasts_thirty_and_ninety_days_of_demand_per_trade_and_emirate.sql', true)
on conflict (duty) do update set routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file, every = excluded.every;

-- ── the canonical supply-gap tick releases a forecast recruitment ───────────────────────────────────────────
-- From a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model.sql (canonical, MANIFEST 1951).
-- Only the "A FORECAST THAT NO LONGER SHOWS DEMAND IS UNDONE" step and its 'forecast_rule_undone' count are new.
create or replace function public.fn_sales_engineer_supply_gap(p_reason_limit integer default 10)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_target int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_rule int; v_closed int; v_reopened int; v_settled int; v_nobody int; v_held_settled int; v_forecast_settled int;
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

  -- A RULE WHOSE CUSTOMER IS GONE IS UNDONE: a gap recruited for because a customer was waiting, where no counted
  -- (non-demo) request remains, goes back to open and is decided again below like any gap nobody waits on.
  update public.supply_gap set status = 'open', decided_by = null, decided_at = null, held_id = null
   where status = 'recruit' and decided_by = 'rule:customer_waiting' and short_open = 0 and demand_90d = 0;
  get diagnostics v_settled = row_count;

  -- A FORECAST THAT NO LONGER SHOWS DEMAND IS UNDONE (review of #1182): a gap fn_demand_forecast_tick recruited for
  -- goes back to open once no forecast from the last two days shows demand there (or the forecast stopped running),
  -- and is decided again below like any gap nobody waits on.
  update public.supply_gap g set status = 'open', decided_by = null, decided_at = null, held_id = null
   where g.status = 'recruit' and g.decided_by = 'rule:forecast_demand'
     and not exists (select 1 from public.demand_forecast f
                      where f.trade = g.trade and f.emirate = g.emirate and f.forecast_90d >= 1
                        and f.run_on > (now() at time zone 'Asia/Dubai')::date - 2);
  get diagnostics v_forecast_settled = row_count;

  -- A CUSTOMER IS ALREADY WAITING: recruited for at once, by rule. No judgement to make, so nothing waits on one.
  update public.supply_gap set status = 'recruit', decided_by = 'rule:customer_waiting', decided_at = now()
   where status in ('open', 'deciding', 'deferred') and (short_open > 0 or demand_90d > 0);
  get diagnostics v_rule = row_count;

  -- NO UNINVITED LEAD LEFT: nobody for marketing to recruit, so "defer" is the only answer - by rule, at no cost.
  update public.supply_gap set status = 'deferred', decided_by = 'rule:no_uninvited_leads', decided_at = now()
   where status = 'open' and uninvited_pool = 0;

  -- NOBODY IS WAITING: deferred by rule, at no cost (R8). A decision already held for the model is settled the same
  -- way, and the question it waited on is expired with the reason.
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', 'fn_sales_engineer_supply_gap',
           'why', 'decided by code: nobody is waiting on this trade and area (rule:nobody_waiting)')
    from public.supply_gap s
   where s.status = 'deciding' and s.short_open = 0 and s.demand_90d = 0 and h.id = s.held_id and h.status = 'held';
  get diagnostics v_held_settled = row_count;
  update public.supply_gap set status = 'deferred', decided_by = 'rule:nobody_waiting', decided_at = now(), held_id = null
   where status in ('open', 'deciding') and short_open = 0 and demand_90d = 0;
  get diagnostics v_nobody = row_count;

  return jsonb_build_object('target', v_target, 'closed', v_closed, 'reopened', v_reopened, 'recruit_by_rule', v_rule, 'customer_rule_undone', v_settled, 'forecast_rule_undone', v_forecast_settled,
    'deferred_nobody_waiting', v_nobody, 'held_questions_settled', v_held_settled, 'filed_for_reasoning', 0,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $fn$;
revoke execute on function public.fn_sales_engineer_supply_gap(integer) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supply_gap(integer) to service_role;
