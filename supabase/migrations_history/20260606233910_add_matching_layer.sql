-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260606233910   name: add_matching_layer
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create extension if not exists vector;

alter table public.leads
  add column if not exists business_role     text,
  add column if not exists products          text,
  add column if not exists services          text,
  add column if not exists certifications    text,
  add column if not exists scale             text,
  add column if not exists capability_summary text,
  add column if not exists embedding         vector(256);

create index if not exists leads_role_idx on public.leads (business_role);

-- temporary load access (revoked after)
grant select, insert, update on public.leads to anon;
alter table public.leads disable row level security;

