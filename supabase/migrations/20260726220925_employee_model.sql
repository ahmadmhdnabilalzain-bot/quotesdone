-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726220925   name: employee_model
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Employees, not agents. An employee object carries everything a real professional
-- has: a manager, direct reports, owned KPIs, authority limits, workload, goals,
-- performance history and an improvement plan.
alter table public.org_agents add column if not exists title            text;
alter table public.org_agents add column if not exists manager_key      text;
alter table public.org_agents add column if not exists seniority        text;      -- director | manager | specialist
alter table public.org_agents add column if not exists responsibilities text;
alter table public.org_agents add column if not exists max_open_tasks   int not null default 5;
alter table public.org_agents add column if not exists improvement_plan text;
alter table public.org_agents add column if not exists hired_at         timestamptz not null default now();

-- Per-employee measurable KPIs, tied to the company goals they serve.
create table if not exists public.employee_kpi (
  id           bigserial primary key,
  agent_key    text not null,
  kpi          text not null,
  metric       text not null,
  target_value numeric,
  unit         text,
  cadence      text not null default 'monthly',
  serves_goal  text references public.company_goals(key),
  measure_sql  text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (agent_key, kpi)
);
alter table public.employee_kpi enable row level security;

-- Per-employee authority. org_authority is department-level; a Director and a
-- specialist in the same department must not carry the same limits.
create table if not exists public.employee_authority (
  agent_key    text not null,
  action_class text not null,
  max_tier     text not null default 'advisory',   -- autonomous | gated | advisory
  threshold_aed numeric,
  note         text,
  primary key (agent_key, action_class)
);
alter table public.employee_authority enable row level security;

-- The review chain. A draft moves specialist -> manager -> Chief of Staff.
-- Every hop is a row, so the approval chain can be reconstructed from data
-- rather than narrated by a model.
create table if not exists public.review_chain (
  id            bigserial primary key,
  subject_type  text not null,          -- social_post | campaign | contract | budget | quote
  subject_id    text not null,
  dept_key      text not null,
  author_agent  text not null,
  reviewer_agent text,
  stage         text not null,          -- drafted | dept_review | cos_review | founder_review | published | rejected
  decision      text,                   -- approve | reject | request_revision
  reason        text,
  violated_rule text,
  confidence    numeric,
  created_at    timestamptz not null default now()
);
alter table public.review_chain enable row level security;
create index if not exists review_chain_subject_idx on public.review_chain(subject_type, subject_id, id);

comment on table public.employee_kpi is 'Artifact: every employee owns measurable KPIs tied to company_goals.';
comment on table public.employee_authority is 'Per-employee authority limits, finer-grained than department-level org_authority.';
comment on table public.review_chain is 'Append-only approval chain. Reconstructs who decided what, why, and against which rule.';
