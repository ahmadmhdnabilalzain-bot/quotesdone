-- REFERENCE MIGRATION ONLY. Claude must adapt this to the existing schema after Phase 0 audit.
-- Do not apply directly to production.

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

create table if not exists public.executive_control_session (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  mode text not null check (mode in ('observe','control')),
  mfa_session_id uuid,
  reason text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);

alter table public.company_event add column if not exists correlation_id uuid;
alter table public.company_event add column if not exists causation_id bigint;
alter table public.company_event add column if not exists event_version integer not null default 1;
alter table public.company_event add column if not exists dedupe_key text;
create unique index if not exists ux_company_event_dedupe on public.company_event(dedupe_key) where dedupe_key is not null;

-- RLS and grants must be designed after inspecting current role model. Do not expose these tables to anon/authenticated by default.
