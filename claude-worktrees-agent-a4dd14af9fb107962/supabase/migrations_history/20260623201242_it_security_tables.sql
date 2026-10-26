-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623201242   name: it_security_tables
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists health_checks (
  id bigint generated always as identity primary key,
  check_kind text not null,
  target text,
  ok boolean,
  status_code int,
  latency_ms int,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists health_checks_idx on health_checks(created_at desc);
alter table health_checks enable row level security;

create table if not exists security_events (
  id bigint generated always as identity primary key,
  kind text not null,
  severity text not null default 'low',
  source text,
  subject text,
  detail jsonb,
  created_at timestamptz not null default now()
);
create index if not exists security_events_idx on security_events(created_at desc);
alter table security_events enable row level security;

