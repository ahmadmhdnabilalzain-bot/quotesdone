-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726211709   name: fix_category_agent_map_pk
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- One catalogue category maps to at most one agent; agent_slug must be nullable
-- so unmapped categories can be recorded as needs_agent.
alter table public.category_agent_map drop constraint if exists category_agent_map_pkey;
alter table public.category_agent_map alter column agent_slug drop not null;
alter table public.category_agent_map add primary key (catalog_slug);
