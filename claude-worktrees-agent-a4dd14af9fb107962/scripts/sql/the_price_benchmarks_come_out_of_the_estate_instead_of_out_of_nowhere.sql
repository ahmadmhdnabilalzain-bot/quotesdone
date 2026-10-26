-- THE PRICE BENCHMARKS COME OUT OF THE ESTATE INSTEAD OF OUT OF NOWHERE (9 Sep 2026).
-- Agent: ceo. Answers founder instruction #15 — "those knowledge gaps, you need to fill them
-- properly", specifically pricing.
--
-- MEASURED BEFORE THIS FILE. The sales engineer exists to judge whether a quote is fair and holds
-- not one AED figure: 0 of 1,136 sales_knowledge rows contain "AED", and 1 of 9,139 ops_knowledge
-- rows carries a per-unit rate. fn_price_confidence reads exactly one thing --
-- `category_price_stats`, a VIEW over `quotes`. quotes = 0 rows, inquiries = 0 rows, so the view is
-- empty and fn_price_confidence has returned band='insufficient_data' on every call it has ever
-- served. Four downstream surfaces are dark behind it: fn_negotiation_guidance, fn_customer_savings,
-- fn_customer_decision_support and fn_decide(p_kind='price'). This is the cold-start problem, and it
-- bites before the first real quote, not after.
--
-- NOT ONE FIGURE IN THIS FILE IS INVENTED. Every row is lifted by regular expression from text that
-- is already in this database, and every row stores the verbatim sentence it came from plus the id
-- or slug of the source, so any figure can be walked back to its evidence:
--
--   A. public.blog_posts -- the company's OWN 29 published UAE cost guides (26 Jun - 20 Jul 2026).
--      Two markups: a <table> of "Item (per unit) | low-high", and prose <li><strong>Item:</strong>
--      roughly AED low-high per unit</li> in the four newer posts. as_of = published_at.
--   B. public.kb_chunks -- 901 "AED low-high per <unit>" ranges across 278 chunks and 90 categories,
--      found by the tight regex below over the 3,678 rows whose fts carries the 'aed' lexeme.
--
-- `typical` is left NULL on every row. The sources state a range; none states a central value, and
-- deriving one into the table would be putting a number in the estate that nobody published. The
-- midpoint is computed at read time by fn_price_confidence and labelled as a midpoint there.
--
-- TRADES WITH NO EVIDENCE ARE RECORDED, NOT GUESSED. Every category_specs.category that ends this
-- file with no rate gets a gap row (low/high NULL, gap_reason set). A guess would be worse than the
-- silence it replaces: this table is read by the routine that tells a customer their quote is fair.
--
--   node scripts/apply_sql.mjs scripts/sql/the_price_benchmarks_come_out_of_the_estate_instead_of_out_of_nowhere.sql --apply --ddl

begin;

create table if not exists public.price_benchmark (
  id              bigserial primary key,
  category        text        not null,
  source_category text,
  item            text,
  unit            text        not null,
  basis_kind      text        not null check (basis_kind in ('per_unit', 'job', 'none')),
  currency        text        not null default 'AED',
  low             numeric,
  typical         numeric,
  high            numeric,
  evidence        text,
  source_kind     text        not null check (source_kind in ('blog_post', 'kb_chunk', 'gap')),
  source_ref      text        not null,
  as_of           date,
  confidence      text        not null check (confidence in ('published', 'machine_extracted', 'none')),
  gap_reason      text,
  created_at      timestamptz not null default now(),
  constraint price_benchmark_rate_or_gap check (
    (source_kind = 'gap' and low is null and high is null and gap_reason is not null)
    or (source_kind <> 'gap' and low is not null and high is not null and gap_reason is null)
  )
);

comment on table public.price_benchmark is
  'UAE unit-rate and whole-job benchmarks lifted verbatim from evidence already in this database (blog_posts cost guides, kb_chunks). Read by fn_price_confidence when category_price_stats has no live quotes -- the cold-start answer. Rows with source_kind=''gap'' are trades where the estate holds NO evidence and a figure was deliberately not guessed. Never insert a figure here that is not quoted in the evidence column.';
comment on column public.price_benchmark.category is 'category_specs.category slug -- the vocabulary inquiries.category is validated against by inquiry_intake, and therefore the vocabulary fn_price_confidence is called with.';
comment on column public.price_benchmark.source_category is 'The category the evidence itself used (kb_chunks speaks a different vocabulary: flooring-suppliers, tiling-marble, false-ceiling). Kept so the mapping is auditable.';
comment on column public.price_benchmark.typical is 'Only ever set when a SOURCE states a central figure. Left null for a published range; fn_price_confidence computes the midpoint at read time and says so.';
comment on column public.price_benchmark.evidence is 'The verbatim source text the numbers were lifted from. A row whose numbers cannot be found in this string is a bug.';

create unique index if not exists price_benchmark_natural_key
  on public.price_benchmark (category, source_kind, source_ref, unit, coalesce(item, ''), coalesce(low, -1), coalesce(high, -1));
create index if not exists price_benchmark_category_idx on public.price_benchmark (category) where source_kind <> 'gap';

-- ---------------------------------------------------------------------------------------------
-- The blog-slug -> category_specs.category map. This is the one judgement in the file, so it is
-- written out rather than inferred: a guide covering two trades produces rows under both.
-- ---------------------------------------------------------------------------------------------
create temporary table _blog_cat (slug_like text, category text) on commit drop;
insert into _blog_cat (slug_like, category) values
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

-- The kb_chunks category vocabulary -> category_specs.category, for the categories that do not
-- already match exactly. Exact matches are joined directly and need no entry here.
create temporary table _kb_cat (source_category text, category text) on commit drop;
insert into _kb_cat (source_category, category) values
  ('false-ceiling',                                 'gypsum'),
  ('tiling-marble',                                 'tiling'),
  ('tiling-marble',                                 'marble-granite'),
  ('flooring-suppliers',                            'flooring'),
  ('waterproofing-suppliers',                       'waterproofing'),
  ('joinery-and-carpentry-suppliers',               'carpentry-joinery'),
  ('ac-maintenance',                                'hvac'),
  ('ac-duct-cleaning',                              'hvac'),
  ('aluminium-glass',                               'aluminium'),
  ('aluminium-glass',                               'glass'),
  ('interior-decoration',                           'interior-design'),
  ('furniture-suppliers-ff-and-e-suppliers',        'custom-furniture'),
  ('swimming-pool-suppliers-and-contractors',       'swimming-pools'),
  ('smart-home-and-home-automation-suppliers',      'smart-home'),
  ('renewable-energy-companies-solar-ev-battery',   'solar'),
  ('facilities-management-companies',               'general-services-other'),
  ('cctv-security',                                 'security'),
  ('pest-control',                                  'pest'),
  ('fire-fighting-equipment-suppliers',             'safety'),
  ('fire-alarm-and-life-safety-suppliers',          'safety'),
  ('security-companies',                            'security'),
  ('paints-and-finishing-materials-suppliers',      'painting'),
  ('modular-and-prefab-building-suppliers',         'general-building-contracting'),
  ('landscaping-and-hardscaping-suppliers',         'landscaping'),
  ('it-and-networking-suppliers',                   'it-networking');

-- ---------------------------------------------------------------------------------------------
-- A. THE COMPANY'S OWN PUBLISHED COST GUIDES -- table markup.
-- ---------------------------------------------------------------------------------------------
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
         (regexp_match(r.price, '([0-9][0-9,]*)\s*[-–—]\s*([0-9][0-9,]*)'))[1] as lo_s,
         (regexp_match(r.price, '([0-9][0-9,]*)\s*[-–—]\s*([0-9][0-9,]*)'))[2] as hi_s,
         lower(r.item || ' ' || r.price)                                       as txt
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
           when p.txt ~ 'per\s*(door|track|bathroom|room|item|key)'                                then (regexp_match(p.txt, 'per\s*(door|track|bathroom|room|item|key)'))[1]
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
  join _blog_cat c on u.slug like c.slug_like
 where u.lo_s is not null and u.hi_s is not null
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- A2. The four newer guides use prose bullets rather than a table.
-- ---------------------------------------------------------------------------------------------
with raw as (
  select b.slug, b.published_at::date as as_of,
         m[1] as item, m[2] as lo_s, m[3] as hi_s, lower(m[4]) as unit_s
    from public.blog_posts b,
         lateral (select regexp_matches(
                    b.body_html,
                    '<strong>([^<]{1,90})</strong>[^<]{0,90}?AED\s*([0-9][0-9,]*)\s*[-–—]\s*([0-9][0-9,]*)\+?\s*per\s+(sqm|square met[a-z]*|sq m|m2|camera|point|door|window|linear met[a-z]*|lm|sqft|sq ft)',
                    'g') as m) x
   where b.published
)
insert into public.price_benchmark
  (category, source_category, item, unit, basis_kind, low, high, evidence, source_kind, source_ref, as_of, confidence)
select distinct
       c.category,
       r.slug,
       btrim(rtrim(r.item, ':')),
       case when r.unit_s ~ '^(sqm|square met|sq m|m2)' then 'sqm'
            when r.unit_s ~ '^(sqft|sq ft)'             then 'sqft'
            when r.unit_s ~ '^(linear met|lm)'          then 'lm'
            else r.unit_s end,
       'per_unit',
       replace(r.lo_s, ',', '')::numeric,
       replace(r.hi_s, ',', '')::numeric,
       'blog_posts/' || r.slug || ': "' || btrim(rtrim(r.item, ':')) || '" AED ' || r.lo_s || '-' || r.hi_s || ' per ' || r.unit_s,
       'blog_post',
       r.slug,
       r.as_of,
       'published'
  from raw r
  join _blog_cat c on r.slug like c.slug_like
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- B. kb_chunks -- "AED low-high per <unit>" lifted verbatim, with 140 characters of the sentence
--    it sat in kept as evidence so the rate can be read in context.
-- ---------------------------------------------------------------------------------------------
with hits as (
  select k.id, k.category as source_category, k.title, k.effective_date, k.content,
         (regexp_matches(
            k.content,
            'AED\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*[-–—]\s*([0-9][0-9,]*(?:\.[0-9]+)?)\+?\s*(?:per|/)\s*(sqm|sq m|m2|m²|square met[a-z]*|sqft|sq ft|linear met[a-z]*|lm|metre|meter|kg|ton|sheet|bag|piece|point|door|leaf|window|letter|set|kWp|kWh|TR|roll|item|hour|month|key|channel)',
            'g') ) as m
    from public.kb_chunks k
   where k.fts @@ to_tsquery('english', 'aed')
), typed as (
  select h.id, h.source_category, h.title, h.effective_date, h.content,
         h.m[1] as lo_s, h.m[2] as hi_s,
         case when lower(h.m[3]) ~ '^(sqm|sq m|m2|m²|square met)' then 'sqm'
              when lower(h.m[3]) ~ '^(sqft|sq ft)'                then 'sqft'
              when lower(h.m[3]) ~ '^(linear met|lm|metre|meter)' then 'lm'
              else h.m[3] end as unit,
         'AED ' || h.m[1] || '-' || h.m[2] || ' per ' || h.m[3] as needle
    from hits h
)
insert into public.price_benchmark
  (category, source_category, item, unit, basis_kind, low, high, evidence, source_kind, source_ref, as_of, confidence)
select distinct on (c.category, t.unit, t.lo_s, t.hi_s, t.id)
       c.category,
       t.source_category,
       nullif(btrim(coalesce(t.title, '')), ''),
       t.unit,
       'per_unit',
       replace(t.lo_s, ',', '')::numeric,
       replace(t.hi_s, ',', '')::numeric,
       btrim(substring(t.content
                       from greatest(1, coalesce(nullif(position(t.needle in t.content), 0), 1) - 160)
                       for 400)),
       'kb_chunk',
       t.id::text,
       t.effective_date::date,
       'machine_extracted'
  from typed t
  join lateral (
        select cs.category from public.category_specs cs where cs.category = t.source_category
        union
        select kc.category from _kb_cat kc where kc.source_category = t.source_category
       ) c on true
 where replace(t.hi_s, ',', '')::numeric >= replace(t.lo_s, ',', '')::numeric
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- C. THE GAPS. Every trade the marketplace covers that this file could not price, recorded by name
--    so the silence is a record rather than an absence.
-- ---------------------------------------------------------------------------------------------
insert into public.price_benchmark
  (category, unit, basis_kind, low, high, source_kind, source_ref, confidence, gap_reason)
select cs.category, 'none', 'none', null, null, 'gap', 'category_specs/' || cs.category, 'none',
       'No AED figure for this trade exists anywhere in the estate as of 9 Sep 2026: not in the 29 published cost guides in blog_posts, and not in the 901 unit rates extractable from kb_chunks. Deliberately not guessed. Fill from a supplier submittal, a real quote, or a sourced ingest -- never from memory.'
  from public.category_specs cs
 where not exists (select 1 from public.price_benchmark pb
                    where pb.category = cs.category and pb.source_kind <> 'gap')
on conflict do nothing;

commit;
