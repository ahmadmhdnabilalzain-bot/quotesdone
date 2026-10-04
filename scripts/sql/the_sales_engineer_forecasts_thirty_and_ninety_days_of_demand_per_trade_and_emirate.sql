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
--   fn_demand_forecast_tick  code only, no model. Demo inquiries (customers.is_demo) are excluded.
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

  with inq as (
    -- distinct: an inquiry's trades usually already contain its category's code, and must count once
    select i.created_at, array(select distinct t from unnest(coalesce(i.trades, '{}') || public.fn_taxonomy_trades_for(array[i.category])) t) as trades, i.emirate
      from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.created_at > now() - interval '90 days' and i.parent_inquiry_id is null
       and not coalesce(c.is_demo, false)
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
