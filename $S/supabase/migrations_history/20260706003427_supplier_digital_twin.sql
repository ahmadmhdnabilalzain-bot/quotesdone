-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706003427   name: supplier_digital_twin
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #12 Supplier Digital Twin: a continuously-derived operational profile per supplier
create or replace view supplier_twin as
select
  l.id                                   as supplier_id,
  l.company_name,
  l.emirate                              as home_emirate,
  l.categories                           as specialties,
  sp.matched, sp.quoted, sp.won,
  sp.quote_rate, sp.win_rate, sp.perf_score,
  rep.reputation_index, rep.overall as avg_rating, rep.review_count,
  rep.disputes, rep.dispute_rate_pct,
  q.quotes_count,
  q.avg_quote_value, q.min_quote_value, q.max_quote_value,
  q.avg_response_hours,
  q.busiest_month,
  wq.typical_project_size,
  pr.preferred_regions
from leads l
left join supplier_perf sp        on sp.supplier_id = l.id
left join supplier_reputation rep on rep.supplier_id = l.id
left join lateral (
  select count(*)                                                              as quotes_count,
         round(avg(qq.quote_amount),0)                                         as avg_quote_value,
         min(qq.quote_amount)                                                  as min_quote_value,
         max(qq.quote_amount)                                                  as max_quote_value,
         round(avg(extract(epoch from (qq.created_at - i.created_at))/3600.0)::numeric,1) as avg_response_hours,
         mode() within group (order by extract(month from qq.created_at)::int) as busiest_month
  from quotes qq join inquiries i on i.id = qq.inquiry_id
  where qq.supplier_id = l.id
) q on true
left join lateral (
  select round(avg(qq.quote_amount),0) as typical_project_size
  from quotes qq join inquiries i on i.id = qq.inquiry_id
  where qq.supplier_id = l.id and i.hired_supplier_id = l.id
) wq on true
left join lateral (
  select array_agg(distinct i.emirate) filter (where i.emirate is not null) as preferred_regions
  from quotes qq join inquiries i on i.id = qq.inquiry_id
  where qq.supplier_id = l.id
) pr on true;

revoke all on supplier_twin from anon, authenticated;
