-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709084512   name: marketing_kpis_social_sent_fix
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.marketing_kpis as
with f as (select funnel_metrics(30) fm)
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
  case when (select coalesce(balance,0) from gl_account_balances where code='6200')>0
    then round((select coalesce(balance,0) from gl_account_balances where code='6200')/nullif((select count(*) from customers where created_at>=now()-interval '30 days'),0),2) else null end as cac,
  case when (select coalesce(balance,0) from gl_account_balances where code='6200')>0
    then round((fm->>'reveal_fees')::numeric/(select coalesce(balance,0) from gl_account_balances where code='6200'),2) else null end as roi,
  (select count(*) from marketing_category_demand where inquiries_90d>0 and suppliers=0) as supply_gaps,
  (select count(*) from marketing_category_demand where not has_seo_page) as seo_gaps
from f;
revoke all on public.marketing_kpis from anon, authenticated;
