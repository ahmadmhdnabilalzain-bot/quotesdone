-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706003722   name: procurement_projects
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #6 Procurement Projects: group multiple related RFQs under one project
create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references customers(id) on delete cascade,
  name text not null,
  description text,
  status text not null default 'active',   -- active | completed | archived
  target_open_date date,
  budget_total numeric,
  meta jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists projects_customer on projects(customer_id);

alter table inquiries add column if not exists project_id uuid references projects(id) on delete set null;
create index if not exists inquiries_project on inquiries(project_id);

alter table projects enable row level security;
revoke all on projects from anon, authenticated;

-- Per-project rollup for dashboards
create or replace view project_summary as
select p.id as project_id, p.customer_id, p.name, p.status, p.target_open_date, p.budget_total, p.created_at,
  count(i.id)                                             as rfq_count,
  count(i.id) filter (where i.status not in ('completed','cancelled')) as rfq_open,
  count(i.id) filter (where i.hired_supplier_id is not null)           as rfq_awarded,
  round(coalesce(sum(i.expected_value),0),0)             as pipeline_value
from projects p
left join inquiries i on i.project_id = p.id
group by p.id, p.customer_id, p.name, p.status, p.target_open_date, p.budget_total, p.created_at;
revoke all on project_summary from anon, authenticated;
