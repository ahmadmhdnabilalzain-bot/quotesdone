-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706003936   name: marketplace_analytics
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #2 Marketplace analytics: single function returning the admin live-metrics bundle
create or replace function fn_marketplace_analytics() returns jsonb language plpgsql stable as $$
declare res jsonb;
begin
  with q_first as (  -- first quote latency per rfq
    select i.id, min(qq.created_at) as first_quote_at, i.created_at, i.category
    from inquiries i left join quotes qq on qq.inquiry_id = i.id group by i.id, i.created_at, i.category
  ),
  spread as (  -- savings potential per rfq with >=2 quotes
    select inquiry_id, min(quote_amount) lo, max(quote_amount) hi, count(*) n
    from quotes where quote_amount > 0 group by inquiry_id having count(*) >= 2
  )
  select jsonb_build_object(
    'rfqs_today',   (select count(*) from inquiries where created_at >= date_trunc('day', now())),
    'rfqs_7d',      (select count(*) from inquiries where created_at >= now() - interval '7 days'),
    'rfqs_30d',     (select count(*) from inquiries where created_at >= now() - interval '30 days'),
    'avg_first_quote_hours', (select round(avg(extract(epoch from (first_quote_at - created_at))/3600.0)::numeric,1) from q_first where first_quote_at is not null),
    'response_rate_pct', (
      select case when count(*)>0 then round(100.0 * count(*) filter (where exists (
        select 1 from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id)) / count(*), 1) else null end
      from inquiry_matches m),
    'avg_savings_pct', (select round(avg(case when hi>0 then 100.0*(hi-lo)/hi else 0 end)::numeric,1) from spread),
    'abandoned_rfqs', (select count(*) from inquiries i where i.created_at < now() - interval '7 days'
                        and coalesce(i.status,'') not in ('completed','cancelled')
                        and not exists (select 1 from quotes q where q.inquiry_id = i.id)),
    'active_suppliers_30d', (select count(distinct supplier_id) from quotes where created_at >= now() - interval '30 days'),
    'supplier_capacity_avg', (select round(avg(c)::numeric,1) from (select supplier_id, count(*) c from quotes where created_at >= now() - interval '30 days' group by supplier_id) s),
    'competitive_categories', (
      select coalesce(jsonb_agg(x order by x.avg_quotes desc), '[]'::jsonb) from (
        select i.category, round(avg(qc.c)::numeric,2) as avg_quotes, count(*) as rfqs
        from inquiries i join (select inquiry_id, count(*) c from quotes group by inquiry_id) qc on qc.inquiry_id=i.id
        where i.created_at >= now() - interval '90 days' and i.category is not null
        group by i.category order by avg_quotes desc limit 8) x),
    'category_growth', (
      select coalesce(jsonb_agg(g), '[]'::jsonb) from (
        select category,
          count(*) filter (where created_at >= now() - interval '30 days') as this_30d,
          count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days') as prev_30d
        from inquiries where category is not null and created_at >= now() - interval '60 days'
        group by category order by this_30d desc limit 10) g),
    'generated_at', now()
  ) into res;
  return res;
end $$;

select fn_marketplace_analytics() as analytics;
