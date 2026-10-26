-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726222754   name: knowledge_lifecycle_governance_digital_twin
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- KNOWLEDGE LIFECYCLE: knowledge must not just accumulate.
alter table public.agent_knowledge add column if not exists source_ref      text;
alter table public.agent_knowledge add column if not exists owner_agent     text;
alter table public.agent_knowledge add column if not exists version         int not null default 1;
alter table public.agent_knowledge add column if not exists confidence      numeric;
alter table public.agent_knowledge add column if not exists validation_status text not null default 'unvalidated';
alter table public.agent_knowledge add column if not exists review_due      date;
alter table public.agent_knowledge add column if not exists supersedes_id   bigint;

-- ORGANIZATIONAL GOVERNANCE: escalation, delegation and conflict resolution as data.
create table if not exists public.governance_rule (
  id           bigserial primary key,
  rule_type    text not null,      -- escalation | delegation | conflict_resolution | approval_hierarchy
  scope        text not null,      -- dept_key, agent_key, or 'company'
  condition    text not null,
  action       text not null,
  routes_to    text,
  priority     int not null default 3,
  active       boolean not null default true
);
alter table public.governance_rule enable row level security;

-- GOAL CASCADE: annual -> quarterly -> monthly -> weekly -> today.
create table if not exists public.goal_period (
  id          bigserial primary key,
  goal_key    text references public.company_goals(key) on delete cascade,
  horizon     text not null,       -- annual | quarterly | monthly | weekly | today
  period_label text not null,
  target_value numeric,
  actual_value numeric,
  owner_dept  text,
  status      text not null default 'open',
  updated_at  timestamptz not null default now(),
  unique (goal_key, horizon, period_label)
);
alter table public.goal_period enable row level security;

-- QUALITY FRAMEWORK: what excellent looks like, per work type.
create table if not exists public.quality_standard (
  work_type   text primary key,
  criteria    jsonb not null,      -- ordered checklist of what "excellent" means
  owner_dept  text,
  updated_at  timestamptz not null default now()
);
alter table public.quality_standard enable row level security;

-- FEEDBACK ENGINE
create table if not exists public.feedback (
  id          bigserial primary key,
  source      text not null,       -- customer | supplier | internal_review | department_review | system | ai_review
  subject_type text,
  subject_id  text,
  rating      numeric,
  comment     text,
  actioned    boolean not null default false,
  action_taken text,
  created_at  timestamptz not null default now()
);
alter table public.feedback enable row level security;

-- DIGITAL TWIN: the live operational picture, assembled from real tables only.
create or replace view public.v_digital_twin as
select
  (select count(*) from org_agents where active)                                    as employees_active,
  (select count(*) from org_departments where active)                               as departments,
  (select count(*) from company_goals where active)                                 as company_goals,
  (select count(*) from catalog_supplier_categories)                                as categories_target,
  (select count(*) from category_agent_map where status='mapped')                   as categories_covered,
  (select count(*) from v_knowledge_compliance where verdict='COMPLIANT')           as knowledge_bases_compliant,
  (select count(*) from leads)                                                      as suppliers_in_pipeline,
  (select count(*) from inquiries)                                                  as inquiries_total,
  (select count(*) from quotes)                                                     as quotes_total,
  (select count(*) from transactions)                                               as transactions_total,
  (select coalesce(sum(amount_aed),0) from (select 0::numeric as amount_aed) z)      as revenue_placeholder,
  (select count(*) from org_tasks where status in ('assigned','in_progress'))       as work_in_progress,
  (select count(*) from org_tasks where status='proposed')                          as awaiting_founder,
  (select count(*) from risk_register where status='open')                          as open_risks,
  (select count(*) from institutional_memory)                                       as memories_held,
  (select count(*) from company_event where occurred_at > now() - interval '24 hours') as events_24h,
  (select count(*) from agent_runs where started_at > now() - interval '24 hours')  as agent_runs_24h,
  (select count(*) from agent_runs where started_at > now() - interval '24 hours' and status='error') as agent_errors_24h,
  (select count(*) from spec_backlog where status='pending')                        as open_backlog,
  (select count(*) from spec_backlog where status='pending' and priority=1)         as open_p1;

comment on view public.v_digital_twin is 'Live operational picture of the company, assembled from real tables. No narration.';
comment on table public.governance_rule is 'Escalation, delegation, conflict-resolution and approval-hierarchy rules as configurable data.';
