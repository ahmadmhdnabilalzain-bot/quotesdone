-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726211534   name: add_company_goals
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Company-level strategic goals. Distinct from org_objectives, which is a work-item
-- table that cos_execute opens and closes per planning cycle. These persist.
create table if not exists public.company_goals (
  key            text primary key,
  goal           text not null,
  metric         text not null,
  target_value   numeric,
  unit           text,
  period         text not null default 'annual',
  owner_dept     text references public.org_departments(dept_key),
  measure_sql    text,
  active         boolean not null default true,
  sort           int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.company_goals enable row level security;

comment on table  public.company_goals is 'Company-level strategic targets every department plans against. Read by dept_plan/cos_execute; never auto-closed.';
comment on column public.company_goals.measure_sql is 'Optional read-only SQL returning a single numeric current value for this metric.';
