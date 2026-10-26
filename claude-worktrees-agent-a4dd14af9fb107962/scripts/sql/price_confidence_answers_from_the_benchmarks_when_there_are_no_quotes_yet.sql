-- PRICE CONFIDENCE ANSWERS FROM THE BENCHMARKS WHEN THERE ARE NO QUOTES YET (9 Sep 2026).
-- Agent: ceo. Closes the cold start named in founder instruction #15.
--
-- MEASURED BEFORE THIS FILE. fn_price_confidence read exactly one thing: `category_price_stats`, a
-- VIEW over `quotes` JOIN `inquiries`. quotes = 0 rows and inquiries = 0 rows, so the view is empty
-- and the function has returned band='insufficient_data' on every call it has ever served. Four
-- surfaces are dark behind it -- fn_negotiation_guidance (which writes the English and Arabic
-- supplier emails), fn_customer_savings, fn_customer_decision_support and fn_decide(p_kind='price').
-- The sales engineer's whole purpose is to judge whether a quote is fair, and it had no number to
-- judge against and no way to get one before the first quote arrived. That is a cold start, and a
-- cold start is not fixed by waiting.
--
-- WHAT CHANGES. The live-quote path is untouched and still wins whenever it can answer: quotes are
-- what this company actually transacted, and nothing published outranks that. Only when the live
-- path cannot answer does the function fall through to public.price_benchmark -- 1,082 UAE rates
-- lifted verbatim from the company's own 29 published cost guides and from kb_chunks, each row
-- carrying the sentence it came from.
--
-- WHAT DELIBERATELY DOES NOT CHANGE:
--   * `category_price_stats` still means QUOTES and nothing else. Union-ing benchmark rows into it
--     was considered and rejected: `n` would then mean two different things, and the three callers
--     that read the view directly and gate on n>=3/4/5 would silently start treating a published
--     range as a sample of real quotes. Those callers stay empty until real quotes exist, and that
--     is recorded as a gap rather than papered over.
--   * `n` is never inflated to clear a downstream gate. It is the true count of evidence bands, and
--     the result carries `n_quotes` alongside it, which is 0 for every benchmark answer, so nothing
--     downstream can mistake one for the other.
--   * `typical` is not invented. price_benchmark stores only what a source published; the central
--     figure here is the median of the published low and high values and the result says exactly
--     that in `basis`.
--
-- THE UNIT PROBLEM IS ANSWERED, NOT HIDDEN. quotes.quote_amount is a whole-job total; most evidence
-- in the estate is AED per m2 / per lm / per point / per door. Comparing the two without a quantity
-- is meaningless, so:
--   * with no quantity, only 'job'-basis benchmarks are compared, and if a category has none the
--     function REFUSES with band='benchmark_is_per_unit' and returns the per-unit bands it does
--     hold, so the caller can supply a quantity rather than receive a wrong answer;
--   * the new four-argument overload takes a quantity and a unit and compares the derived unit rate.
-- Every answer carries a `reference` block of the per-unit bands for the category regardless, so the
-- sales engineer can always see the trade's real shape even when the headline call refuses.
--
--   node scripts/apply_sql.mjs scripts/sql/price_confidence_answers_from_the_benchmarks_when_there_are_no_quotes_yet.sql --apply --ddl

begin;

create or replace function public.fn_price_confidence(
  p_category text,
  p_amount   numeric,
  p_quantity numeric,
  p_unit     text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  s          record;
  iqr        numeric;
  z          numeric;
  conf       int;
  band       text;
  v_basis    text;
  v_unit     text;
  v_rate     numeric;
  v_n        int;
  v_p25      numeric;
  v_med      numeric;
  v_p75      numeric;
  v_srcs     jsonb;
  v_asof     date;
  v_ref      jsonb;
  v_items    jsonb;
  v_conf_lbl text;
begin
  -- Always available, whatever happens below: what this trade's per-unit bands actually look like.
  select coalesce(jsonb_agg(jsonb_build_object(
           'unit', r.unit, 'low', r.lo, 'high', r.hi, 'n', r.n, 'source', r.src) order by r.n desc), '[]'::jsonb)
    into v_ref
    from (select pb.unit, min(pb.low) lo, max(pb.high) hi, count(*) n,
                 case when bool_or(pb.source_kind = 'blog_post') then 'quotesdone_cost_guide' else 'estate_extract' end src
            from public.price_benchmark pb
           where pb.category = p_category and pb.source_kind <> 'gap' and pb.basis_kind = 'per_unit'
           group by pb.unit) r;

  -- THE NAMED BANDS. A category-wide answer is necessarily wide, because one category legitimately
  -- holds a plain gypsum ceiling at AED 35-70/m2 and a demountable modular partition at AED
  -- 900-2,000/m2. Widening the IQR is the honest response to that -- but it is not a judgement, and
  -- the judgement lives in the item name. So every answer also carries the individual named bands,
  -- which is the row a sales engineer actually reads before saying a quote is high.
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.item, 'unit', i.unit, 'low', i.low, 'high', i.high,
           'source', i.source_kind || ':' || i.source_ref, 'as_of', i.as_of)
           order by i.low), '[]'::jsonb)
    into v_items
    from (select distinct on (pb.item, pb.unit) pb.item, pb.unit, pb.low, pb.high,
                 pb.source_kind, pb.source_ref, pb.as_of
            from public.price_benchmark pb
           where pb.category = p_category and pb.source_kind <> 'gap' and pb.item is not null
           order by pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end)
           limit 40) i;

  -- ---------------------------------------------------------------------------------------------
  -- 1. LIVE QUOTES FIRST. What the company actually transacted outranks anything published.
  -- ---------------------------------------------------------------------------------------------
  select * into s from public.category_price_stats where category = p_category;
  if s is not null and s.n >= 4 then
    iqr := nullif(s.p75 - s.p25, 0);
    if iqr is null then iqr := nullif(s.sd, 0); end if;
    if iqr is not null then
      z := abs(p_amount - s.median) / iqr;
      conf := greatest(5, least(99, round(100 * exp(-0.6 * z))::int));
      if    p_amount < s.p25 - 1.5 * iqr           then band := 'suspiciously_low';
      elsif p_amount > s.p75 + 1.5 * iqr           then band := 'suspiciously_high';
      elsif p_amount between s.p25 and s.p75       then band := 'fair';
      else                                              band := 'within_range';
      end if;
      return jsonb_build_object(
        'confidence', conf, 'band', band, 'median', s.median, 'p25', s.p25, 'p75', s.p75,
        'n', s.n, 'n_quotes', s.n, 'basis', 'live_quotes', 'reference_bands', v_ref, 'item_bands', v_items);
    end if;
  end if;

  -- ---------------------------------------------------------------------------------------------
  -- 2. THE BENCHMARKS. Published company cost guides preferred over machine-extracted estate text;
  --    a category never mixes the two, so the caller always knows which grade of evidence answered.
  -- ---------------------------------------------------------------------------------------------
  if p_quantity is not null and p_quantity > 0 then
    -- A quantity was supplied, so the comparison is a UNIT RATE against per-unit benchmarks.
    select coalesce(p_unit, (select pb.unit from public.price_benchmark pb
                              where pb.category = p_category and pb.source_kind <> 'gap'
                                and pb.basis_kind = 'per_unit'
                              group by pb.unit order by count(*) desc limit 1))
      into v_unit;
    v_rate := p_amount / p_quantity;
    v_basis := 'published_range_midpoint_per_unit';
  else
    v_unit  := null;
    v_rate  := p_amount;
    v_basis := 'published_range_midpoint_per_job';
  end if;

  -- count(*) = 0 FIRST, and it is not defensive noise. bool_or over an empty set returns NULL, and
  -- `case when NULL then 'blog_post' else 'kb_chunk' end` is 'kb_chunk' -- so without this guard a
  -- category with NO benchmark at all reports that it has kb_chunk evidence, and the refusal that
  -- should say "the estate holds no price for this trade" never fires. Measured: elevators, a trade
  -- whose gap row this file's sibling deliberately recorded, came back 'benchmark_has_no_spread'
  -- instead of the gap refusal. Same family as least(100.0, NULL) = 100.0.
  select case when count(*) = 0 then null
              when bool_or(pb.source_kind = 'blog_post') then 'blog_post'
              else 'kb_chunk' end
    into v_conf_lbl
    from public.price_benchmark pb
   where pb.category = p_category and pb.source_kind <> 'gap'
     and (case when v_unit is null then pb.basis_kind = 'job' else pb.basis_kind = 'per_unit' and pb.unit = v_unit end);

  if v_conf_lbl is null then
    return jsonb_build_object(
      'confidence', null,
      'band', case when v_ref = '[]'::jsonb then 'insufficient_data' else 'benchmark_is_per_unit' end,
      'n', 0, 'n_quotes', 0, 'basis', 'no_matching_benchmark',
      'refusal', case
        when v_ref = '[]'::jsonb then
          'No AED evidence for this trade exists anywhere in the estate, and a figure was deliberately not guessed. See price_benchmark where source_kind = ''gap''.'
        else
          'This trade is priced per unit in every piece of evidence the estate holds, and no quantity was supplied, so a whole-job amount cannot be judged against it. Pass p_quantity (and optionally p_unit), or read reference_bands.' end,
      'reference_bands', v_ref, 'item_bands', v_items);
  end if;

  select count(*),
         percentile_cont(0.25) within group (order by v.x)::numeric,
         percentile_cont(0.50) within group (order by v.x)::numeric,
         percentile_cont(0.75) within group (order by v.x)::numeric,
         max(v.as_of),
         coalesce(jsonb_agg(distinct v.src), '[]'::jsonb)
    into v_n, v_p25, v_med, v_p75, v_asof, v_srcs
    from (
      select unnest(array[pb.low, pb.high]) as x, pb.as_of,
             pb.source_kind || ':' || pb.source_ref as src
        from public.price_benchmark pb
       where pb.category = p_category
         and pb.source_kind = v_conf_lbl
         and (case when v_unit is null then pb.basis_kind = 'job'
                   else pb.basis_kind = 'per_unit' and pb.unit = v_unit end)
    ) v;

  -- v_n counts low/high endpoints, two per band. Report the number of BANDS, which is what a reader
  -- means by "how much evidence is behind this".
  v_n := v_n / 2;

  iqr := nullif(v_p75 - v_p25, 0);
  if iqr is null then
    return jsonb_build_object('confidence', null, 'band', 'insufficient_data', 'n', v_n, 'n_quotes', 0,
      'basis', 'benchmark_has_no_spread', 'reference_bands', v_ref, 'item_bands', v_items);
  end if;

  z := abs(v_rate - v_med) / iqr;
  conf := greatest(5, least(99, round(100 * exp(-0.6 * z))::int));
  if    v_rate < v_p25 - 1.5 * iqr       then band := 'suspiciously_low';
  elsif v_rate > v_p75 + 1.5 * iqr       then band := 'suspiciously_high';
  elsif v_rate between v_p25 and v_p75   then band := 'fair';
  else                                        band := 'within_range';
  end if;

  return jsonb_build_object(
    'confidence', conf,
    'band', band,
    'median', round(v_med, 0), 'p25', round(v_p25, 0), 'p75', round(v_p75, 0),
    'n', v_n,
    -- 0, always, on this path. A benchmark is published evidence, never a sample of this company's
    -- own quotes, and a caller that gates on real trading history must be able to see the difference.
    'n_quotes', 0,
    'basis', v_basis,
    'evidence_grade', case when v_conf_lbl = 'blog_post' then 'published_by_quotesdone' else 'extracted_from_estate' end,
    'unit', coalesce(v_unit, 'job'),
    'compared_rate', round(v_rate, 2),
    'as_of', v_asof,
    'sources', v_srcs,
    'reference_bands', v_ref, 'item_bands', v_items);
end
$function$;

revoke execute on function public.fn_price_confidence(text, numeric, numeric, text) from public;

-- The two-argument signature every existing caller uses. CREATE OR REPLACE, so its ACL is preserved
-- and no caller changes. It is now a delegation and holds no logic of its own -- one implementation,
-- one place to be wrong.
create or replace function public.fn_price_confidence(p_category text, p_amount numeric)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select public.fn_price_confidence(p_category, p_amount, null::numeric, null::text);
$function$;

commit;
