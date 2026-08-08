-- 4 Aug 2026. The 17 tables the three 31-July reference migrations specify and production did not
-- have. Adapted, not applied blindly, as those files instruct:
--
--   * `executive_control_session` is NOT created. `public.control_mode_session` already is that
--     table - id uuid, user_id, reason, expires_at, closed_at, mfa_method/mfa_ref, plus ip,
--     user_agent and actions_used that the spec does not have. Creating a second one would breach
--     the pack's own first acceptance gate ("No duplicate portal/OS architecture was introduced")
--     and fork Control Mode state across two tables. A view carries the specified NAME onto the
--     real table instead, so anything written against the spec resolves, and there is one session
--     of record.
--   * FK targets were checked before writing: workflow.workflow_key text, company_event.id bigint,
--     leads.id bigint, inquiries.id / customers.id / quotes.id uuid. All match.
--   * RLS is ON with ZERO policies on every new table, which is the house pattern established when
--     the supplier-docs bucket policies were superseded: no anon/authenticated reach, all access
--     through edge functions on the service role.
--
-- These tables are the run model the approval path needs underneath it. Creating them does not
-- turn anything on - nothing writes them yet - but it ends the state where a workflow could be
-- declared and never executed because there was nowhere to record a run.

-- ============================================================ shared autonomy foundation
create table if not exists public.workflow_run (
  id uuid primary key default gen_random_uuid(),
  workflow_key text not null references public.workflow(workflow_key),
  trigger_event_id bigint references public.company_event(id),
  correlation_id uuid not null,
  entity_type text,
  entity_id text,
  idempotency_key text not null unique,
  status text not null default 'queued',
  current_step integer not null default 0,
  context jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  next_attempt_at timestamptz,
  lease_owner text,
  lease_expires_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  error jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ix_workflow_run_correlation on public.workflow_run(correlation_id);
create index if not exists ix_workflow_run_status on public.workflow_run(status, next_attempt_at);

create table if not exists public.workflow_step_run (
  id bigserial primary key,
  workflow_run_id uuid not null references public.workflow_run(id) on delete cascade,
  step_no integer not null,
  actor text,
  action_class text,
  status text not null default 'queued',
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  idempotency_key text not null unique,
  attempts integer not null default 0,
  started_at timestamptz,
  finished_at timestamptz,
  error jsonb,
  unique(workflow_run_id, step_no)
);

create table if not exists public.decision_trace (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null,
  causation_event_id bigint references public.company_event(id),
  entity_type text,
  entity_id text,
  decision_type text not null,
  proposed_by text,
  decided_by text,
  policy_keys text[] not null default '{}',
  knowledge_refs jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  alternatives jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  risk jsonb not null default '{}'::jsonb,
  confidence numeric,
  authority_result jsonb not null default '{}'::jsonb,
  decision jsonb not null,
  outcome_status text not null default 'pending',
  outcome jsonb,
  created_at timestamptz not null default now(),
  evaluated_at timestamptz
);
create index if not exists ix_decision_trace_correlation on public.decision_trace(correlation_id);

create table if not exists public.action_execution (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null,
  workflow_step_run_id bigint references public.workflow_step_run(id),
  action_class text not null,
  executor text not null,
  idempotency_key text not null unique,
  risk_tier text not null,
  reversible boolean not null default false,
  request jsonb not null,
  response jsonb,
  status text not null default 'queued',
  attempts integer not null default 0,
  compensation_action_class text,
  compensated_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists ix_action_execution_correlation on public.action_execution(correlation_id);

-- The specified name, on the table that already exists. Not a second session store.
create or replace view public.executive_control_session as
select s.id,
       s.user_id,
       case when s.closed_at is null and s.expires_at > now() then 'control' else 'observe' end as mode,
       s.mfa_ref     as mfa_session_id,
       s.reason,
       s.opened_at   as created_at,
       s.expires_at,
       s.closed_at   as revoked_at
from public.control_mode_session s;
comment on view public.executive_control_session is
  'The 31-July shared-autonomy pack specifies this name; public.control_mode_session is the real table. A view, not a second session store - see the migration header.';

-- ============================================================ the event backbone contract
alter table public.company_event add column if not exists correlation_id uuid;
alter table public.company_event add column if not exists causation_id bigint;
alter table public.company_event add column if not exists event_version integer not null default 1;
alter table public.company_event add column if not exists dedupe_key text;
create unique index if not exists ux_company_event_dedupe on public.company_event(dedupe_key) where dedupe_key is not null;
create index if not exists ix_company_event_correlation on public.company_event(correlation_id);

-- ============================================================ supplier portal
create table if not exists public.supplier_catalog (
  id uuid primary key default gen_random_uuid(),
  supplier_id bigint not null references public.leads(id),
  source_document_path text,
  source_hash text,
  version integer not null default 1,
  status text not null default 'processing',
  extracted_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(supplier_id, source_hash)
);

create table if not exists public.supplier_product (
  id uuid primary key default gen_random_uuid(),
  supplier_id bigint not null references public.leads(id),
  catalog_id uuid references public.supplier_catalog(id),
  external_key text,
  name text not null,
  category_slug text,
  subcategory_slug text,
  brand text,
  model text,
  description text,
  attributes jsonb not null default '{}'::jsonb,
  certifications jsonb not null default '[]'::jsonb,
  documents jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(supplier_id, external_key)
);

create table if not exists public.supplier_product_variant (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.supplier_product(id) on delete cascade,
  sku text,
  attributes jsonb not null default '{}'::jsonb,
  price_policy jsonb,
  lead_time_policy jsonb,
  active boolean not null default true,
  unique(product_id, sku)
);

create table if not exists public.supplier_opportunity_score (
  supplier_id bigint not null references public.leads(id),
  inquiry_id uuid not null references public.inquiries(id),
  score numeric not null,
  eligibility boolean not null,
  reasons jsonb not null default '[]'::jsonb,
  risks jsonb not null default '[]'::jsonb,
  calculated_at timestamptz not null default now(),
  algorithm_version text not null,
  primary key(supplier_id, inquiry_id)
);

create table if not exists public.supplier_negotiation_policy (
  supplier_id bigint primary key references public.leads(id),
  policy jsonb not null default '{}'::jsonb,
  approved_by text,
  approved_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ============================================================ customer portal
create table if not exists public.customer_organization (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_customer_id uuid references public.customers(id),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.customer_organization_member (
  organization_id uuid not null references public.customer_organization(id) on delete cascade,
  user_id uuid not null,
  role text not null,
  permissions jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  primary key(organization_id, user_id)
);

create table if not exists public.customer_preference (
  customer_id uuid primary key references public.customers(id),
  preferences jsonb not null default '{}'::jsonb,
  consented_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.comparison_run_v2 (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.inquiries(id),
  quote_signature text not null,
  algorithm_version text not null,
  corpus_version text,
  customer_priority jsonb not null default '{}'::jsonb,
  status text not null default 'processing',
  deterministic_result jsonb,
  explanation_en jsonb,
  explanation_ar jsonb,
  created_at timestamptz not null default now(),
  unique(inquiry_id, quote_signature, algorithm_version)
);

create table if not exists public.comparison_candidate_v2 (
  comparison_run_id uuid not null references public.comparison_run_v2(id) on delete cascade,
  quote_id uuid not null references public.quotes(id),
  rank integer,
  eligible boolean not null,
  hard_gates jsonb not null default '{}'::jsonb,
  score_breakdown jsonb not null default '{}'::jsonb,
  missing jsonb not null default '[]'::jsonb,
  deviations jsonb not null default '[]'::jsonb,
  primary key(comparison_run_id, quote_id)
);

create table if not exists public.procurement_approval_policy (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.customer_organization(id),
  name text not null,
  conditions jsonb not null,
  steps jsonb not null,
  active boolean not null default true
);

create table if not exists public.procurement_approval_request (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.customer_organization(id),
  entity_type text not null,
  entity_id text not null,
  policy_id uuid references public.procurement_approval_policy(id),
  status text not null default 'pending',
  current_step integer not null default 1,
  decisions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

-- ============================================================ RLS: on, with no policies
do $$
declare t text;
begin
  foreach t in array array[
    'workflow_run','workflow_step_run','decision_trace','action_execution',
    'supplier_catalog','supplier_product','supplier_product_variant',
    'supplier_opportunity_score','supplier_negotiation_policy',
    'customer_organization','customer_organization_member','customer_preference',
    'comparison_run_v2','comparison_candidate_v2',
    'procurement_approval_policy','procurement_approval_request'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;
revoke all on public.executive_control_session from anon, authenticated;
grant select on public.executive_control_session to service_role;;
