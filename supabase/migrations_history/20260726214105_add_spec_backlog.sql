-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726214105   name: add_spec_backlog
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Durable programme backlog derived from the founder's three specification documents
-- (architecture, supplier categories, agents & knowledge). Survives sessions; readable
-- by the Chief of Staff so the org can plan against its own build-out.
create table if not exists public.spec_backlog (
  id            bigserial primary key,
  source_doc    text not null,          -- architecture | categories | agents_knowledge
  area          text not null,
  item          text not null,
  spec_ref      text,
  status        text not null default 'pending',   -- pending | in_progress | done | superseded
  verdict_at_audit text,                -- PRESENT | PARTIAL | ABSENT as measured 2026-07-26
  evidence      text,
  priority      int not null default 3,
  notes         text,
  updated_at    timestamptz not null default now()
);
alter table public.spec_backlog enable row level security;
create index if not exists spec_backlog_status_idx on public.spec_backlog(status, priority);
comment on table public.spec_backlog is 'Programme of work from the founder specs. Built 2026-07-26 from the spec-coverage audit.';
