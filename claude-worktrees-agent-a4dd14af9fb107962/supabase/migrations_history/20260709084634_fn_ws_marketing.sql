-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709084634   name: fn_ws_marketing
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

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
    'mkt_spend', k.mkt_spend, 'roi', k.roi,
    'priorities', coalesce((select plan->'priorities' from marketing_snapshots order by snapshot_date desc limit 1),'[]'::jsonb),
    'push_supply', coalesce((select jsonb_agg(jsonb_build_object('category',category,'inquiries_90d',inquiries_90d,'suppliers',suppliers) order by inquiries_90d desc)
        from (select * from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc limit 10) t),'[]'::jsonb),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
        from agent_actions where agent='marketing_ai' and status in ('pending','needs_review')),'[]'::jsonb)
  )
  from marketing_kpis k;
$fn$;
revoke all on function public.fn_ws_marketing() from anon, authenticated, public;
