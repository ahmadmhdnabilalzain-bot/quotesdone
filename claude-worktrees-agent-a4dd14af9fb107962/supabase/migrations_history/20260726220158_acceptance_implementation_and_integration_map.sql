-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726220158   name: acceptance_implementation_and_integration_map
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Artifact 7: Integration Matrix. Which external services the platform can reach,
-- inferred from configured credentials in app_secrets and the functions that use them.
create table if not exists public.integration_matrix (
  service       text primary key,
  purpose       text not null,
  credential_keys text not null,
  used_by_fns   text,
  owner_dept    text,
  configured    boolean not null default true,
  notes         text
);
alter table public.integration_matrix enable row level security;

-- Artifact 8: Implementation Map. Capability -> exact files, tables, cron jobs, routes.
create table if not exists public.implementation_map (
  capability    text primary key,
  area          text not null,
  files         text,
  db_tables     text,
  cron_jobs     text,
  api_routes    text,
  test_suite    text,
  status        text not null default 'partial',   -- implemented | partial | missing
  evidence      text,
  updated_at    timestamptz not null default now()
);
alter table public.implementation_map enable row level security;

comment on table public.integration_matrix is 'Acceptance artifact 7: external APIs/services each department can access';
comment on table public.implementation_map is 'Acceptance artifact 8: exact files, modules and tables implementing each feature';
