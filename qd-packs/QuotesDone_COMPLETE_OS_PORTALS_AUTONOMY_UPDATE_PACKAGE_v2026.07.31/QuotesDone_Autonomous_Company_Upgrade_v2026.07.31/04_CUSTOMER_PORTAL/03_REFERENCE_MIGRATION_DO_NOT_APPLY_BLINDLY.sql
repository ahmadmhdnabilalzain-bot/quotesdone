-- REFERENCE ONLY. Reconcile with existing tables before migration.

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
  primary key(organization_id,user_id)
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
  primary key(comparison_run_id,quote_id)
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

-- Apply strict organization/customer RLS and preserve the simple single-user flow for existing customers.
