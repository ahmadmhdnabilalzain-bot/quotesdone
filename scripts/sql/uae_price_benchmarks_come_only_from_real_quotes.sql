-- UAE PRICE BENCHMARKS COME ONLY FROM REAL QUOTES. Founder instruction 1009, upgrade 4. Seat: sales_engineer.
--
-- Every received quote line (and every accepted quote, counted separately) feeds a price range per
-- trade, item/spec and unit: median, interquartile range, count and last seen. Nothing is stored:
-- the range is computed from quote_items at read time, so it can never go stale and never holds a
-- figure the quotes do not.
--
-- NOT public.price_benchmark. That table holds SOURCED reference prices (source_kind, source_ref,
-- confidence) read by fn_price_confidence. This file owns OBSERVED market prices. The two subjects
-- stay apart so a quoted price is never mistaken for a published one, and vice versa.
--
-- RULES
--   * Demo and fixture data never count: fn_inquiry_is_demo, leads.is_demo and a 'ZZ DEMO' company
--     name each exclude a quote. p_include_demo exists ONLY so the aborted-transaction probe can
--     prove the arithmetic on ZZ DEMO rows; every routine a caller reaches passes false.
--   * A range is published only with >= 5 distinct quotes from >= 3 distinct suppliers. Below that
--     the answer is 'no_benchmark_yet' and no price is given - never an invented one. Min and max
--     are never published: each is exactly one supplier's figure.
--   * One observation per quote per (trade, item, unit): a supplier listing the same item twice in
--     one quote is one price (the average), not two votes.
--   * A comparison never benchmarks a line against its own enquiry's quotes.
--   * Flags are plain code. Well above = more than 1.5 x IQR above the upper quartile; well below =
--     more than 1.5 x IQR under the lower quartile (Tukey fences). The IQR used is at least 10% of
--     the median, so a tight market does not flag a 1% difference.
--
-- Probe: uae_price_benchmarks_come_only_from_real_quotes_probe.sql (ZZ DEMO, aborted transaction).

create or replace function public.fn_price_benchmark_key(p_description text, p_specification text)
returns text language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select nullif(btrim(regexp_replace(lower(coalesce(p_description, '') || ' ' || coalesce(p_specification, '')),
                                     '[^a-z0-9؀-ۿ.]+', ' ', 'g')), '')
$fn$;

create or replace function public.fn_price_benchmark_unit(p_unit text)
returns text language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(nullif(btrim(regexp_replace(lower(coalesce(p_unit, '')), '[^a-z0-9]+', '', 'g')), ''), 'each')
$fn$;

create or replace function public.fn_price_benchmark_observations(p_include_demo boolean default false,
                                                                  p_exclude_inquiry uuid default null)
returns table (trade text, item_key text, unit text, unit_price numeric, quote_id uuid,
               supplier_id bigint, accepted boolean, seen_at timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select lower(i.category), public.fn_price_benchmark_key(qi.description, qi.specification),
         public.fn_price_benchmark_unit(qi.unit),
         avg(coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0))),
         q.id, q.supplier_id, bool_or(q.status in ('accepted', 'won', 'revealed')), max(coalesce(qi.created_at, q.created_at))
    from public.quote_items qi
    join public.quotes q on q.id::text = qi.quote_id
    join public.inquiries i on i.id = q.inquiry_id
    left join public.leads l on l.id = q.supplier_id
   where coalesce(q.status, 'submitted') not in ('draft', 'withdrawn', 'cancelled')
     and q.supplier_id is not null
     and i.category is not null
     and coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)) > 0
     and public.fn_price_benchmark_key(qi.description, qi.specification) is not null
     and (p_exclude_inquiry is null or q.inquiry_id <> p_exclude_inquiry)
     and (p_include_demo or not (public.fn_inquiry_is_demo(q.inquiry_id)
                                 or coalesce(l.is_demo, false)
                                 or coalesce(l.company_name, '') ilike 'ZZ DEMO%'))
   group by 1, 2, 3, q.id, q.supplier_id
$fn$;

create or replace function public.fn_price_benchmarks(p_include_demo boolean default false,
                                                      p_exclude_inquiry uuid default null)
returns table (trade text, item_key text, unit text, median numeric, p25 numeric, p75 numeric,
               iqr numeric, quote_count int, supplier_count int, accepted_count int, last_seen timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select o.trade, o.item_key, o.unit,
         round((percentile_cont(0.5)  within group (order by o.unit_price))::numeric, 2),
         round((percentile_cont(0.25) within group (order by o.unit_price))::numeric, 2),
         round((percentile_cont(0.75) within group (order by o.unit_price))::numeric, 2),
         round((percentile_cont(0.75) within group (order by o.unit_price)
              - percentile_cont(0.25) within group (order by o.unit_price))::numeric, 2),
         count(distinct o.quote_id)::int, count(distinct o.supplier_id)::int,
         count(distinct o.quote_id) filter (where o.accepted)::int, max(o.seen_at)
    from public.fn_price_benchmark_observations(p_include_demo, p_exclude_inquiry) o
   group by 1, 2, 3
  having count(distinct o.quote_id) >= 5 and count(distinct o.supplier_id) >= 3
$fn$;

-- Pure code: judge one price against one benchmark row. p_bench is null when there is none.
create or replace function public.fn_price_benchmark_judge(p_price numeric, p_median numeric, p_p25 numeric,
                                                           p_p75 numeric, p_count int, p_suppliers int, p_unit text)
returns jsonb language plpgsql immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare v_iqr numeric; v_hi numeric; v_lo numeric; v_range text;
begin
  if p_median is null then
    return jsonb_build_object('status', 'no_benchmark_yet', 'reason', 'No benchmark yet: fewer than 5 quotes from 3 or more suppliers have priced this item.');
  end if;
  if p_price is null or p_price <= 0 then
    return jsonb_build_object('status', 'unpriced', 'reason', 'This line states no unit price, so it cannot be compared with the market range.');
  end if;
  v_iqr := greatest(p_p75 - p_p25, 0.10 * p_median);
  v_hi := p_p75 + 1.5 * v_iqr;  v_lo := greatest(p_p25 - 1.5 * v_iqr, 0);
  v_range := 'AED ' || to_char(p_p25, 'FM999,999,990.00') || ' to ' || to_char(p_p75, 'FM999,999,990.00')
          || ' per ' || p_unit || ' (middle half of ' || p_count || ' quotes from ' || p_suppliers
          || ' suppliers; median AED ' || to_char(p_median, 'FM999,999,990.00') || ')';
  if p_price > v_hi then
    return jsonb_build_object('status', 'well_above', 'pct_vs_median', round(100 * (p_price / p_median - 1)),
      'reason', 'Well above the UAE market range: AED ' || to_char(p_price, 'FM999,999,990.00') || ' is '
        || round(100 * (p_price / p_median - 1)) || '% over the median. Usual range ' || v_range
        || '. Ask the supplier what justifies it (brand, grade, scope or delivery).');
  elsif p_price < v_lo then
    return jsonb_build_object('status', 'well_below', 'pct_vs_median', round(100 * (p_price / p_median - 1)),
      'reason', 'Well below the UAE market range: AED ' || to_char(p_price, 'FM999,999,990.00') || ' is '
        || round(100 * (1 - p_price / p_median)) || '% under the median. Usual range ' || v_range
        || '. Check the specification, quantity and what is excluded before relying on it.');
  end if;
  return jsonb_build_object('status', 'within', 'pct_vs_median', round(100 * (p_price / p_median - 1)),
    'reason', 'Within the UAE market range. Usual range ' || v_range || '.');
end $fn$;

-- What the comparison reads: every priced line of every non-draft quote on this enquiry, judged
-- against benchmarks built from every OTHER enquiry.
create or replace function public.fn_price_benchmark_flags_for_inquiry(p_inquiry_id uuid, p_include_demo boolean default false)
returns jsonb language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with b as (select * from public.fn_price_benchmarks(p_include_demo, p_inquiry_id)),
  lines as (
    select q.id as quote_id, qi.line_no, qi.description, lower(i.category) as trade,
           public.fn_price_benchmark_key(qi.description, qi.specification) as item_key,
           public.fn_price_benchmark_unit(qi.unit) as unit,
           coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)) as price
      from public.quotes q
      join public.inquiries i on i.id = q.inquiry_id
      join public.quote_items qi on qi.quote_id = q.id::text
     where q.inquiry_id = p_inquiry_id and coalesce(q.status, 'submitted') <> 'draft')
  select coalesce(jsonb_agg(jsonb_build_object('quote_id', l.quote_id, 'line_no', l.line_no, 'description', l.description, 'unit', l.unit)
           || public.fn_price_benchmark_judge(round(l.price, 2), b.median, b.p25, b.p75, b.quote_count, b.supplier_count, l.unit)
           || case when b.median is null then '{}'::jsonb else jsonb_build_object('benchmark',
                jsonb_build_object('median', b.median, 'p25', b.p25, 'p75', b.p75, 'iqr', b.iqr, 'count', b.quote_count, 'last_seen', b.last_seen)) end
           order by l.quote_id, l.line_no), '[]'::jsonb)
    from lines l
    left join b on b.trade = l.trade and b.item_key = l.item_key and b.unit = l.unit
$fn$;

revoke execute on function public.fn_price_benchmark_observations(boolean, uuid) from public, anon, authenticated;
revoke execute on function public.fn_price_benchmarks(boolean, uuid) from public, anon, authenticated;
revoke execute on function public.fn_price_benchmark_flags_for_inquiry(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.fn_price_benchmark_judge(numeric, numeric, numeric, numeric, int, int, text) from public, anon, authenticated;
revoke execute on function public.fn_price_benchmark_key(text, text) from public, anon, authenticated;
revoke execute on function public.fn_price_benchmark_unit(text) from public, anon, authenticated;
