-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260610120140   name: stage_v7_import
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

drop table if exists stage_v7;
create table stage_v7 (
  company_name text, email text, website text, domain text, phone text,
  city text, emirate text, sector text, services text, description text,
  rating numeric, reviews int, instagram text, facebook text, linkedin text,
  whatsapp text, founded_year int, company_size text,
  norm_name text generated always as (lower(regexp_replace(coalesce(company_name,''),'[^a-z0-9]','','gi'))) stored
);
create index on stage_v7 (lower(email));
create index on stage_v7 (domain);
create index on stage_v7 (norm_name);
