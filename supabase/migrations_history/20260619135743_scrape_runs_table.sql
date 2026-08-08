-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619135743   name: scrape_runs_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.scrape_runs (
  id bigint generated always as identity primary key,
  run_id text, dataset_id text, actor text,
  sector text, emirate text, label text,
  status text default 'RUNNING',
  requested int, fetched int default 0, inserted int default 0,
  created_at timestamptz default now(),
  collected_at timestamptz
);
create index if not exists scrape_runs_status_idx on public.scrape_runs(status);
alter table public.scrape_runs enable row level security;
-- de-dupe guard for incoming places
create unique index if not exists leads_place_id_uidx on public.leads(place_id) where place_id is not null;
