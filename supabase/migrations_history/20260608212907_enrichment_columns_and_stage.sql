-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608212907   name: enrichment_columns_and_stage
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.leads add column if not exists linkedin text;
alter table public.leads add column if not exists employee_count integer;
alter table public.leads add column if not exists business_hours text;
alter table public.leads add column if not exists catalogue_pdfs text;

create table if not exists public.leads_enrich_stage (
  id bigint primary key,
  description text,
  capability_summary text,
  services text,
  products text,
  certifications text,
  founded_year integer,
  company_type text,
  company_size text,
  employee_count integer,
  linkedin text,
  business_hours text,
  catalogue_pdfs text
);
truncate public.leads_enrich_stage;
alter table public.leads_enrich_stage enable row level security;
