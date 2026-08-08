-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623191036   name: marketing_and_category_agents
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists content_drafts (
  id bigint generated always as identity primary key,
  channel text not null default 'social',
  category text,
  title text,
  body text not null,
  status text not null default 'draft',
  source text default 'marketing_agent',
  created_at timestamptz not null default now()
);
create index if not exists content_drafts_status_idx on content_drafts (status, id desc);
alter table content_drafts enable row level security;

create table if not exists category_agents (
  slug text primary key,
  name text not null,
  emoji text not null default '🛠️',
  active boolean not null default true,
  persona text,
  created_at timestamptz not null default now()
);
alter table category_agents enable row level security;

insert into category_agents (slug, name, emoji)
select slug, name,
  case slug
    when 'electrical' then '⚡' when 'plumbing' then '🔧' when 'ac-maintenance' then '❄️'
    when 'cleaning' then '🧽' when 'interior-design' then '🛋️' when 'joinery-kitchens' then '🪚'
    when 'waterproofing' then '💧' when 'tiling-marble' then '🧱' when 'pest-control' then '🐜'
    when 'swimming-pools' then '🏊' when 'movers' then '📦' when 'handyman' then '🧰'
    when 'facilities-management' then '🏢' when 'ac-duct-cleaning' then '🌬️' when 'smart-home' then '🏠'
    when 'solar' then '☀️' when 'curtains-blinds' then '🪟' when 'cctv-security' then '📹'
    when 'painting' then '🎨' when 'flooring' then '🪵' when 'false-ceiling' then '🔲'
    when 'landscaping' then '🌳' when 'aluminium-glass' then '🪟' when 'signage' then '🪧'
    else '🛠️' end
from seo_categories
on conflict (slug) do nothing;

