-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623224332   name: hardening_phase1_schema
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- PDPL: global email suppression / opt-out list
create table if not exists email_suppression(
  email text primary key,
  reason text,
  source text,
  created_at timestamptz default now()
);

-- Observability: app-level error events
create table if not exists error_events(
  id bigserial primary key,
  source text not null,
  kind text,
  severity text default 'error',
  detail jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_error_events_created on error_events(created_at desc);

-- Marketplace supply-health snapshots
create table if not exists supply_health_snapshots(
  id bigserial primary key,
  period_end date,
  metrics jsonb,
  created_at timestamptz default now()
);

-- Supplier verification state machine (licence verification itself stays deferred per owner)
alter table leads add column if not exists verification_status text default 'unverified';
update leads set verification_status = case
  when verified = true then 'verified'
  when approval_status = 'approved' and claimed = true then 'pending'
  else 'unverified' end
where verification_status is null or verification_status = 'unverified';
