-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710214222   name: marketplace_intelligence_views
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.v_mkt_response_by_category as
with fq as (
  select i.id, i.category, i.created_at,
         (select min(q.created_at) from public.quotes q where q.inquiry_id=i.id) as first_quote_at
  from public.inquiries i
  where i.category is not null
)
select category,
       count(*) as rfqs,
       count(first_quote_at) as rfqs_quoted,
       round(avg(extract(epoch from (first_quote_at - created_at))/3600.0)
             filter (where first_quote_at is not null)::numeric, 1) as avg_first_quote_hrs,
       round((count(*) filter (where first_quote_at is null))::numeric / nullif(count(*),0) * 100, 1) as no_quote_pct
from fq
group by category
order by avg_first_quote_hrs desc nulls last;
revoke all on public.v_mkt_response_by_category from anon, authenticated;

create or replace view public.v_mkt_brand_by_category as
select i.category, qi.brand,
       count(*) as line_count,
       count(distinct q.supplier_id) as suppliers,
       round(sum(coalesce(qi.amount,0))::numeric, 2) as total_amount
from public.quote_items qi
join public.quotes q on q.id::text = qi.quote_id::text
join public.inquiries i on i.id = q.inquiry_id
where qi.brand is not null and btrim(qi.brand) <> '' and i.category is not null
group by i.category, qi.brand
order by i.category, line_count desc;
revoke all on public.v_mkt_brand_by_category from anon, authenticated;

create or replace view public.v_mkt_over_budget as
select id as inquiry_id, category, budget_aed, min_quote, (min_quote - budget_aed) as overrun, created_at
from (
  select i.id, i.category, i.created_at,
         nullif(regexp_replace(coalesce((regexp_match(i.budget,'([0-9][0-9,\.]{2,})'))[1],''),'[^0-9]','','g'),'')::numeric as budget_aed,
         (select min(q.quote_amount) from public.quotes q where q.inquiry_id=i.id and coalesce(q.status,'')<>'draft') as min_quote
  from public.inquiries i
  where i.budget is not null and btrim(i.budget) <> ''
) s
where budget_aed is not null and budget_aed >= 100 and min_quote is not null and min_quote > budget_aed
order by overrun desc;
revoke all on public.v_mkt_over_budget from anon, authenticated;

create or replace view public.v_mkt_underpriced as
select q.id as quote_id, q.inquiry_id, i.category, q.supplier_id, q.quote_amount,
       (x.pc->>'median') as category_median, q.created_at
from public.quotes q
join public.inquiries i on i.id = q.inquiry_id
cross join lateral (select public.fn_price_confidence(i.category, q.quote_amount) as pc) x
where coalesce(q.status,'') <> 'draft' and i.category is not null
  and (x.pc->>'band') = 'suspiciously_low'
order by q.created_at desc;
revoke all on public.v_mkt_underpriced from anon, authenticated;
