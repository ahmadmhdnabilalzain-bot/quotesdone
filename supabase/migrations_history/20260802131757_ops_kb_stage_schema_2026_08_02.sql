-- QuotesDone COMPANY OPERATIONS corpus — staging schema (2 Aug 2026).
-- Source: QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31 (3,959 records, 24 departments).
-- Adapted from the supplied 01_STAGING_SCHEMA.sql. Five deliberate changes, each explained below.
--
-- WHY A SECOND STAGING SCHEMA RATHER THAN THE LIVE ORG TABLES. Every one of the 33 objects the
-- mapping guide names already EXISTS in production and is populated - org_departments (15 rows),
-- org_agents (67), dept_library (1,456), employee_knowledge (900), governance_policy (16). This
-- corpus describes 24 target departments and 96 target roles, i.e. a LARGER organisation than the
-- one running. Writing it straight into org_departments would create nine departments with no
-- agents, no authority rows and no health function, and the Command Center would immediately start
-- reporting them as broken. So the corpus lands here intact, the crosswalk between the two is
-- explicit and reviewable, and promotion is a separate decision per department.
create schema if not exists ops_kb_stage;
revoke all on schema ops_kb_stage from public, anon, authenticated;
grant usage on schema ops_kb_stage to service_role;

create table if not exists ops_kb_stage.ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  package_name text not null,
  package_version text not null,
  package_sha256 text,
  status text not null default 'running'
    check (status in ('running','validated','failed','completed','completed_with_errors','rolled_back')),
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
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now()
);

-- The canonical record table. Every field the pack requires preserved is a column, not a jsonb key:
-- implementation_status, validation_status, authority_tier and risk_level are the four that decide
-- whether a record may act, and burying them in jsonb is how they stop being enforced.
create table if not exists ops_kb_stage.records (
  record_id text primary key,
  scope_type text not null check (scope_type in ('company','department','workflow','agent','external_source')),
  scope_key text not null,
  module text not null,
  record_type text not null,
  title text not null,
  content text not null,
  structured_data jsonb not null default '{}'::jsonb,
  source_ids text[] not null default '{}',
  implementation_status text not null check (implementation_status in ('implemented','partial','target_state','external_reference')),
  validation_status text not null check (validation_status in ('source_verified','reviewed','draft','approved','quarantined','superseded')),
  authority_tier text not null check (authority_tier in ('advisory','supervised','gated','autonomous')),
  risk_level text not null check (risk_level in ('low','medium','high','critical')),
  version text not null,
  effective_date date,
  review_after date,
  keywords jsonb not null default '[]'::jsonb,
  dependencies jsonb not null default '[]'::jsonb,
  escalation_rule jsonb not null default '{}'::jsonb,
  content_sha256 text not null,
  package_version text not null,
  ingestion_run_id uuid references ops_kb_stage.ingestion_runs(id),
  source_file text,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ops_kb_stage_records_scope_idx on ops_kb_stage.records(scope_type, scope_key, record_type);
create index if not exists ops_kb_stage_records_review_idx on ops_kb_stage.records(review_after)
  where validation_status not in ('superseded','quarantined');
create index if not exists ops_kb_stage_records_sources_gin on ops_kb_stage.records using gin(source_ids);
create index if not exists ops_kb_stage_records_structured_gin on ops_kb_stage.records using gin(structured_data);
create index if not exists ops_kb_stage_records_impl_idx on ops_kb_stage.records(implementation_status, authority_tier, risk_level);

-- ADDITION 1: version history. The security rules require append-only/versioned knowledge history,
-- which the supplied schema has no table for. Same trigger pattern as the supplier corpus.
create table if not exists ops_kb_stage.record_versions (
  id bigserial primary key,
  record_id text not null,
  version text not null,
  content_sha256 text,
  payload jsonb not null,
  replaced_at timestamptz not null default now(),
  ingestion_run_id uuid references ops_kb_stage.ingestion_runs(id) on delete set null
);
create index if not exists ops_kb_stage_record_versions_idx on ops_kb_stage.record_versions(record_id, replaced_at desc);

create or replace function ops_kb_stage.trg_archive_record_version() returns trigger
language plpgsql as $$
begin
  if TG_OP = 'UPDATE' and OLD.content_sha256 is distinct from NEW.content_sha256 then
    insert into ops_kb_stage.record_versions (record_id, version, content_sha256, payload, ingestion_run_id)
    values (OLD.record_id, OLD.version, OLD.content_sha256, to_jsonb(OLD), OLD.ingestion_run_id);
    NEW.updated_at := now();
  elsif TG_OP = 'UPDATE' then
    NEW.updated_at := OLD.updated_at;
  end if;
  return NEW;
end $$;
drop trigger if exists archive_record_version on ops_kb_stage.records;
create trigger archive_record_version before update on ops_kb_stage.records
  for each row execute function ops_kb_stage.trg_archive_record_version();

-- Relational projections. Everything deterministic lives here, not in an embedding.
create table if not exists ops_kb_stage.departments (
  department_key text primary key,
  name text not null,
  implementation_status text not null,
  charter text,
  north_star text,
  production_keys text[] not null default '{}',
  raw jsonb not null default '{}'::jsonb
);

create table if not exists ops_kb_stage.roles (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  agent_key text not null,
  department_key text not null,
  title text not null,
  responsibilities text,
  authority_tier text not null,
  max_authority text,
  manager text,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_roles_dept_idx on ops_kb_stage.roles(department_key);

create table if not exists ops_kb_stage.sops (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  department_key text not null,
  workflow_key text,
  trigger text,
  steps jsonb not null default '[]'::jsonb,
  required_inputs jsonb,
  required_outputs jsonb,
  definition_of_done jsonb,
  service_level text,
  rollback text,
  authority_tier text not null,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_sops_dept_idx on ops_kb_stage.sops(department_key);

-- enabled=false everywhere by design. The pack is explicit: imported rules and workflows stay
-- disabled until mapped, tested and approved. An imported rule that can fire is an activated rule.
create table if not exists ops_kb_stage.decision_rules (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  rule_id text not null unique,
  department_key text not null,
  priority int,
  condition jsonb,
  action jsonb,
  owner text,
  requires_human_review boolean not null default false,
  authority_tier text not null,
  enabled boolean not null default false,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_rules_dept_idx on ops_kb_stage.decision_rules(department_key, priority desc);

create table if not exists ops_kb_stage.exception_playbooks (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  exception_key text not null,
  department_key text not null,
  trigger text,
  immediate_actions jsonb,
  recovery jsonb,
  closure jsonb,
  enabled boolean not null default false,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_playbooks_dept_idx on ops_kb_stage.exception_playbooks(department_key);

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
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_kpis_dept_idx on ops_kb_stage.kpis(department_key);

create table if not exists ops_kb_stage.scenarios (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  scenario_key text not null,
  scope_key text not null,
  kind text not null default 'department',
  situation text not null,
  expected_behaviour text not null,
  pass_criteria jsonb,
  last_result text,
  last_run timestamptz,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_scenarios_scope_idx on ops_kb_stage.scenarios(scope_key, kind);

create table if not exists ops_kb_stage.workflows (
  workflow_key text primary key,
  record_id text,
  name text not null,
  trigger text,
  departments text[] not null default '{}',
  steps jsonb not null default '[]'::jsonb,
  hard_gates text[] not null default '{}',
  audit_requirements jsonb,
  definition_of_done jsonb,
  implementation_status text not null,
  enabled boolean not null default false,
  raw jsonb not null default '{}'::jsonb
);

create table if not exists ops_kb_stage.handoffs (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  workflow_key text not null,
  from_department text not null,
  to_department text not null,
  sender_action text,
  receiver_action text,
  handoff_payload jsonb not null default '{}'::jsonb,
  acceptance text,
  rejection text,
  enabled boolean not null default false,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_handoffs_wf_idx on ops_kb_stage.handoffs(workflow_key);

-- ADDITION 2: the supplied schema has no home for the 100 event subscriptions, 120 templates or the
-- 28 governance policy records (model routing, memory, audit, data classification, incidents).
-- Without these tables a third of the corpus would have landed as narrative text only.
create table if not exists ops_kb_stage.event_subscriptions (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  event_type text not null,
  department_key text not null,
  reason text,
  active boolean not null default false,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_events_idx on ops_kb_stage.event_subscriptions(event_type, department_key);

create table if not exists ops_kb_stage.templates (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  department_key text not null,
  template_key text,
  purpose text,
  body text,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_templates_dept_idx on ops_kb_stage.templates(department_key);

create table if not exists ops_kb_stage.policies (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  policy_domain text not null,
  policy_key text,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_policies_idx on ops_kb_stage.policies(policy_domain);

-- ADDITION 3: hard gates get their own table. They are the list of things that must NEVER happen
-- autonomously - money movement, legal commitments, identity changes, production deployment. They
-- are worth being queryable on their own rather than filtered out of a jsonb blob at runtime.
create table if not exists ops_kb_stage.hard_gates (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  gate_key text not null,
  title text not null,
  rule text,
  raw jsonb not null default '{}'::jsonb
);

create table if not exists ops_kb_stage.live_bindings (
  record_id text primary key references ops_kb_stage.records(record_id) on delete cascade,
  department_key text not null,
  object_name text not null,
  object_kind text,
  found_in_export boolean,
  exists_in_db boolean,
  db_object_kind text,
  read_purpose text,
  write_policy text,
  cache_policy text,
  mapping_status text not null default 'unresolved'
    check (mapping_status in ('unresolved','mapped','validated','rejected','missing')),
  raw jsonb not null default '{}'::jsonb
);
create index if not exists ops_kb_stage_bindings_idx on ops_kb_stage.live_bindings(mapping_status, department_key);

-- ADDITION 4: the production/target department crosswalk as a table, not a CSV in a zip. This is the
-- single most contested object in the whole import - 15 production departments against 24 target
-- ones - and it needs to be queryable, reviewable and versioned.
create table if not exists ops_kb_stage.department_crosswalk (
  production_dept_key text not null,
  target_department_key text not null,
  mapping_type text not null,
  note text,
  production_exists boolean,
  target_exists boolean,
  review_status text not null default 'draft',
  primary key (production_dept_key, target_department_key)
);

create table if not exists ops_kb_stage.mapping_decisions (
  id bigint generated always as identity primary key,
  concept_type text not null,
  concept_key text not null,
  existing_object text,
  decision text not null check (decision in ('reuse','extend','create_staging','unresolved','reject')),
  rationale text not null,
  decided_by text,
  decided_at timestamptz default now(),
  evidence jsonb,
  unique(concept_type, concept_key)
);

-- ADDITION 5: RLS on, not just grants revoked. The supplied schema revokes table privileges, which
-- is correct but relies on nobody ever adding a grant. RLS with zero policies fails closed even if
-- a privilege is granted by mistake later.
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'ops_kb_stage' loop
    execute format('alter table ops_kb_stage.%I enable row level security', t.tablename);
    execute format('revoke all on ops_kb_stage.%I from anon, authenticated', t.tablename);
    execute format('grant all on ops_kb_stage.%I to service_role', t.tablename);
  end loop;
end $$;
alter default privileges in schema ops_kb_stage revoke all on tables from anon, authenticated;
