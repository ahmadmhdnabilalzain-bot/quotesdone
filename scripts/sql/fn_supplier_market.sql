-- ==============================================================================================
-- ROW #5 §14 — MARKET INTELLIGENCE. The demand half, now that there is demand to read.
--
-- ── WHAT CHANGED AND WHY ────────────────────────────────────────────────────────────────────────
-- The previous version hard-coded `available: false` on demand_trend, most_requested and
-- avg_market_price, and that was the right answer to the estate it was written against: 0 inquiries
-- and 0 quotes, so every one of those figures would have been invented. A hard-coded false is the
-- wrong answer to a market that exists, and it is wrong in the more dangerous direction — it would
-- keep saying "not available yet" after the platform could answer, and no one would notice.
--
-- So availability is now COMPUTED. Each of the three figures returns a real value when its
-- population is non-empty and returns `available: false` with the empty population named when it is
-- not. The flag is derived from a count, which means this routine tells the truth on both sides of
-- the day the market starts, and neither side needs anybody to remember to come back and edit it.
--
-- ── DEMO ROWS AND REAL ROWS CANNOT SEE EACH OTHER ───────────────────────────────────────────────
-- This is a fence, not a filter, and it is the one the fixtures could not enforce for themselves.
-- §14 tells a supplier how many companies compete with them and what the market pays. Six demo
-- companies and twenty-four demo quotes would have moved both numbers for every real HVAC supplier
-- on the platform, and a real supplier would have had no way to know their competitor count was
-- inflated. One symmetric predicate, applied to every population below:
--
--     (coalesce(l.source, '') = 'qd_demo_fixture') = is_demo
--
-- A demo fixture's market is computed over demo rows; a real supplier's market over real rows.
-- Symmetric, so neither side leaks into the other, and it costs a real supplier nothing.
--
-- ── THE PERCENTAGE THIS CANNOT HONESTLY GIVE, AND THE ONE IT CAN ────────────────────────────────
-- Nothing here is back-dated, so every demo enquiry was created within minutes of each other and
-- the prior period is empty. A period-over-period percentage from a base of zero is undefined, and
-- "demand ↑ 600%" would be a fabrication dressed as arithmetic. So `pct` is NULL whenever the prior
-- period is empty, `from_zero` says why, and the weekly `series` is returned so the shape of the
-- run-up is visible rather than asserted.
--
-- `share_pct` IS honest and is computed: what proportion of all enquiries in the window are in this
-- supplier's category. It is labelled as a share, never as a trend, because they are different
-- claims and only one of them is available today.
create or replace function public.fn_supplier_market(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),

  -- Competitors: same sector, overlapping service area, not this supplier, same side of the fence.
  peers as (
    select l.*
    from public.leads l, me, flag
    where l.id <> me.id
      and l.sector is not null
      and me.sector is not null
      and l.sector = me.sector
      and coalesce(l.permanently_closed, false) = false
      and (coalesce(l.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  peers_here as (
    select p.* from peers p, me
    where me.service_emirates is null
       or coalesce(array_length(me.service_emirates, 1), 0) = 0
       or p.emirate is null
       or exists (select 1 from unnest(me.service_emirates) e where p.emirate ilike '%' || e || '%')
  ),

  -- ── THE DEMAND POPULATIONS ────────────────────────────────────────────────────────────────────
  -- Every enquiry on this side of the fence, and the subset in this supplier's own category.
  -- The window is 28 days split into two 14-day halves; `cur` is the half that just ended.
  demand_all as (
    select i.* from public.inquiries i, flag
    where (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
      and i.created_at >= now() - interval '28 days'
  ),
  demand_mine as (
    select d.* from demand_all d, me where me.sector is not null and d.category = me.sector
  ),
  -- Quotes are priced against enquiries, so the price population is the quotes ON those enquiries.
  priced as (
    select q.quote_amount amt
    from public.quotes q join demand_mine d on d.id = q.inquiry_id, flag
    where (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
      and q.quote_amount is not null and q.quote_amount > 0
  ),

  -- ── THE THREE FIGURES, EACH BUILT ONCE ────────────────────────────────────────────────────────
  -- Built in a CTE and referenced by key below, rather than inline, so each figure's empty branch
  -- sits with the computation it belongs to instead of beside the key it answers for.
  figures as (
    select
      -- Trend. Direction is a comparison of two counted halves; pct is only produced when there is
      -- a prior period to divide by.
      (with c as (
         select count(*) filter (where created_at >= now() - interval '14 days') as recent,
                count(*) filter (where created_at <  now() - interval '14 days') as earlier
         from demand_mine)
       select case when c.recent = 0 and c.earlier = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'direction', null,
                'basis', 'enquiries in your category over the last 28 days',
                'population', 0,
                'note', 'no enquiries in your category yet, so there is no series to trend')
         else jsonb_build_object(
                'available', true,
                'category', (select sector from me),
                'value', c.recent,
                'prior', c.earlier,
                'direction', case when c.recent > c.earlier then 'up'
                                  when c.recent < c.earlier then 'down' else 'flat' end,
                'pct', case when c.earlier > 0
                            then round(((c.recent - c.earlier)::numeric / c.earlier) * 100, 1)
                            else null end,
                'from_zero', c.earlier = 0,
                'share_pct', case when (select count(*) from demand_all) > 0
                             then round((c.recent::numeric
                                  / nullif((select count(*) from demand_all), 0)) * 100, 1)
                             else null end,
                'series', (
                  select coalesce(jsonb_agg(jsonb_build_object('week', w.wk, 'count', w.c) order by w.wk), '[]'::jsonb)
                  from (select date_trunc('week', created_at)::date wk, count(*) c
                        from demand_mine group by 1) w),
                'basis', 'enquiries in your category, two 14-day halves',
                'population', (select count(*) from demand_mine),
                'note', case when c.earlier = 0
                        then 'first activity in this window, so there is no prior period to take a percentage against'
                        else null end)
         end from c) as trend_obj,

      -- The single most-asked-for category across the whole population, with its count.
      (with r as (select category cat, count(*) c from demand_all
                  where category is not null group by 1 order by count(*) desc limit 1)
       select case when not exists (select 1 from r)
         then jsonb_build_object(
                'available', false, 'value', null,
                'basis', 'enquiries over the last 28 days',
                'population', (select count(*) from demand_all),
                'note', 'that is a fact about requests, and none have been made')
         else jsonb_build_object(
                'available', true,
                'value', (select cat from r),
                'count', (select c from r),
                'basis', 'enquiries over the last 28 days, grouped by category',
                'population', (select count(*) from demand_all))
         end) as topcat_obj,

      -- What the market is actually charging. The median matters more than the mean to a supplier
      -- deciding where to sit, and the quartiles are what "you are high/low" is measured against,
      -- so all of them are returned rather than one number with no spread around it.
      (with s as (
         select count(*) n, round(avg(amt)) mean,
                round(percentile_cont(0.5)  within group (order by amt)) mid,
                round(percentile_cont(0.25) within group (order by amt)) lo,
                round(percentile_cont(0.75) within group (order by amt)) hi,
                min(amt) lowest, max(amt) highest
         from priced)
       select case when s.n = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'currency', 'AED',
                'basis', 'quotes on enquiries in your category',
                'population', 0,
                'note', 'nothing in your category has been priced, so there is no market price')
         else jsonb_build_object(
                'available', true, 'currency', 'AED',
                'value', s.mean, 'median', s.mid, 'p25', s.lo, 'p75', s.hi,
                'low', s.lowest, 'high', s.highest,
                'basis', 'quotes on enquiries in your category over the last 28 days',
                'population', s.n)
         end from s) as money_obj
  )

  select jsonb_build_object(
    'lead_id', p_lead_id,
    'sector', (select sector from me),
    'population', case when (select is_demo from flag) then 'demo' else 'live' end,

    -- ── The competitive picture, real since the first scrape ─────────────────────────────────────
    'competitors', jsonb_build_object(
      'available', true,
      'basis', 'leads in the same sector',
      'total', (select count(*) from peers),
      'in_my_area', (select count(*) from peers_here),
      -- The number a scraped list hides: how many competitors can receive an RFQ at all.
      'matchable', (
        select count(*) from peers p
        where public.fn_is_matchable(p.verified, p.banned, p.matching_blocked,
                                     p.approval_status, p.permanently_closed, p.chat_strikes)
      ),
      -- Group FIRST, build the json after. `group by 1` over a jsonb_build_object containing
      -- count(*) raises 42803: the grouping key would be an expression containing an aggregate.
      'by_emirate', (
        select coalesce(jsonb_agg(jsonb_build_object('emirate', s.em, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select p.emirate as em, count(*) as c
          from peers p where p.emirate is not null
          group by p.emirate order by count(*) desc limit 8
        ) s
      )
    ),

    'market_composition', jsonb_build_object(
      'available', true,
      'basis', 'leads in the same sector, grouped by category',
      'segments', (
        select coalesce(jsonb_agg(jsonb_build_object('name', s.nm, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select coalesce(nullif(btrim(split_part(p.categories, ',', 1)), ''), 'Uncategorised') as nm,
                 count(*) as c
          from peers p group by 1 order by count(*) desc limit 8
        ) s
      )
    ),

    -- ── The demand half. Computed when there is a population, refused when there is not ──────────
    'demand_trend',     (select trend_obj  from figures),
    'most_requested',   (select topcat_obj from figures),
    'avg_market_price', (select money_obj  from figures)
  );
$function$;

comment on function public.fn_supplier_market(bigint) is
  'Row #5 §14. Competitor and supply-composition figures from real leads; demand trend, '
  'most-requested and average price are COMPUTED when their population is non-empty and return '
  'available:false naming the empty population when it is not. Demo and live rows are partitioned '
  'symmetrically so a fixture can never move a real supplier''s numbers.';
