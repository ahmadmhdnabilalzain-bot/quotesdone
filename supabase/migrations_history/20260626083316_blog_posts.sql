-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626083316   name: blog_posts
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists blog_posts (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  excerpt text,
  meta_desc text,
  body_html text not null,
  author text default 'QuotesDone',
  category text,
  published boolean default true,
  published_at timestamptz default now(),
  updated_at timestamptz default now(),
  sort int default 0
);
alter table blog_posts enable row level security;
