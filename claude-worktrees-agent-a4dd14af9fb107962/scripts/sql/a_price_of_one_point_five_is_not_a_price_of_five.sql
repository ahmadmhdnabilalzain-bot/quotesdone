-- A PRICE OF ONE POINT FIVE IS NOT A PRICE OF FIVE (9 Sep 2026). Agent: ceo.
-- Second repair to the_price_benchmarks_come_out_of_the_estate_instead_of_out_of_nowhere.sql.
--
-- FOUND BY A SANITY CHECK, not by reading: one price_benchmark row had high < low. Hollow concrete
-- blocks came out as AED 5 to AED 4 per piece, from a source cell that reads "1.5-4 / piece".
--
-- CAUSE. The blog-table extractor's number pattern was `([0-9][0-9,]*)`, which has no decimal part.
-- Against "1.5-4" it did not fail -- it matched the "5" out of the middle of "1.5" and the "4" after
-- the dash, and produced a confident, inverted, wrong band. The kb_chunks extractor in the same file
-- already carried `(?:\.[0-9]+)?` and was correct; the blog path did not, and nothing compared them.
--
-- WHY IT MATTERS MORE THAN ONE ROW. Exactly one of the 206 blog-sourced cells carries a decimal
-- today, so the visible damage is one row. But the estate's own cost guides quote materials in
-- fractions of a dirham -- blocks, tiles, per-piece and per-kg items -- and the next guide published
-- would have been mis-parsed in silence. A parser that mangles a number rather than refusing it is
-- the worst kind: the row still looks like data.
--
-- THE FIX is the decimal group, plus the `high >= low` guard the kb_chunks path already had. An
-- inverted band is now impossible to insert on either path rather than merely unlikely.
--
--   node scripts/apply_sql.mjs scripts/sql/a_price_of_one_point_five_is_not_a_price_of_five.sql --apply --ddl

begin;

-- The band is inserted, not asserted, so the guard belongs on the table where every future writer
-- meets it -- not in the one query that happened to be wrong today.
alter table public.price_benchmark drop constraint if exists price_benchmark_band_ordered;
delete from public.price_benchmark where source_kind <> 'gap' and high < low;
alter table public.price_benchmark
  add constraint price_benchmark_band_ordered check (low is null or high is null or high >= low);

create temporary table _blog_cat3 (slug_like text, category text) on commit drop;
insert into _blog_cat3 (slug_like, category) values
  ('cost-of-flooring-uae',            'flooring'),
  ('cost-of-tiling-marble-uae',       'tiling'),
  ('cost-of-tiling-marble-uae',       'marble-granite'),
  ('cost-of-false-ceiling-uae',       'gypsum'),
  ('cost-of-house-painting-uae',      'painting'),
  ('cost-of-plumbing-uae',            'plumbing'),
  ('cost-of-electrical-work-uae',     'electrical'),
  ('cost-of-cctv-installation-uae',   'security'),
  ('cost-of-signage-uae',             'signage'),
  ('cost-of-landscaping-uae',         'landscaping'),
  ('cost-of-movers-uae',              'movers'),
  ('cost-of-deep-cleaning-uae',       'cleaning'),
  ('cost-of-pest-control-uae',        'pest'),
  ('cost-of-solar-uae',               'solar'),
  ('cost-of-smart-home-uae',          'smart-home'),
  ('cost-of-swimming-pool-uae',       'swimming-pools'),
  ('cost-of-waterproofing-uae',       'waterproofing'),
  ('cost-of-kitchen-uae',             'kitchens'),
  ('cost-of-fit-out-uae',             'fitout'),
  ('cost-of-fit-out-uae',             'commercial-retail-fitout'),
  ('cost-of-ac-maintenance-uae',      'hvac'),
  ('cost-of-ac-duct-cleaning-uae',    'hvac'),
  ('cost-of-curtains-blinds-uae',     'blinds-curtains'),
  ('cost-of-aluminium-glass-uae',     'aluminium'),
  ('cost-of-aluminium-glass-uae',     'glass'),
  ('cost-of-handyman-uae',            'general-services-other'),
  ('cost-of-facilities-management-uae','general-services-other'),
  ('cost-of-building-materials-uae',  'general'),
  ('how-much-does-epoxy-flooring-cost%',  'epoxy-flooring'),
  ('how-much-does-cctv-installation-cost%','security'),
  ('how-much-does-an-annual-ac-maintenance%','hvac'),
  ('how-much-does-office-partition-installation%', 'gypsum'),
  ('how-much-does-office-partition-installation%', 'glass');

with raw as (
  select b.slug,
         b.published_at::date as as_of,
         replace(replace(replace(replace(replace(m[1], '&ndash;', '-'), '&mdash;', ' - '), '&amp;', '&'), '&rarr;', '->'), '&nbsp;', ' ') as item,
         replace(replace(replace(m[2], '&ndash;', '-'), '&mdash;', ' - '), '&nbsp;', ' ')                                                  as price
    from public.blog_posts b,
         lateral (select regexp_matches(b.body_html, '<tr><td>([^<]{1,160})</td><td>([^<]{1,80})</td></tr>', 'g') as m) x
   where b.published and b.body_html ~ 'AED'
), parsed as (
  select r.*,
         -- The decimal group is the whole point of this file.
         (regexp_match(r.price, '([0-9][0-9,]*(?:\.[0-9]+)?)\s*[-–—]\s*([0-9][0-9,]*(?:\.[0-9]+)?)'))[1] as lo_s,
         (regexp_match(r.price, '([0-9][0-9,]*(?:\.[0-9]+)?)\s*[-–—]\s*([0-9][0-9,]*(?:\.[0-9]+)?)'))[2] as hi_s,
         lower(r.item || ' ' || r.price)                                                                 as txt
    from raw r
), united as (
  select p.*,
         case
           when p.txt ~ '(per\s*sqm|per\s*sq\s*m\b|/\s*sqm|per\s*square\s*met|/\s*m2|per\s*m2)'    then 'sqm'
           when p.txt ~ '(per\s*sqft|per\s*sq\s*ft|/\s*sqft|per\s*square\s*f(oo|ee)t)'             then 'sqft'
           when p.txt ~ '(per\s*linear\s*met|per\s*lm\b|/\s*lm\b|per\s*metre|per\s*meter)'         then 'lm'
           when p.txt ~ '/\s*ton'                                                                  then 'ton'
           when p.txt ~ '/\s*sheet'                                                                then 'sheet'
           when p.txt ~ '/\s*bag'                                                                  then 'bag'
           when p.txt ~ '/\s*kg'                                                                   then 'kg'
           when p.txt ~ '/\s*(m³|m3)'                                                              then 'm3'
           when p.txt ~ '/\s*piece'                                                                then 'piece'
           when p.txt ~ 'per\s*kwp'                                                                then 'kWp'
           when p.txt ~ 'per\s*kwh'                                                                then 'kWh'
           when p.txt ~ 'per\s*window'                                                             then 'window'
           when p.txt ~ 'per\s*letter'                                                             then 'letter'
           when p.txt ~ 'per\s*camera'                                                             then 'camera'
           when p.txt ~ '(per\s*wiring\s*point|per\s*point|per\s*outlet)'                          then 'point'
           when p.txt ~ 'per\s*(door|track|bathroom|room|item|key)'                                 then (regexp_match(p.txt, 'per\s*(door|track|bathroom|room|item|key)'))[1]
           when p.txt ~ '(per\s*hour|hourly)'                                                      then 'hour'
           when p.txt ~ 'per\s*month'                                                              then 'month'
           when p.txt ~ '\(each\)'                                                                 then 'each'
           else 'job'
         end as unit_base
    from parsed p
)
insert into public.price_benchmark
  (category, source_category, item, unit, basis_kind, low, high, evidence, source_kind, source_ref, as_of, confidence)
select distinct
       c.category,
       u.slug,
       btrim(u.item),
       u.unit_base || case when u.unit_base <> 'job' and u.txt ~ 'year' then '/year' else '' end,
       case when u.unit_base = 'job' then 'job' else 'per_unit' end,
       replace(u.lo_s, ',', '')::numeric,
       replace(u.hi_s, ',', '')::numeric,
       'blog_posts/' || u.slug || ' table row: "' || btrim(u.item) || '" = AED ' || u.price,
       'blog_post',
       u.slug,
       u.as_of,
       'published'
  from united u
  join _blog_cat3 c on u.slug like c.slug_like
 where u.lo_s is not null and u.hi_s is not null
   and replace(u.hi_s, ',', '')::numeric >= replace(u.lo_s, ',', '')::numeric
on conflict do nothing;

-- A category whose only band was the inverted one would now be silently priceless, so the gap rows
-- are recomputed rather than assumed still correct.
delete from public.price_benchmark g
 where g.source_kind = 'gap'
   and exists (select 1 from public.price_benchmark pb
                where pb.category = g.category and pb.source_kind <> 'gap');

insert into public.price_benchmark
  (category, unit, basis_kind, low, high, source_kind, source_ref, confidence, gap_reason)
select cs.category, 'none', 'none', null, null, 'gap', 'category_specs/' || cs.category, 'none',
       'No AED figure for this trade exists anywhere in the estate as of 9 Sep 2026: not in the 29 published cost guides in blog_posts, and not in the unit rates extractable from kb_chunks. Deliberately not guessed. Fill from a supplier submittal, a real quote, or a sourced ingest -- never from memory.'
  from public.category_specs cs
 where not exists (select 1 from public.price_benchmark pb
                    where pb.category = cs.category and pb.source_kind <> 'gap')
on conflict do nothing;

commit;
