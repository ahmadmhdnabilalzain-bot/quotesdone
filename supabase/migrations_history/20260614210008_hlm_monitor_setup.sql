-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260614210008   name: hlm_monitor_setup
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.hlm_watchlist(
  addr text primary key,
  name text,
  score real
);
create table if not exists public.hlm_state(
  key text primary key,
  val jsonb
);
create table if not exists public.hlm_digest_log(
  id bigserial primary key,
  ts timestamptz default now(),
  coin text,
  dir int,
  lean real,
  long_n int,
  short_n int
);

alter table public.hlm_watchlist enable row level security;
alter table public.hlm_state enable row level security;
alter table public.hlm_digest_log enable row level security;

