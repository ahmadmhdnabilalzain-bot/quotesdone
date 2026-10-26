-- QuotesDone Company Operations Corpus — staging schema template
-- Review and adapt to the current repository before applying.
-- This schema is intentionally not exposed through the public API.

create schema if not exists ops_kb_stage;

create table if not exists ops_kb_stage.ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  package_name text not null,
  package_version text not null,
  package_sha256 text,
  status text not null default 'running'
    check (status in ('running','validated','failed','completed','rolled_back')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  inserted_count bigint not null default 0,
  updated_count bigint not null default 0,
  skipped_count bigint not null default 0,
  rejected_count bigint not null default 0,
  detail jsonb not null default '{}'::jsonb
);

create table if not exists ops_kb_stage.ingestion_files (
  run_id uuid not null references ops_kb_stage.ingestion_runs(id) on delete cascade,
  relative_path text not null,
  sha256 text not null,
  size_bytes bigint,
  status text not null default 'pending'
    check (status in ('pending','validated','imported','skipped','rejected')),
  inserted_count bigint not null default 0,
  updated_count bigint not null default 0,
  skipped_count bigint not null default 0,
  rejected_count bigint not null default 0,
  last_record_id text,
  error_detail jsonb,
  primary key (run_id, relative_path)
);

create table if not exists ops_kb_stage.sources (
  source_id text primary key,
  title text not null,
  source_type text not null,
  publisher text,
  url_or_path text,
  status text,
  scope text,
  verified_on date,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);

create table if not exists ops_kb_stage.records (
  record_id text primary key,
  scope_type text not null,
  scope_key text not null,
  module text not null,
  record_type text not null,
  title text not null,
  content text not null,
  structured_data jsonb not null default '{}'::jsonb,
  source_ids text[] not null default '{}',
  implementation_status text not null,
  validation_status text not null,
  authority_tier text not null,
  risk_level text not null,
  version text not null,
  effective_date date,
  review_after date,
  keywords jsonb not null default '[]'::jsonb,
  dependencies jsonb not null default '[]'::jsonb,
  escalation_rule jsonb not null default '{}'::jsonb,
  content_sha256 text not null,
  package_version text not null,
  ingestion_run_id uuid references ops_kb_stage.ingestion_runs(id),
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ops_kb_stage_records_scope_idx
  on ops_kb_stage.records(scope_type, scope_key, record_type);
create index if not exists ops_kb_stage_records_review_idx
  on ops_kb_stage.records(review_after)
  where validation_status not in ('superseded','quarantined');
create index if not exists ops_kb_stage_records_sources_gin
  on ops_kb_stage.records using gin(source_ids);
create index if not exists ops_kb_stage_records_structured_gin
  on ops_kb_stage.records using gin(structured_data);

-- Relational projections for deterministic runtime use.
create table if not exists ops_kb_stage.departments (
  department_key text primary key,
  name text not null,
  implementation_status text not null,
  charter text,
  north_star text,
  production_keys text[] not null default '{}',
  raw jsonb not null
);

create table if not exists ops_kb_stage.roles (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  agent_key text not null,
  department_key text not null,
  title text not null,
  responsibilities text,
  authority_tier text not null,
  raw jsonb not null
);

create table if not exists ops_kb_stage.sops (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  department_key text not null,
  workflow_key text,
  steps jsonb not null,
  required_inputs jsonb,
  required_outputs jsonb,
  definition_of_done jsonb,
  authority_tier text not null,
  raw jsonb not null
);

create table if not exists ops_kb_stage.decision_rules (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  rule_id text not null unique,
  department_key text not null,
  priority int,
  condition jsonb,
  action jsonb,
  requires_human_review boolean not null default false,
  authority_tier text not null,
  enabled boolean not null default false,
  raw jsonb not null
);

create table if not exists ops_kb_stage.exception_playbooks (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  exception_key text not null unique,
  department_key text not null,
  trigger text,
  immediate_actions jsonb,
  recovery jsonb,
  closure jsonb,
  enabled boolean not null default false,
  raw jsonb not null
);

create table if not exists ops_kb_stage.kpis (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  department_key text not null,
  metric_name text not null,
  formula_description text,
  direction text,
  source_candidates jsonb,
  owner text,
  query_sql text,
  enabled boolean not null default false,
  raw jsonb not null
);

create table if not exists ops_kb_stage.scenarios (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  scenario_key text not null unique,
  scope_key text not null,
  situation text not null,
  expected_behaviour text not null,
  pass_criteria jsonb,
  last_result text,
  last_run timestamptz,
  raw jsonb not null
);

create table if not exists ops_kb_stage.workflows (
  workflow_key text primary key,
  name text not null,
  trigger text,
  departments text[] not null,
  steps jsonb not null,
  hard_gates text[] not null default '{}',
  implementation_status text not null,
  enabled boolean not null default false,
  raw jsonb not null
);

create table if not exists ops_kb_stage.handoffs (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  workflow_key text not null references ops_kb_stage.workflows(workflow_key) on delete cascade,
  from_department text not null,
  to_department text not null,
  handoff_payload jsonb not null,
  acceptance text,
  rejection text,
  enabled boolean not null default false,
  raw jsonb not null
);

create table if not exists ops_kb_stage.live_bindings (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  department_key text not null,
  object_name text not null,
  object_kind text,
  found_in_export boolean,
  resolved_object regclass,
  access_path text,
  mapping_status text not null default 'unresolved'
    check (mapping_status in ('unresolved','mapped','validated','rejected')),
  raw jsonb not null
);

create table if not exists ops_kb_stage.mapping_decisions (
  id bigint generated always as identity primary key,
  concept_type text not null,
  concept_key text not null,
  existing_object text,
  decision text not null
    check (decision in ('reuse','extend','create_staging','unresolved','reject')),
  rationale text not null,
  decided_by text,
  decided_at timestamptz,
  evidence jsonb,
  unique(concept_type, concept_key)
);

-- No public grants.
revoke all on schema ops_kb_stage from public;
revoke all on all tables in schema ops_kb_stage from anon, authenticated;
alter default privileges in schema ops_kb_stage revoke all on tables from anon, authenticated;

-- Imported rules/workflows remain disabled until mapped, tested and approved.
