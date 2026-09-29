-- The sales engineer measures how fast and how full each comparison is. Seat: sales_engineer. 28 Sep 2026.
--
-- GAP: nothing measured the time from an inquiry to its quote_compare report, or how many of those
-- reports compared 3 or more complete quotes. The report is the qd_compare_cache row the quote_compare
-- edge function writes (supabase/functions/quote_compare/index.ts). A row whose analysis carries
-- '__failed' is a remembered failure (spend_guards.ts failureRecord), not a report, and is not counted.
-- Measured read-only on production 28 Sep 2026: 180 cache rows, 0 of them a report; 3 quotes in total.
--
-- COMPLETE QUOTE: a price (price_ex_vat or quote_amount) and all four terms deterministic.ts scores
-- stated - lead_time, validity, warranty, payment_terms. EXCLUSIONS are flagged separately, because a
-- quote that excludes something is complete but not like-for-like.
--
-- Weekly duty: sales_engineer.comparison_kpi via seat_duty. Knowledge and spec checklists are out of scope.

create or replace function public.fn_sales_engineer_comparison_kpi(p_days integer default 7)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
with rep as (
  select c.inquiry_id, min(c.created_at) as reported_at
    from public.qd_compare_cache c
   where not (c.analysis ? '__failed')
     and c.created_at >= now() - make_interval(days => greatest(1, p_days))
   group by c.inquiry_id
),
q as (
  select r.inquiry_id,
         count(*) filter (where coalesce(qt.price_ex_vat, qt.quote_amount) is not null
                            and nullif(btrim(qt.lead_time), '') is not null
                            and nullif(btrim(qt.validity), '') is not null
                            and nullif(btrim(qt.warranty), '') is not null
                            and nullif(btrim(qt.payment_terms), '') is not null) as complete_n,
         count(*) filter (where nullif(btrim(qt.exclusions), '') is not null) as excl_n
    from rep r
    left join public.quotes qt on qt.inquiry_id::text = r.inquiry_id
   group by r.inquiry_id
),
t as (
  select r.inquiry_id, extract(epoch from (r.reported_at - i.created_at)) / 3600.0 as hours,
         q.complete_n, q.excl_n
    from rep r
    join q on q.inquiry_id = r.inquiry_id
    left join public.inquiries i on i.id::text = r.inquiry_id
)
select jsonb_build_object(
  'window_days', greatest(1, p_days),
  'reports', count(*),
  'hours_median', round((percentile_cont(0.5) within group (order by hours))::numeric, 1),
  'hours_p90', round((percentile_cont(0.9) within group (order by hours))::numeric, 1),
  'share_3plus_complete', case when count(*) > 0 then round(count(*) filter (where complete_n >= 3)::numeric / count(*), 3) end,
  'reports_with_exclusions', count(*) filter (where excl_n > 0),
  'quotes_with_exclusions', coalesce(sum(excl_n), 0))
from t;
$fn$;
revoke execute on function public.fn_sales_engineer_comparison_kpi(integer) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_comparison_kpi(integer) to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.comparison_kpi', 'sales_engineer', interval '7 days', 'fn_sales_engineer_comparison_kpi',
   'Hours from inquiry to its quote_compare report (median, p90), share of reports with 3+ complete quotes, exclusions flagged.',
   'scripts/sql/the_sales_engineer_measures_how_fast_and_how_full_each_comparison_is.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- Verdict row (DDL file, so no raise): the routine answers and the duty is registered.
select case
  when (public.fn_sales_engineer_comparison_kpi(7) ? 'reports')
   and exists (select 1 from public.seat_duty where duty = 'sales_engineer.comparison_kpi' and routine = 'fn_sales_engineer_comparison_kpi')
  then 'PROBE OK ' || public.fn_sales_engineer_comparison_kpi(7)::text
  else 'PROBE FAILED: comparison KPI did not answer or its duty is missing' end as verdict;
