-- QuotesDone knowledge corpus staging schema.
-- Claude must adapt names/types after inspecting the existing production schema.
create schema if not exists kb_stage;

create table if not exists kb_stage.ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  package_id text not null,
  package_version text not null,
  package_sha256 text,
  status text not null default 'started',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  inserted_count bigint not null default 0,
  updated_count bigint not null default 0,
  rejected_count bigint not null default 0,
  report jsonb not null default '{}'::jsonb,
  unique(package_id, package_version, package_sha256)
);

create table if not exists kb_stage.sources (
  source_id text primary key,
  title text not null,
  publisher text,
  url text,
  source_type text,
  jurisdiction text,
  published_date text,
  accessed_date text,
  notes text,
  raw jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists kb_stage.categories (
  category_slug text primary key,
  category_name_en text not null,
  category_name_ar text,
  package_id text not null,
  package_version text not null,
  raw jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists kb_stage.subcategories (
  category_slug text not null references kb_stage.categories(category_slug),
  subcategory_slug text not null,
  name_en text not null,
  name_ar text,
  raw jsonb not null,
  primary key(category_slug, subcategory_slug)
);

create table if not exists kb_stage.records (
  record_id text primary key,
  category_slug text not null,
  subcategory_slug text not null,
  module text not null,
  record_type text not null,
  title text not null,
  content text not null,
  structured_data jsonb not null default '{}'::jsonb,
  jurisdiction text,
  authority text,
  source_ids jsonb not null default '[]'::jsonb,
  effective_date text,
  superseded_date text,
  version text not null,
  confidence numeric,
  validation_status text not null,
  review_after text,
  keywords_en jsonb not null default '[]'::jsonb,
  keywords_ar jsonb not null default '[]'::jsonb,
  applies_when jsonb,
  exceptions jsonb not null default '[]'::jsonb,
  escalation_rule jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id),
  content_sha256 text not null,
  updated_at timestamptz not null default now()
);
create index if not exists kb_stage_records_scope_idx on kb_stage.records(category_slug, subcategory_slug, module, record_type);
create index if not exists kb_stage_records_validation_idx on kb_stage.records(validation_status, review_after);

create table if not exists kb_stage.questions (
  question_id text primary key,
  record_id text not null references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  payload jsonb not null,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id)
);

create table if not exists kb_stage.decision_rules (
  rule_id text primary key,
  record_id text not null references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  priority integer,
  when_json jsonb,
  then_json jsonb,
  requires_human_review boolean not null default false,
  payload jsonb not null,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id)
);

create table if not exists kb_stage.validation_rules (
  validation_id text primary key,
  record_id text not null references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  payload jsonb not null,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id)
);

create table if not exists kb_stage.scenario_tests (
  scenario_id text primary key,
  record_id text not null references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  payload jsonb not null,
  latest_result jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id)
);

create table if not exists kb_stage.category_crosswalk (
  knowledge_domain_slug text not null,
  knowledge_subcategory_slug text not null,
  production_category_id text not null,
  production_category_slug text not null,
  relationship_type text not null check (relationship_type in ('primary','secondary','overlap','fallback')),
  routing_priority integer not null default 100,
  review_status text not null default 'draft',
  effective_from date not null default current_date,
  primary key(knowledge_subcategory_slug, production_category_id)
);
