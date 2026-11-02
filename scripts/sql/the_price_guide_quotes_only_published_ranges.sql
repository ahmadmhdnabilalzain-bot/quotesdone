-- Seat: customer_support
-- customer_support, 2 Nov 2026 (founder ledger 1464: the agents must never hallucinate; a quoted price range must come from a real source).
--
-- MEASURED. The browser proof asked the homepage widget "How much will it cost me to fit a 3 metre wardrobe in Dubai?" and it
-- answered "built-in joinery in the UAE is published at roughly AED 2,200 to 6,500 per linear metre". That range is
-- price_benchmark id 1454: category carpentry-joinery, source_kind kb_chunk, confidence machine_extracted, evidence "Dubai
-- KITCHENS run approx AED 2,200-6,500 per linear metre installed depending on finish". A kitchen figure, scraped by a machine
-- from a knowledge chunk and filed under all of joinery, was quoted to a visitor as the published range for a wardrobe.
--
-- WHAT. fn_price_brief() (the PUBLISHED PRICE GUIDE block of every reply's brief) now carries only rows whose confidence is
-- 'published' (the company's own guide and the blog tables it publishes). A machine-extracted row stays in the table for
-- review; it is no longer a number the agents can state. Everything else in the function is unchanged
-- (the_company_brief_carries_the_published_price_ranges.sql).
-- NOT APPLIED BY THIS SESSION: applied at merge, per scripts/sql/MANIFEST.txt.
create or replace function public.fn_price_brief()
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with lines as (
    select distinct on (pb.category, pb.item, pb.unit)
           pb.category, pb.item,
           '- ' || pb.category || ': ' || pb.item || ': AED '
             || trim(to_char(pb.low, 'FM999999990.##'))
             || case when pb.high is not null and pb.high <> pb.low then ' to ' || trim(to_char(pb.high, 'FM999999990.##')) else '' end
             || coalesce(' per ' || nullif(nullif(pb.unit, ''), 'none'), '')
             || coalesce(' (as of ' || pb.as_of::text || ')', '') as line
      from public.price_benchmark pb
     where pb.source_kind <> 'gap' and pb.item is not null and pb.low is not null
       and pb.confidence = 'published'
     order by pb.category, pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end), pb.as_of desc nulls last, pb.id
  )
  select '## PUBLISHED PRICE GUIDE (UAE ranges QuotesDone publishes; quote them as a range and say it is a guide, not a quotation — suppliers price the work)'
      || E'\n' || coalesce((select string_agg(line, E'\n' order by category, item) from lines), '')
      || coalesce(E'\nNo published range (say so, never estimate): '
                  || (select string_agg(distinct category, ', ') from public.price_benchmark where source_kind = 'gap'), '');
$fn$;

revoke execute on function public.fn_price_brief() from public, anon, authenticated;

-- PROBE (reads only). The block still carries a guide, and the kitchen figure mislabelled as joinery is not in it.
select case
  when public.fn_price_brief() !~ 'PUBLISHED PRICE GUIDE' then 'PROBE FAILED: no header'
  when (select count(*) from regexp_matches(public.fn_price_brief(), E'\n- ', 'g')) < 20 then 'PROBE FAILED: fewer than 20 published price lines'
  when public.fn_price_brief() ~ 'carpentry-joinery: Carpentry & Joinery specialist[^\n]*2200 to 6500' then 'PROBE FAILED: the machine-extracted kitchen range is still quoted'
  else 'PROBE OK'
end as verdict;
