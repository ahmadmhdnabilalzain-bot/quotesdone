-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709085728   name: wire_meta_into_marketing_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

drop view if exists public.marketing_kpis;
create view public.marketing_kpis as
with f as (select funnel_metrics(30) fm),
mi as (
  select coalesce(sum(spend),0) as meta_spend, coalesce(sum(impressions),0) as meta_impr,
         coalesce(sum(clicks),0) as meta_clicks, coalesce(sum(results),0) as meta_results,
         count(*) filter (where effective_status='ACTIVE') as meta_active
  from meta_insights where time_window='last_30d' and campaign_name ilike '%quotesdone%'
)
select
  (fm->>'inquiries')::int as inquiries_30d,
  (fm->>'matched')::int as matched_30d,
  (fm->>'quoted')::int as quoted_30d,
  (fm->>'revealed')::int as revealed_30d,
  (fm->>'reveal_fees')::numeric as revenue_30d,
  case when (fm->>'inquiries')::int>0 then round(100.0*(fm->>'quoted')::int/(fm->>'inquiries')::int,1) else null end as inq_to_quote_pct,
  case when (fm->>'quoted')::int>0 then round(100.0*(fm->>'revealed')::int/(fm->>'quoted')::int,1) else null end as quote_to_reveal_pct,
  (select count(*) from blog_posts where published) as blog_published,
  (select count(*) from blog_posts) as blog_total,
  (select count(*) from content_drafts where coalesce(status,'') not in ('published','discarded')) as drafts_pending,
  (select count(*) from social_posts where coalesce(status,'') in ('staged','scheduled','draft','pending')) as social_staged,
  (select count(*) from social_posts where coalesce(status,'') in ('published','sent')) as social_published,
  (select count(*) from seo_categories) as seo_pages,
  (select count(*) from seo_categories where generated) as seo_generated,
  (select count(*) from leads) as leads_total,
  (select count(*) from outreach) as outreach_sent,
  (select coalesce(balance,0) from gl_account_balances where code='6200') as mkt_spend,
  (select count(*) from customers where created_at>=now()-interval '30 days') as new_customers_30d,
  case when mi.meta_spend>0 then round(mi.meta_spend/nullif((select count(*) from customers where created_at>=now()-interval '30 days'),0),2) else null end as cac,
  case when mi.meta_spend>0 then round((fm->>'reveal_fees')::numeric/mi.meta_spend,2)
       when (select coalesce(balance,0) from gl_account_balances where code='6200')>0 then round((fm->>'reveal_fees')::numeric/(select coalesce(balance,0) from gl_account_balances where code='6200'),2)
       else null end as roi,
  (select count(*) from marketing_category_demand where inquiries_90d>0 and suppliers=0) as supply_gaps,
  (select count(*) from marketing_category_demand where not has_seo_page) as seo_gaps,
  mi.meta_spend as meta_spend_30d, mi.meta_impr as meta_impressions_30d, mi.meta_clicks as meta_clicks_30d,
  mi.meta_results as meta_results_30d, mi.meta_active as meta_active_campaigns,
  case when mi.meta_results>0 then round(mi.meta_spend/mi.meta_results,2) else null end as meta_cpl,
  case when mi.meta_spend>0 then round((fm->>'reveal_fees')::numeric/mi.meta_spend,2) else null end as meta_roi
from f, mi;
revoke all on public.marketing_kpis from anon, authenticated;

create or replace function public.fn_ws_marketing()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $fn$
  select jsonb_build_object(
    'health', (select (kpis->>'health')::numeric from marketing_snapshots order by snapshot_date desc limit 1),
    'inquiries_30d', k.inquiries_30d, 'quoted_30d', k.quoted_30d, 'revealed_30d', k.revealed_30d,
    'revenue_30d', k.revenue_30d, 'inq_to_quote_pct', k.inq_to_quote_pct, 'quote_to_reveal_pct', k.quote_to_reveal_pct,
    'blog_published', k.blog_published, 'drafts_pending', k.drafts_pending,
    'social_staged', k.social_staged, 'social_published', k.social_published,
    'seo_pages', k.seo_pages, 'seo_gaps', k.seo_gaps, 'supply_gaps', k.supply_gaps,
    'leads_total', k.leads_total, 'outreach_sent', k.outreach_sent,
    'meta', jsonb_build_object(
      'spend_30d', k.meta_spend_30d, 'clicks_30d', k.meta_clicks_30d, 'results_30d', k.meta_results_30d,
      'impressions_30d', k.meta_impressions_30d, 'active_campaigns', k.meta_active_campaigns,
      'cpl', k.meta_cpl, 'roi', k.meta_roi,
      'sync', (select case when (select value from app_secrets where key='meta_access_token') is not null then 'connected' else 'awaiting_token' end),
      'campaigns', coalesce((select jsonb_agg(jsonb_build_object('name',campaign_name,'status',effective_status,'spend',spend,'clicks',clicks,'results',results))
          from meta_insights where time_window='last_30d' and campaign_name ilike '%quotesdone%'),'[]'::jsonb)
    ),
    'priorities', coalesce((select plan->'priorities' from marketing_snapshots order by snapshot_date desc limit 1),'[]'::jsonb),
    'push_supply', coalesce((select jsonb_agg(jsonb_build_object('category',category,'inquiries_90d',inquiries_90d,'suppliers',suppliers) order by inquiries_90d desc)
        from (select * from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc limit 10) t),'[]'::jsonb),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
        from agent_actions where agent='marketing_ai' and status in ('pending','needs_review')),'[]'::jsonb)
  )
  from marketing_kpis k;
$fn$;
revoke all on function public.fn_ws_marketing() from anon, authenticated, public;

select cron.schedule('meta_sync_daily','35 3 * * *',
  $$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/meta_sync',
     headers:='{"Content-Type":"application/json"}'::jsonb,
     body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')));$$);
