-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709085502   name: meta_insights_scaffold
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.meta_insights (
  id bigint generated always as identity primary key,
  campaign_id text not null,
  campaign_name text,
  effective_status text,
  objective text,
  time_window text not null default 'last_30d',
  spend numeric(14,2) default 0,
  impressions bigint default 0,
  clicks bigint default 0,
  reach bigint default 0,
  ctr numeric(8,3),
  cpc numeric(10,3),
  results bigint default 0,
  currency text default 'AED',
  synced_at timestamptz not null default now(),
  synced_via text default 'meta_sync',
  unique(campaign_id, time_window)
);
revoke all on public.meta_insights from anon, authenticated;

insert into public.app_secrets(key,value) values
  ('meta_campaign_filter','QuotesDone'),
  ('meta_sync_enabled','false')
on conflict (key) do nothing;

insert into public.meta_insights(campaign_id,campaign_name,effective_status,objective,time_window,spend,impressions,clicks,reach,results,currency,synced_via)
values
 ('120247871214360016','QuotesDone — UAE SMEs — Get Anonymous Quotes (Traffic)','PAUSED','LINK_CLICKS','last_30d',0,0,0,0,0,'AED','seed'),
 ('120247871214360016','QuotesDone — UAE SMEs — Get Anonymous Quotes (Traffic)','PAUSED','LINK_CLICKS','maximum',0,0,0,0,0,'AED','seed')
on conflict (campaign_id,time_window) do nothing;
