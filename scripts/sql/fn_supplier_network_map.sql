-- ROW #5 §19 — THE SUPPLIER NETWORK MAP: real geography, and four layers scored honestly.
--
-- ── WHAT IS REAL AND WHAT IS EMPTY, MEASURED BEFORE WRITING ─────────────────────────────────────
-- suppliers  : 20,464 leads carry an emirate. REAL, and dense enough to be worth looking at.
-- demand     : 0 inquiries on production.
-- projects   : 0.
-- shipments  : there is no shipments relation at all.
--
-- So one of §19's four layers has data and three do not. Each layer returns its own `count` and its
-- own `basis`, and the empty ones come back as empty arrays rather than as plausible dots. A globe
-- speckled with invented demand would be the most seductive lie in this whole spec: it looks like
-- market intelligence, it photographs well, and nobody can tell by looking that it is nothing.
--
-- ── COORDINATES ARE REFERENCE GEOGRAPHY, NOT BUSINESS DATA ──────────────────────────────────────
-- leads has no lat/lng column, so emirate centroids are stated here as constants. That is the same
-- kind of fact as a map projection — the position of Dubai is not a claim about QuotesDone. What
-- WOULD be fabrication is the count at that position, and every count below is a real count(*).
create or replace function public.fn_supplier_network_map()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with centroid(emirate, lat, lng) as (
    values ('Dubai', 25.2048, 55.2708),
           ('Abu Dhabi', 24.4539, 54.3773),
           ('Sharjah', 25.3463, 55.4209),
           ('Ajman', 25.4052, 55.5136),
           ('Ras Al Khaimah', 25.7895, 55.9432),
           ('Umm Al Quwain', 25.5647, 55.5552),
           ('Fujairah', 25.1288, 56.3265)
  ),
  -- Emirate names arrive in several spellings across 20,464 scraped rows, so they are normalised
  -- to the centroid table's keys. A row that matches nothing is counted as unplaced rather than
  -- dropped: silently discarding rows would make the map look tidier than the data is.
  norm as (
    select case
             when l.emirate ilike '%dubai%'      then 'Dubai'
             when l.emirate ilike '%abu%dhabi%'  then 'Abu Dhabi'
             when l.emirate ilike '%sharjah%'    then 'Sharjah'
             when l.emirate ilike '%ajman%'      then 'Ajman'
             when l.emirate ilike '%ras%khaim%'  then 'Ras Al Khaimah'
             when l.emirate ilike '%umm%quwain%' then 'Umm Al Quwain'
             when l.emirate ilike '%fujairah%'   then 'Fujairah'
             else null end as emirate,
           l.id, l.verified, l.matching_blocked
    from public.leads l
  )
  select jsonb_build_object(
    'generated_for', 'row5-section-19',

    -- ── LAYER 1: SUPPLIERS. Real, and the only populated one. ──────────────────────────────────
    'suppliers', jsonb_build_object(
      'basis', 'leads.emirate',
      'count', (select count(*) from norm where emirate is not null),
      'unplaced', (select count(*) from norm where emirate is null),
      'markers', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'name', c.emirate, 'lat', c.lat, 'lng', c.lng,
          'count', (select count(*) from norm n where n.emirate = c.emirate),
          -- Kept separate because they are different claims: how many companies we KNOW OF versus
          -- how many can actually receive an RFQ. On production the second is 0 and the map must
          -- not let the first stand in for it.
          'matchable', (select count(*) from norm n where n.emirate = c.emirate
                          and coalesce(n.verified, false) and not coalesce(n.matching_blocked, false))
        ) order by c.emirate), '[]'::jsonb)
        from centroid c
      )
    ),

    -- ── LAYERS 2-4: EMPTY, each saying so in its own words ─────────────────────────────────────
    'demand', jsonb_build_object(
      'basis', 'inquiries',
      'count', (select count(*) from public.inquiries),
      'markers', '[]'::jsonb,
      'note', 'no inquiries exist yet, so no demand is plotted'
    ),
    'projects', jsonb_build_object(
      'basis', 'inquiries with a project',
      'count', (select count(*) from public.inquiries),
      'markers', '[]'::jsonb,
      'note', 'no projects exist yet'
    ),
    'shipments', jsonb_build_object(
      'basis', 'none',
      'count', 0,
      'markers', '[]'::jsonb,
      'note', 'there is no shipments relation in this schema; nothing is tracked to plot'
    ),

    'totals', jsonb_build_object(
      'leads', (select count(*) from public.leads),
      'placed', (select count(*) from norm where emirate is not null),
      'matchable', (select count(*) from norm
                    where coalesce(verified, false) and not coalesce(matching_blocked, false))
    )
  );
$function$;

comment on function public.fn_supplier_network_map() is
  'Row #5 §19. Supplier density by emirate from real leads, plus demand/projects/shipments layers '
  'that return EMPTY with a stated basis rather than plausible dots. Centroids are reference '
  'geography; every count is a real count(*).';
