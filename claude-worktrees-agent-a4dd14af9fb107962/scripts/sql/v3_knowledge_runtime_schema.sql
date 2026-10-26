-- V3 agent-knowledge runtime: the data model.
--
-- The company already has the right corpus table: ops_knowledge carries scope, module,
-- record type, structured data, authority tier, risk, validation status, effective and
-- review dates. What it never carried is WHICH DELIVERY a record came from, whether the
-- record is a deterministic rule or narrative, and whether a runtime agent may retrieve
-- it at all. Those are added here rather than in a second parallel corpus that no runtime
-- function reads.
--
-- Three stores with different access boundaries:
--   ops_knowledge         runtime-retrievable knowledge (V1/V2/V3 training knowledge)
--   agent_training_case   training material, reachable only through the remediation loop
--   cert.*                certification questions, answer keys and results — evaluator only
--
-- This session writes the first two. It creates the third empty and holds no key to it.

-- ---------------------------------------------------------------- ingestion runs
create table if not exists knowledge_ingestion_run (
  run_id            uuid primary key default gen_random_uuid(),
  package           text not null,
  package_version   text not null,
  generation        text not null check (generation in ('V1','V2','V3')),
  started_at        timestamptz not null default now(),
  finished_at       timestamptz,
  status            text not null default 'running' check (status in ('running','ok','failed','rolled_back')),
  counts            jsonb not null default '{}'::jsonb,
  note              text
);
create index if not exists knowledge_ingestion_run_pkg on knowledge_ingestion_run (package_version, generation);

-- ------------------------------------------------------- packaged -> runtime vocabulary
-- The packaged department names and the runtime dept_keys are two vocabularies for the
-- same 24 departments. Neither side is renamed; the bridge is a row, so a future package
-- with different names costs an insert and not a migration.
create table if not exists org_department_alias (
  packaged_department text not null,
  dept_key            text not null references org_departments(dept_key) on delete cascade,
  is_second_home      boolean not null default false,
  note                text,
  primary key (packaged_department, dept_key)
);

-- ------------------------------------------------------------------ role identity
-- Every active runtime agent must resolve to at least one approved packaged role, and
-- every packaged role must resolve to a runtime agent or be deliberately deferred.
create table if not exists org_role_identity (
  agent_key           text not null references org_agents(agent_key) on delete cascade,
  packaged_role_id    text not null,
  packaged_department text not null,
  archetype           text not null check (archetype in
                        ('director','operations-specialist','analyst-controller','reviewer-auditor')),
  mapping_type        text not null check (mapping_type in
                        ('one_to_one','runtime_composite','package_composite','duplicate_role',
                         'missing_runtime_agent','obsolete_runtime_agent','on_demand_specialist',
                         'requires_split','requires_merge')),
  -- Stage 13 readiness. A builder session may not go past independent_certification_pending.
  readiness           text not null default 'knowledge_imported' check (readiness in
                        ('knowledge_imported','runtime_mapped','tools_connected','live_data_connected',
                         'decision_trace_connected','training_passed','independent_certification_pending',
                         'certified_for_defined_role_scope','blocked','restricted_to_advisory')),
  package_version     text not null default '2026.08.14',
  updated_at          timestamptz not null default now(),
  primary key (agent_key, packaged_role_id)
);
create index if not exists org_role_identity_role on org_role_identity (packaged_role_id);
create index if not exists org_role_identity_dept on org_role_identity (packaged_department);

-- On-demand category identities: the 86 packaged specialists are overlays on the existing
-- route catalogue, not 86 standing agents.
create table if not exists org_category_identity (
  category_key      text primary key,              -- 001_construction-materials-suppliers
  catalog_num       integer not null,
  route_key         text not null,
  owner_agent       text references org_agents(agent_key),
  package_version   text not null default '2026.08.14',
  readiness         text not null default 'knowledge_imported',
  updated_at        timestamptz not null default now()
);

-- ------------------------------------------------------- ops_knowledge V3 characteristics
alter table ops_knowledge
  add column if not exists package            text,
  add column if not exists package_version    text,
  add column if not exists generation         text,
  add column if not exists layer              text,
  add column if not exists role_key           text,
  add column if not exists category_key       text,
  add column if not exists jurisdiction       text not null default 'AE',
  add column if not exists source_type        text,
  add column if not exists source_authority   text,
  add column if not exists source_freshness   text not null default 'stable',
  add column if not exists confidentiality    text not null default 'internal',
  add column if not exists runtime_eligible   boolean not null default true,
  add column if not exists deterministic      boolean not null default false,
  add column if not exists supersedes_id      text,
  add column if not exists supersession_state text not null default 'current',
  add column if not exists checksum           text,
  add column if not exists ingestion_run_id   uuid,
  add column if not exists embedding_status   text not null default 'not_required',
  add column if not exists source_path        text;

do $$ begin
  alter table ops_knowledge add constraint ops_knowledge_layer_ck check (layer is null or layer in
    ('company_core','department_shared','role_specific','task_specific','category_specialist',
     'validated_experience','policy','authority','kpi','decision_playbook','case_training',
     'failure_mode','remediation','source_reference'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table ops_knowledge add constraint ops_knowledge_supersession_ck
    check (supersession_state in ('current','superseded','withdrawn'));
exception when duplicate_object then null; end $$;

-- Retrieval always filters on these three together.
create index if not exists ops_knowledge_runtime_lookup
  on ops_knowledge (runtime_eligible, layer, scope_type, scope_key)
  where supersession_state = 'current';
create index if not exists ops_knowledge_role on ops_knowledge (role_key) where role_key is not null;
create index if not exists ops_knowledge_category on ops_knowledge (category_key) where category_key is not null;
create index if not exists ops_knowledge_run on ops_knowledge (ingestion_run_id);

-- ------------------------------------------------------------------ training cases
-- Training material is not knowledge. It is never retrieved by task-time context assembly;
-- it is handed out by the remediation loop, one targeted set at a time.
create table if not exists agent_training_case (
  case_id          text primary key,
  generation       text not null check (generation in ('V1','V2','V3')),
  package          text not null,
  package_version  text not null,
  scope_type       text not null check (scope_type in ('role','department','category','company')),
  scope_key        text not null,
  case_family      text not null,
  competency       text,
  company_stage    text,
  payload          jsonb not null,
  checksum         text not null,
  ingestion_run_id uuid,
  created_at       timestamptz not null default now()
);
create index if not exists agent_training_case_scope on agent_training_case (scope_type, scope_key, case_family);
create index if not exists agent_training_case_family on agent_training_case (case_family);
create index if not exists agent_training_case_run on agent_training_case (ingestion_run_id);

-- Which cases an agent has already been shown, so remediation retests on unseen material.
create table if not exists agent_training_attempt (
  id               bigserial primary key,
  agent_key        text not null references org_agents(agent_key) on delete cascade,
  case_id          text not null references agent_training_case(case_id) on delete cascade,
  purpose          text not null check (purpose in ('practice','retest','drift_check')),
  failure_class    text,
  competency       text,
  score            numeric,
  passed           boolean,
  model            text,
  input_tokens     integer,
  output_tokens    integer,
  cost_aed         numeric,
  detail           jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now()
);
create index if not exists agent_training_attempt_agent on agent_training_attempt (agent_key, created_at desc);
create unique index if not exists agent_training_attempt_unseen on agent_training_attempt (agent_key, case_id, purpose);

-- A remediation cycle: what failed, what was assigned, whether the retest on unseen
-- material actually improved, and whether autonomy stays blocked.
create table if not exists agent_remediation (
  id               bigserial primary key,
  agent_key        text not null references org_agents(agent_key) on delete cascade,
  failure_class    text not null,
  competency       text not null,
  opened_at        timestamptz not null default now(),
  closed_at        timestamptz,
  status           text not null default 'open' check (status in ('open','training','retesting','passed','escalated','abandoned')),
  attempts         integer not null default 0,
  max_attempts     integer not null default 3,
  cost_aed         numeric not null default 0,
  max_cost_aed     numeric not null default 5,
  baseline_score   numeric,
  latest_score     numeric,
  blocks_autonomy  boolean not null default true,
  detail           jsonb not null default '{}'::jsonb
);
create index if not exists agent_remediation_open on agent_remediation (agent_key) where status <> 'passed';

-- ---------------------------------------------------------------- certification island
-- Runtime agents reach the database as `anon` or `authenticated`. This schema is granted to
-- neither, so no runtime retrieval path — SQL, lexical or vector — can see a question or an
-- answer. The builder session creates the island and leaves it empty.
create schema if not exists cert;
revoke all on schema cert from public;

create table if not exists cert.certification_question (
  question_id     text primary key,
  scope_type      text not null,
  scope_key       text not null,
  package_version text not null,
  payload         jsonb not null,
  loaded_at       timestamptz not null default now()
);

create table if not exists cert.certification_answer_key (
  question_id     text primary key,
  package_version text not null,
  payload         jsonb not null,
  loaded_at       timestamptz not null default now()
);

-- Append-only: an evaluator writes a result once and nobody edits it afterwards.
create table if not exists cert.certification_result (
  result_id       uuid primary key default gen_random_uuid(),
  question_id     text not null,
  agent_key       text not null,
  packaged_role_id text,
  answered_at     timestamptz not null default now(),
  raw_output      text not null,
  score           numeric,
  passed          boolean,
  environment     jsonb not null default '{}'::jsonb,
  evaluator       text not null
);

create or replace function cert.no_mutation() returns trigger
language plpgsql as $$
begin
  raise exception 'cert.% is append-only', tg_table_name;
end $$;

drop trigger if exists certification_result_append_only on cert.certification_result;
create trigger certification_result_append_only
  before update or delete on cert.certification_result
  for each row execute function cert.no_mutation();

-- RLS: staging does not get it by event trigger the way production does, so it is explicit.
alter table org_department_alias  enable row level security;
alter table org_role_identity     enable row level security;
alter table org_category_identity enable row level security;
alter table agent_training_case   enable row level security;
alter table agent_training_attempt enable row level security;
alter table agent_remediation     enable row level security;
alter table knowledge_ingestion_run enable row level security;
alter table cert.certification_question   enable row level security;
alter table cert.certification_answer_key enable row level security;
alter table cert.certification_result     enable row level security;

-- No policies are created for the certification island: RLS on with zero policies denies
-- every non-owner role, which is exactly the boundary required.
