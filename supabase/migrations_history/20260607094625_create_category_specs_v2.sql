-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607094625   name: create_category_specs_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.category_specs (
  category   text primary key,
  label      text,
  fields     jsonb not null,
  updated_at timestamptz default now()
);
alter table public.category_specs enable row level security;
grant select on public.category_specs to anon;
drop policy if exists "specs readable" on public.category_specs;
create policy "specs readable" on public.category_specs for select to anon using (true);

