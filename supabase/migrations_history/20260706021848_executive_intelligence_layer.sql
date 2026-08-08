-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706021848   name: executive_intelligence_layer
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists exec_reports (
  id bigint generated always as identity primary key,
  officer text not null,
  period text,
  summary text,
  findings jsonb default '[]'::jsonb,
  recommendations jsonb default '[]'::jsonb,
  metrics jsonb default '{}'::jsonb,
  status text not null default 'new',
  created_at timestamptz default now()
);
create index if not exists exec_reports_officer on exec_reports(officer, created_at desc);
alter table exec_reports enable row level security;
revoke all on exec_reports from anon, authenticated;

-- STRATEGY: demand vs supply, coverage gaps, funnel
create or replace function fn_strategy_metrics() returns jsonb language plpgsql stable as $$
declare res jsonb;
begin
  with dem as (select category, count(*) rfqs from inquiries where created_at > now()-interval '90 days' and category is not null group by category),
  sup as (select i.category, count(distinct q.supplier_id) sups from quotes q join inquiries i on i.id=q.inquiry_id where q.created_at > now()-interval '90 days' and i.category is not null group by i.category)
  select jsonb_build_object(
    'under_supplied', (select coalesce(jsonb_agg(x order by x.rfqs desc),'[]'::jsonb) from (
        select d.category, d.rfqs, coalesce(s.sups,0) as active_suppliers
        from dem d left join sup s on s.category=d.category
        where coalesce(s.sups,0) < greatest(2, d.rfqs/3) order by d.rfqs desc limit 12) x),
    'coverage', jsonb_build_object(
        'categories_total', (select count(*) from category_specs),
        'with_requirements', (select count(*) from category_specs where supplier_requirements is not null),
        'with_playbook', (select count(distinct category) from qualification_playbooks where status='active'),
        'regulation_category_tags', (select count(distinct c) from regulations r, unnest(coalesce(r.categories,'{}')) c where r.status='active')),
    'funnel', (select coalesce(fn_marketplace_analytics(),'{}'::jsonb))
  ) into res;
  return res;
end $$;

-- OPERATIONS: bottlenecks & SLA
create or replace function fn_ops_metrics() returns jsonb language plpgsql stable as $$
declare res jsonb;
begin
  select jsonb_build_object(
    'open_rfqs_no_quotes_7d', (select count(*) from inquiries i where i.created_at < now()-interval '7 days'
        and coalesce(i.status,'') not in ('completed','cancelled','closed')
        and not exists (select 1 from quotes q where q.inquiry_id=i.id)),
    'matched_not_quoted', (select count(*) from inquiry_matches m
        where not exists (select 1 from quotes q where q.inquiry_id=m.inquiry_id and q.supplier_id=m.supplier_id)),
    'avg_first_quote_hours', (select (fn_marketplace_analytics()->>'avg_first_quote_hours')::numeric),
    'response_rate_pct', (select (fn_marketplace_analytics()->>'response_rate_pct')::numeric),
    'pipeline_by_stage', (select coalesce(jsonb_agg(jsonb_build_object('stage',label,'deals',deals,'value',value) order by sort_order),'[]'::jsonb) from crm_pipeline_report),
    'overdue_activities', (select overdue_activities from crm_deal_kpis)
  ) into res;
  return res;
end $$;

-- PROCUREMENT QUALITY
create or replace function fn_quality_metrics() returns jsonb language plpgsql stable as $$
declare res jsonb;
begin
  select jsonb_build_object(
    'rfqs_missing_fields_30d', (select count(*) from inquiries where created_at > now()-interval '30 days'
        and (category is null or coalesce(summary,'')='' or emirate is null)),
    'rfqs_few_suppliers_30d', (select count(*) from inquiries i where i.created_at > now()-interval '30 days'
        and (select count(*) from inquiry_matches m where m.inquiry_id=i.id) < 3),
    'avg_quote_completeness', (select round(avg((quality->>'score')::numeric),1) from quotes where quality is not null),
    'low_quality_quotes', (select count(*) from quotes where (quality->>'score')::numeric < 50),
    'rfqs_not_comparable', (select count(*) from (select inquiry_id from quotes group by inquiry_id having count(*)=1) z)
  ) into res;
  return res;
end $$;

-- DATA SCIENCE: trends & pricing
create or replace function fn_data_metrics() returns jsonb language plpgsql stable as $$
declare res jsonb;
begin
  select jsonb_build_object(
    'category_growth', (select coalesce(fn_marketplace_analytics()->'category_growth','[]'::jsonb)),
    'competitive_categories', (select coalesce(fn_marketplace_analytics()->'competitive_categories','[]'::jsonb)),
    'price_spread', (select coalesce(jsonb_agg(jsonb_build_object('category',category,'n',n,'median',median,'p25',p25,'p75',p75) order by n desc),'[]'::jsonb)
        from (select * from category_price_stats order by n desc limit 10) z),
    'monthly_volume', (select coalesce(jsonb_agg(jsonb_build_object('month',m,'rfqs',c) order by m),'[]'::jsonb)
        from (select to_char(date_trunc('month',created_at),'YYYY-MM') m, count(*) c from inquiries where created_at > now()-interval '6 months' group by 1) z)
  ) into res;
  return res;
end $$;

-- VOICE (product/ux + customer success)
create or replace function fn_voice_metrics() returns jsonb language plpgsql stable as $$
declare res jsonb;
begin
  select jsonb_build_object(
    'low_ratings_90d', (select count(*) from reviews where created_at > now()-interval '90 days' and rating is not null and rating <= 2),
    'recent_low_comments', (select coalesce(jsonb_agg(comment),'[]'::jsonb) from (select comment from reviews where rating <= 2 and coalesce(comment,'')<>'' order by created_at desc limit 8) z),
    'disputes', (select coalesce(jsonb_object_agg(coalesce(refund_status,'none'), c),'{}'::jsonb) from (select refund_status, count(*) c from transactions group by refund_status) z),
    'abandoned_rfqs', (select (fn_marketplace_analytics()->>'abandoned_rfqs')::int),
    'repeat_customers', (select count(*) from (select customer_id from inquiries where customer_id is not null group by customer_id having count(*)>1) z)
  ) into res;
  return res;
end $$;

revoke all on function fn_strategy_metrics() from anon, authenticated;
revoke all on function fn_ops_metrics() from anon, authenticated;
revoke all on function fn_quality_metrics() from anon, authenticated;
revoke all on function fn_data_metrics() from anon, authenticated;
revoke all on function fn_voice_metrics() from anon, authenticated;
