-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260624122543   name: qa_results_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists qa_results (
  id bigint generated always as identity primary key,
  run_at timestamptz default now(),
  passed boolean,
  total int,
  failed int,
  results jsonb
);
alter table qa_results enable row level security;
revoke all on qa_results from anon, authenticated;
