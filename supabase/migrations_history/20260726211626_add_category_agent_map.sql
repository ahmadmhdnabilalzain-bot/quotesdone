-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726211626   name: add_category_agent_map
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Reconciles the two disjoint taxonomies:
--   catalog_supplier_categories (84, the spec's canonical B2B supplier catalogue)
--   category_agents             (45, of which 14 are internal staff agents, not categories)
-- status: mapped | needs_agent | service_only | internal_agent
create table if not exists public.category_agent_map (
  catalog_slug text references public.catalog_supplier_categories(slug) on delete cascade,
  agent_slug   text references public.category_agents(slug) on delete set null,
  status       text not null default 'needs_agent',
  confidence   text not null default 'high',
  note         text,
  created_at   timestamptz not null default now(),
  primary key (catalog_slug, agent_slug)
);
alter table public.category_agent_map enable row level security;
comment on table public.category_agent_map is 'Bridge between the 84-category supplier catalogue and the category_agents roster. Built 2026-07-26 during spec-coverage reconciliation.';
