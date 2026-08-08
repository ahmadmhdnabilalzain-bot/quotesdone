-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706003512   name: price_confidence
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #10 Price confidence: per-category price distribution + a scoring function
create or replace view category_price_stats as
select i.category,
  count(qq.quote_amount)                                                          as n,
  round(percentile_cont(0.5)  within group (order by qq.quote_amount)::numeric,0) as median,
  round(percentile_cont(0.25) within group (order by qq.quote_amount)::numeric,0) as p25,
  round(percentile_cont(0.75) within group (order by qq.quote_amount)::numeric,0) as p75,
  round(avg(qq.quote_amount),0)                                                   as mean,
  round(coalesce(stddev_pop(qq.quote_amount),0),0)                                as sd
from quotes qq join inquiries i on i.id = qq.inquiry_id
where qq.quote_amount is not null and qq.quote_amount > 0 and i.category is not null
group by i.category;

revoke all on category_price_stats from anon, authenticated;

-- Returns a fair-price confidence (%) + band for a quote amount in a category.
create or replace function fn_price_confidence(p_category text, p_amount numeric)
returns jsonb language plpgsql stable as $$
declare s record; iqr numeric; z numeric; conf int; band text;
begin
  select * into s from category_price_stats where category = p_category;
  if s is null or s.n < 4 then
    return jsonb_build_object('confidence', null, 'band', 'insufficient_data', 'n', coalesce(s.n,0));
  end if;
  iqr := nullif(s.p75 - s.p25, 0);
  if iqr is null then iqr := nullif(s.sd, 0); end if;
  if iqr is null then
    return jsonb_build_object('confidence', null, 'band', 'insufficient_data', 'n', s.n);
  end if;
  z := abs(p_amount - s.median) / iqr;
  conf := greatest(5, least(99, round(100 * exp(-0.6 * z))::int));
  if    p_amount < s.p25 - 1.5*iqr then band := 'suspiciously_low';
  elsif p_amount > s.p75 + 1.5*iqr then band := 'suspiciously_high';
  elsif p_amount between s.p25 and s.p75 then band := 'fair';
  else band := 'within_range';
  end if;
  return jsonb_build_object('confidence', conf, 'band', band,
    'median', s.median, 'p25', s.p25, 'p75', s.p75, 'n', s.n);
end $$;
