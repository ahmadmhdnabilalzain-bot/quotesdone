-- QuotesDone knowledge-corpus staging schema (2 Aug 2026).
-- Source: QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31 + the supplied ingestion control pack.
--
-- WHY A SEPARATE SCHEMA. The control pack is explicit: ingest into staging, do not replace the live
-- category router until the crosswalk has been reviewed. public.agent_knowledge (1,844 rows) and
-- public.kb_chunks (4,886 rows) are what the company answers from TODAY; dropping 115,000 unreviewed
-- records into them would silently change every answer the platform gives, with no way back. So the
-- corpus lands here, intact and versioned, and promotion into the live tables is a separate,
-- reviewable step per category. Rollback is 'delete where ingestion_run_id = ...', not a restore.
--
-- WHAT IS DELIBERATELY NOT STORED. The supplied staging schema carries a `raw jsonb` copy of every
-- row. Every field of that row is already columnised below, so `raw` would double 174 MB of JSONL
-- for no read path. Dropped on records (kept on the small taxonomy tables, where it is cheap and
-- occasionally useful). 02_category_master.md (119 MB of narrative across the 67 packages) is NOT
-- imported at all - the pack forbids putting a master into a runtime prompt, so the DB has no reason
-- to hold it. Its checksum is recorded in the package manifest instead.
create schema if not exists kb_stage;
revoke all on schema kb_stage from anon, authenticated;
grant usage on schema kb_stage to service_role;

-- Every write is attached to a run. This is the rollback handle and the audit trail.
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
  report jsonb not null default '{}'::jsonb
);
create unique index if not exists kb_stage_runs_pkg_idx
  on kb_stage.ingestion_runs (package_id, package_version, coalesce(package_sha256,''));
create index if not exists kb_stage_runs_status_idx on kb_stage.ingestion_runs (status, started_at desc);

-- SHA-256 per file, so a rerun skips unchanged files instead of re-streaming 174 MB.
create table if not exists kb_stage.file_hashes (
  package_id text not null,
  file_name text not null,
  sha256 text not null,
  rows_seen integer not null default 0,
  last_run_id uuid references kb_stage.ingestion_runs(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (package_id, file_name)
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
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists kb_stage.categories (
  category_slug text primary key,
  category_number integer,
  category_name_en text not null,
  category_name_ar text,
  package_id text not null,
  package_version text not null,
  package_zip text,
  aliases jsonb not null default '[]'::jsonb,
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists kb_stage.subcategories (
  category_slug text not null references kb_stage.categories(category_slug) on delete cascade,
  subcategory_slug text not null,
  subcategory_number integer,
  name_en text not null,
  name_ar text,
  aliases_en jsonb not null default '[]'::jsonb,
  aliases_ar jsonb not null default '[]'::jsonb,
  raw jsonb not null default '{}'::jsonb,
  primary key (category_slug, subcategory_slug)
);

-- The narrative/searchable body of the corpus. One row per supplied record_id.
-- NOTE ON validation_status: it is imported verbatim and never promoted. The pack is emphatic that
-- draft / source_verified / reviewed must not be mass-promoted to approved, and runtime retrieval
-- filters on it, so this column is the safety boundary between "we have text about it" and "we are
-- willing to say it to a customer".
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
  package_id text,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null,
  content_sha256 text,
  updated_at timestamptz not null default now()
);
create index if not exists kb_stage_records_scope_idx on kb_stage.records (category_slug, subcategory_slug, module, record_type);
create index if not exists kb_stage_records_validation_idx on kb_stage.records (validation_status, review_after);
create index if not exists kb_stage_records_run_idx on kb_stage.records (ingestion_run_id);
create index if not exists kb_stage_records_pkg_idx on kb_stage.records (package_id);

-- Superseded versions are kept rather than overwritten, so a bad package version can be rolled back
-- to the previous text rather than to nothing.
create table if not exists kb_stage.record_versions (
  id bigserial primary key,
  record_id text not null,
  version text not null,
  content_sha256 text,
  payload jsonb not null,
  replaced_at timestamptz not null default now(),
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null
);
create index if not exists kb_stage_record_versions_idx on kb_stage.record_versions (record_id, replaced_at desc);

-- Deterministic layer. These are the tables that are meant to REPLACE model calls: which question
-- to ask next, whether the brief is complete, whether a supplier is eligible. They are relational
-- on purpose - no embeddings, no chat model, no ambiguity.
create table if not exists kb_stage.questions (
  question_id text primary key,
  record_id text references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  field_key text,
  question_en text,
  question_ar text,
  answer_type text,
  allowed_values jsonb not null default '[]'::jsonb,
  unit text,
  mandatory boolean not null default false,
  activation jsonb,
  impact jsonb not null default '[]'::jsonb,
  on_missing text,
  answerable_by_documents jsonb not null default '[]'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null
);
create index if not exists kb_stage_questions_scope_idx on kb_stage.questions (category_slug, subcategory_slug, mandatory);
create index if not exists kb_stage_questions_field_idx on kb_stage.questions (field_key);

create table if not exists kb_stage.decision_rules (
  rule_id text primary key,
  category_slug text not null,
  subcategory_slug text not null,
  rule_type text,
  priority integer,
  when_json jsonb,
  then_json jsonb,
  source_ids jsonb not null default '[]'::jsonb,
  confidence numeric,
  requires_human_review boolean not null default false,
  version text,
  payload jsonb not null default '{}'::jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null
);
create index if not exists kb_stage_rules_scope_idx on kb_stage.decision_rules (category_slug, subcategory_slug, priority desc);
create index if not exists kb_stage_rules_type_idx on kb_stage.decision_rules (rule_type);

create table if not exists kb_stage.validation_rules (
  validation_id text primary key,
  record_id text references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  rule_text text,
  severity text,
  on_fail jsonb not null default '[]'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null
);
create index if not exists kb_stage_validations_scope_idx on kb_stage.validation_rules (category_slug, subcategory_slug);

create table if not exists kb_stage.scenario_tests (
  scenario_id text primary key,
  record_id text references kb_stage.records(record_id) on delete cascade,
  category_slug text not null,
  subcategory_slug text not null,
  setup text,
  expected text,
  pass_criteria jsonb not null default '[]'::jsonb,
  status text not null default 'not_executed',
  latest_result jsonb,
  payload jsonb not null default '{}'::jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null
);
create index if not exists kb_stage_scenarios_scope_idx on kb_stage.scenario_tests (category_slug, subcategory_slug, status);

create table if not exists kb_stage.knowledge_gaps (
  id bigserial primary key,
  package_id text not null,
  category_slug text,
  subcategory_slug text,
  gap text not null,
  severity text,
  raw jsonb not null default '{}'::jsonb,
  ingestion_run_id uuid references kb_stage.ingestion_runs(id) on delete set null
);

-- THE CROSSWALK. The pack is explicit that the 66 knowledge domains, the founder's 84-item supplier
-- list and the live 86-category catalogue are NOT interchangeable, and that routing must use stable
-- slugs/IDs rather than the display number. This table is the only sanctioned bridge between them,
-- and it stays review_status='draft' until a human signs it off.
create table if not exists kb_stage.category_crosswalk (
  knowledge_domain_slug text not null,
  knowledge_subcategory_slug text not null,
  production_category_id text not null,
  production_category_slug text not null,
  relationship_type text not null check (relationship_type in ('primary','secondary','overlap','fallback')),
  routing_priority integer not null default 100,
  review_status text not null default 'draft',
  effective_from date not null default current_date,
  primary key (knowledge_subcategory_slug, production_category_id, knowledge_domain_slug)
);
create index if not exists kb_stage_crosswalk_prod_idx on kb_stage.category_crosswalk (production_category_id, routing_priority);

do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'kb_stage' loop
    execute format('alter table kb_stage.%I enable row level security', t.tablename);
    execute format('revoke all on kb_stage.%I from anon, authenticated', t.tablename);
    execute format('grant all on kb_stage.%I to service_role', t.tablename);
  end loop;
end $$;
