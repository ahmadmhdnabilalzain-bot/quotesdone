-- The homepage counters, and the floor below which they say nothing.
--
-- WHY. Every benchmark front door leads with a measured number (website audit 14 Sep 2026, §1
-- finding 18 / ADOPT 4). The founder's rule is "never state what you have not measured", not
-- "never state numbers" — so the homepage may show a count, but only one read from production on
-- the request, and only once it is large enough to mean something. Below each floor the value is
-- NULL and the page keeps its descriptors (7 Emirates / 3% / Verified / Anonymous).
--
-- WHAT IS COUNTED, AND WHAT IS NOT:
--   licence_verified_suppliers  leads that pass fn_is_matchable (the same gate dispatch uses) AND
--                               have a confirmed scope (supplier_capabilities.confirmed_at), i.e.
--                               a supplier that can actually receive a brief today. ZZ DEMO
--                               fixtures excluded.
--   jobs_this_month             inquiries created since the 1st of the month, Dubai time, excluding
--                               drafts, cancellations and example.invalid demo customers.
--   median_hours_to_first_quote over inquiries of the last 30 days that received a quote: the gap
--                               between posting and the first quote. Needs 5 such jobs.
--   categories_covered          distinct trade codes held by at least one counted supplier.
--   per_trade                   the same supplier count per trade code, for the category tiles;
--                               a tile shows its number only when it is > 0.
-- Measured 14 Sep 2026 on production: 0 / 0 / no quotes / 0 — every value is NULL today, which is
-- the point: the module renders nothing until the business produces the numbers.
--
-- Called only by the public_site edge function with the service role. Aggregates only — no name,
-- id, email or amount leaves this routine.

create or replace function public.fn_public_site_counters()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
with sup as (
  select l.id, sc.trades
    from leads l
    join supplier_capabilities sc on sc.supplier_id = l.id
   where sc.confirmed_at is not null
     and fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status,
                         l.permanently_closed, l.chat_strikes)
     and coalesce(l.company_name, '') not ilike 'ZZ DEMO%'
),
real_inq as (
  select i.id, i.created_at, i.status
    from inquiries i
   where coalesce(i.status, '') not in ('draft', 'cancelled')
     and not exists (select 1 from customers c
                      where c.id = i.customer_id and c.email ilike '%example.invalid')
),
firstq as (
  select i.id, extract(epoch from (min(q.created_at) - i.created_at)) / 3600.0 as h
    from real_inq i
    join quotes q on q.inquiry_id = i.id
   where i.created_at >= now() - interval '30 days'
   group by i.id, i.created_at
),
per as (
  select t, count(distinct sup.id) as n from sup, unnest(sup.trades) as t group by t
),
k as (
  select (select count(*) from sup) as suppliers,
         (select count(*) from real_inq
           where created_at >= (date_trunc('month', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai')) as jobs,
         (select count(*) from firstq) as quoted_jobs,
         (select percentile_cont(0.5) within group (order by h) from firstq) as median_h,
         (select count(*) from per) as trades
)
select jsonb_build_object(
  'licence_verified_suppliers', case when k.suppliers >= 10 then k.suppliers end,
  'jobs_this_month',            case when k.jobs >= 5 then k.jobs end,
  'median_hours_to_first_quote', case when k.quoted_jobs >= 5 then round(k.median_h::numeric, 1) end,
  'median_basis_jobs',          case when k.quoted_jobs >= 5 then k.quoted_jobs end,
  'categories_covered',         case when k.trades >= 3 then k.trades end,
  'per_trade',                  coalesce((select jsonb_object_agg(t, n) from per), '{}'::jsonb),
  'floors', jsonb_build_object('suppliers', 10, 'jobs_this_month', 5, 'quoted_jobs_30d', 5, 'categories', 3),
  'measured_at', now())
from k;
$fn$;

revoke execute on function public.fn_public_site_counters() from public, anon, authenticated;
grant execute on function public.fn_public_site_counters() to service_role;
