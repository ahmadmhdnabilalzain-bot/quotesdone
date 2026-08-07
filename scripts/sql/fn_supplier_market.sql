-- ROW #5 §14 — MARKET INTELLIGENCE, and an honest ceiling.
--
-- ── WHAT THIS CAN AND CANNOT KNOW TODAY, MEASURED FIRST ─────────────────────────────────────────
-- §14 draws four figures. Two of them are about SUPPLY and two are about DEMAND, and the estate
-- only has one of those halves.
--
--   competitors        REAL. 20,464 leads with a sector and an emirate. A supplier genuinely can
--                      be told how many companies compete with them, where, and how many of those
--                      are actually able to receive work.
--   market composition REAL. The same population, grouped by category.
--   demand trend       BLOCKED. 0 inquiries, so there is no series to trend and no direction to
--                      point an arrow at.
--   most requested     BLOCKED. Same reason: "most requested" is a fact about requests.
--   average price      BLOCKED. 0 quotes. There is no market price because nothing has been priced.
--
-- Each blocked figure returns null with an `available: false` and a `basis` naming the empty
-- population. It does NOT return a plausible number. An arrow saying "HVAC demand ↑ 18%" against
-- zero inquiries would be indistinguishable from real market intelligence on screen, and a supplier
-- could staff up on the strength of it.
--
-- The competitor half is not a consolation prize. "23 suppliers compete with you in Dubai, and 0 of
-- them can currently receive an RFQ" is a genuinely useful and completely truthful thing to know.
create or replace function public.fn_supplier_market(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  -- Competitors: same sector, overlapping service area, not this supplier.
  peers as (
    select l.*
    from public.leads l, me
    where l.id <> me.id
      and l.sector is not null
      and me.sector is not null
      and l.sector = me.sector
      and coalesce(l.permanently_closed, false) = false
  ),
  peers_here as (
    select p.* from peers p, me
    where me.service_emirates is null
       or coalesce(array_length(me.service_emirates, 1), 0) = 0
       or p.emirate is null
       or exists (select 1 from unnest(me.service_emirates) e where p.emirate ilike '%' || e || '%')
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'sector', (select sector from me),

    -- ── REAL: the competitive picture ───────────────────────────────────────────────────────────
    'competitors', jsonb_build_object(
      'available', true,
      'basis', 'leads in the same sector',
      'total', (select count(*) from peers),
      'in_my_area', (select count(*) from peers_here),
      -- The number that actually matters, and the one a scraped list hides: how many of those
      -- competitors can receive an RFQ at all. On production this is 0, and saying so is the
      -- difference between a market and a mailing list.
      'matchable', (
        select count(*) from peers p
        where public.fn_is_matchable(p.verified, p.banned, p.matching_blocked,
                                     p.approval_status, p.permanently_closed, p.chat_strikes)
      ),
      -- Group FIRST, build the json after. `group by 1` over a jsonb_build_object that contains
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

    -- REAL: how the supply side is distributed, which is what a chart can honestly plot today.
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

    -- ── BLOCKED: null, with the empty population named ──────────────────────────────────────────
    'demand_trend', jsonb_build_object(
      'available', false, 'value', null, 'direction', null,
      'basis', 'inquiries',
      'population', (select count(*) from public.inquiries),
      'note', 'no inquiries exist, so there is no series to trend'
    ),
    'most_requested', jsonb_build_object(
      'available', false, 'value', null,
      'basis', 'inquiries',
      'population', (select count(*) from public.inquiries),
      'note', 'most-requested is a fact about requests, and none have been made'
    ),
    'avg_market_price', jsonb_build_object(
      'available', false, 'value', null, 'currency', 'AED',
      'basis', 'quotes',
      'population', (select count(*) from public.quotes),
      'note', 'nothing has been priced, so there is no market price'
    )
  );
$function$;

comment on function public.fn_supplier_market(bigint) is
  'Row #5 §14. Competitor and supply-composition figures from real leads; demand trend, '
  'most-requested and average price return available:false with the empty population named, '
  'never a plausible number.';
