-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623214903   name: agent_knowledge_and_memory
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists agent_knowledge(
  id bigserial primary key,
  agent_key text not null,
  topic text,
  content text not null,
  priority int default 5,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_agent_knowledge_key on agent_knowledge(agent_key);

create table if not exists agent_memory(
  id bigserial primary key,
  agent_key text not null,
  kind text default 'learning',
  content text not null,
  source text,
  importance int default 5,
  created_at timestamptz default now()
);
create index if not exists idx_agent_memory_key on agent_memory(agent_key, created_at desc);
