-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726233429   name: continuity_vendor_career_evolution
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Item 16: Business continuity. Per-vendor fallback, degraded mode, recovery.
create table if not exists public.continuity_plan (
  service        text primary key references public.integration_matrix(service),
  criticality    text not null default 'high',   -- critical | high | medium | low
  failure_mode   text not null,
  detection      text not null,
  fallback       text not null,
  degraded_mode  text not null,
  recovery       text not null,
  rto_minutes    int,
  owner_agent    text,
  last_tested    date
);
alter table public.continuity_plan enable row level security;

-- Item 17: Vendor management.
alter table public.integration_matrix add column if not exists monthly_cost_aed numeric;
alter table public.integration_matrix add column if not exists sla_uptime_pct   numeric;
alter table public.integration_matrix add column if not exists renewal_date     date;
alter table public.integration_matrix add column if not exists alternatives     text;
alter table public.integration_matrix add column if not exists usage_limit_note text;
alter table public.integration_matrix add column if not exists last_reviewed    date;

-- Item 14: AI career system. Progression on evidence, not elapsed time.
create table if not exists public.career_level (
  level_no    int primary key,
  level_name  text not null unique,
  criteria    text not null,
  min_kpis_met_pct numeric,
  min_runs    int,
  max_error_rate_pct numeric
);
alter table public.career_level enable row level security;

create table if not exists public.promotion_record (
  id          bigserial primary key,
  agent_key   text not null,
  from_level  text,
  to_level    text not null,
  reason      text not null,
  evidence    text,
  decided_by  text not null default 'hr_director',
  decided_at  timestamptz not null default now()
);
alter table public.promotion_record enable row level security;

insert into career_level (level_no, level_name, criteria, min_kpis_met_pct, min_runs, max_error_rate_pct) values
(1,'junior','Executes defined tasks under supervision. All output reviewed by a manager.',0,0,20),
(2,'specialist','Owns a domain. Advisory-safe actions run autonomously. Output sampled, not fully reviewed.',60,50,10),
(3,'senior','Consistently meets KPIs. Trusted on non-gated actions in their domain without review.',75,200,5),
(4,'lead','Reviews the work of specialists. Can reject and request revision within the department.',80,500,3),
(5,'director','Owns department outcomes and approves department output before it leaves.',85,1000,2),
(6,'vp','Owns multiple departments or a company-level outcome.',90,2000,1),
(7,'chief','Company-level authority. Sets strategy or owns a whole function.',90,2000,1)
on conflict (level_no) do nothing;

-- Item 15: Self-evolution. The company reviews itself on a cycle.
create table if not exists public.self_review (
  id           bigserial primary key,
  review_type  text not null,   -- stale_sop | stale_knowledge | overloaded_dept | missed_kpi | recurring_failure
  subject      text not null,
  finding      text not null,
  evidence     text,
  proposal     text,
  status       text not null default 'proposed', -- proposed | approved | rejected | implemented | measured
  impact       text,
  reviewed_by  text,
  created_at   timestamptz not null default now()
);
alter table public.self_review enable row level security;

comment on table public.continuity_plan is 'Item 16: what happens when each external service fails, and how the company degrades rather than stops.';
comment on table public.career_level is 'Item 14: progression gates on measured performance, not elapsed time.';
