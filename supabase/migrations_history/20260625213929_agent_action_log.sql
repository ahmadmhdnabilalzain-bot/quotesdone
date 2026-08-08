-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625213929   name: agent_action_log
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists agent_action_log (
  id uuid primary key default gen_random_uuid(),
  agent_key text,
  action text,
  args jsonb,
  result jsonb,
  ok boolean,
  actor text,
  created_at timestamptz default now()
);
create index if not exists agent_action_log_created_idx on agent_action_log(created_at desc);
