-- A BENCHMARK QUOTES THE SENTENCE ITS NUMBER CAME FROM (9 Sep 2026). Agent: ceo.
-- Repairs the kb_chunk half of the_price_benchmarks_come_out_of_the_estate_instead_of_out_of_nowhere.sql.
--
-- MEASURED after that file applied: 1,082 benchmark rows, and on 357 of them the `evidence` column
-- did NOT contain the number the row asserts. The figures themselves are correct -- they were lifted
-- from the chunk by the regex -- but the evidence window was anchored with
-- `position('AED '||lo||'-'||hi||' per '||unit  in  content)`, a reconstruction that only matches
-- when the source happened to use an ASCII hyphen, the word "per" rather than "/", and single
-- spaces. Where it did not match, position() returned 0 and the window fell back to the START of the
-- chunk, so the row quoted an opening paragraph that says nothing about its own rate.
--
-- That is the failure this table exists to prevent. The whole point of price_benchmark is that any
-- figure can be walked back to the sentence that published it; a row whose evidence does not contain
-- its own number is unverifiable, and an unverifiable number in a table read by the routine that
-- tells a customer their quote is fair is worse than no row at all.
--
-- THE FIX: split each chunk into sentences FIRST, run the rate regex per sentence, and keep that
-- sentence as the evidence. The match and the quote then come from the same string by construction
-- and cannot drift apart. Only source_kind='kb_chunk' rows are rebuilt; the blog_post rows are
-- assembled from their own captured cells and were already exact.
--
--   node scripts/apply_sql.mjs scripts/sql/a_benchmark_quotes_the_sentence_its_number_came_from.sql --apply --ddl

begin;

delete from public.price_benchmark where source_kind = 'kb_chunk';

create temporary table _kb_cat2 (source_category text, category text) on commit drop;
insert into _kb_cat2 (source_category, category) values
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

with sentences as (
  select k.id, k.category as source_category, k.title, k.effective_date, btrim(s.sent) as sent
    from public.kb_chunks k
    cross join lateral regexp_split_to_table(k.content, '(?:\.\s+|;\s+|\n+)') as s(sent)
   where k.fts @@ to_tsquery('english', 'aed')
     and s.sent like '%AED%'
), typed as (
  select s.id, s.source_category, s.title, s.effective_date, s.sent,
         m[1] as lo_s, m[2] as hi_s,
         case when lower(m[3]) ~ '^(sqm|sq m|m2|m²|square met)' then 'sqm'
              when lower(m[3]) ~ '^(sqft|sq ft)'                then 'sqft'
              when lower(m[3]) ~ '^(linear met|lm|metre|meter)' then 'lm'
              else lower(m[3]) end as unit
    from sentences s,
         lateral (select regexp_matches(
                    s.sent,
                    'AED\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*[-–—]\s*([0-9][0-9,]*(?:\.[0-9]+)?)\+?\s*(?:per|/)\s*(sqm|sq m|m2|m²|square met[a-z]*|sqft|sq ft|linear met[a-z]*|lm|metre|meter|kg|ton|sheet|bag|piece|point|door|leaf|window|letter|set|kWp|kWh|TR|roll|item|hour|month|key|channel)',
                    'g') as m) x
)
insert into public.price_benchmark
  (category, source_category, item, unit, basis_kind, low, high, evidence, source_kind, source_ref, as_of, confidence)
select distinct
       c.category,
       t.source_category,
       nullif(btrim(coalesce(t.title, '')), ''),
       t.unit,
       'per_unit',
       replace(t.lo_s, ',', '')::numeric,
       replace(t.hi_s, ',', '')::numeric,
       left(t.sent, 600),
       'kb_chunk',
       t.id::text,
       t.effective_date::date,
       'machine_extracted'
  from typed t
  join lateral (
        select cs.category from public.category_specs cs where cs.category = t.source_category
        union
        select kc.category from _kb_cat2 kc where kc.source_category = t.source_category
       ) c on true
 where replace(t.hi_s, ',', '')::numeric >= replace(t.lo_s, ',', '')::numeric
on conflict do nothing;

-- Gap rows are recomputed: a category that lost its only evidence in the rebuild must gain a gap
-- row, and a category that gained evidence must lose its gap row. Silence is a record here.
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
