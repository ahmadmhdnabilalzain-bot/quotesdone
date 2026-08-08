-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260713062435   name: create_os_audit_log
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.os_audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor text,
  action text not null,
  entity text,
  entity_id text,
  detail jsonb,
  ok boolean,
  err text
);
create index if not exists idx_os_audit_at on public.os_audit_log (at desc);
create index if not exists idx_os_audit_actor on public.os_audit_log (actor);
create index if not exists idx_os_audit_action on public.os_audit_log (action);
alter table public.os_audit_log enable row level security;
