-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706004818   name: category_reqs_compliance
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #1 extension: per-category supplier requirements + compliance checklists
alter table category_specs add column if not exists supplier_requirements jsonb;
alter table category_specs add column if not exists compliance_checklist jsonb;
alter table category_specs add column if not exists reqs_updated_at timestamptz;
