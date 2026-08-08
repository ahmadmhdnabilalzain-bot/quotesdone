-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623185003   name: agent_chats
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists agent_chats (
  id bigint generated always as identity primary key,
  agent_key text not null,
  role text not null check (role in ('user','assistant')),
  content text not null,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists agent_chats_agent_idx on agent_chats (agent_key, id);
alter table agent_chats enable row level security;
-- deny-all to anon/auth; edge functions use service role and bypass RLS
;
