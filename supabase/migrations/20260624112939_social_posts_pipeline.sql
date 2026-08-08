-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260624112939   name: social_posts_pipeline
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists social_posts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  source text default 'manual',
  content jsonb,
  image_url text,
  channels text[] default '{}',
  schedule_at timestamptz,
  mode text default 'draft',
  status text default 'pending',
  postiz_ids jsonb,
  error text
);
insert into app_secrets(key,value,updated_at)
values ('postiz_publish_key','pzp_4d9b2c8a1e7f4063b5a9d0c2e6f1a3b7', now())
on conflict (key) do update set value=excluded.value, updated_at=now();
