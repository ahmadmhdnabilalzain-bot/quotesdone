-- Blueprint components 2,3,4,7,8: mission, objectives at five horizons, EXCLUSIVE
-- responsibility ownership, declared inputs and declared outputs.

alter table public.operating_system
  add column if not exists mission text,
  add column if not exists health_score numeric,
  add column if not exists last_health_at timestamptz;

update operating_system set mission = m.mission from (values
 ('leadership','Continuously steer the company toward long-term growth while balancing risk, profitability and customer value.'),
 ('commercial','Create and convert qualified demand at a cost the business can sustain.'),
 ('marketplace','Match every qualified buyer with suppliers who can actually deliver, faster than anyone else in the UAE.'),
 ('operations','Make work flow predictably and hold quality without slowing the company down.'),
 ('technology','Keep the platform available, secure, fast and cheap enough to run without thinking about it.'),
 ('finance','Protect the money, allocate it where it earns most, and always know the true position.'),
 ('legal_gov','Keep every action lawful, every decision defensible and every risk named before it bites.'),
 ('knowledge','Ensure every employee answers from current, cited, validated knowledge and never from memory alone.'),
 ('intelligence','Tell the company what is actually happening and what happens next, before it has to guess.'),
 ('evolution','Make the company measurably better every week and reverse anything that made it worse.')
) m(os_key,mission) where operating_system.os_key = m.os_key;

-- 4. EXCLUSIVE RESPONSIBILITY. One OS owns each domain. No duplicated ownership.
create table if not exists public.os_responsibility (
  responsibility text primary key,
  os_key         text not null references operating_system(os_key),
  note           text
);
alter table public.os_responsibility enable row level security;
comment on table public.os_responsibility is
  'Primary key is the responsibility, so a domain can be owned by exactly one operating system. Duplicated ownership is impossible by construction.';

insert into os_responsibility (responsibility, os_key) values
 ('vision','leadership'),('mission','leadership'),('strategy','leadership'),('company_goals','leadership'),
 ('priorities','leadership'),('executive_decisions','leadership'),('budget_approval','leadership'),
 ('resource_allocation','leadership'),('org_authority_model','leadership'),
 ('marketing','commercial'),('sales','commercial'),('business_development','commercial'),
 ('partnerships','commercial'),('brand','commercial'),('revenue_growth','commercial'),
 ('customers','marketplace'),('suppliers','marketplace'),('rfqs','marketplace'),('matching','marketplace'),
 ('quotes','marketplace'),('procurement','marketplace'),('supplier_performance','marketplace'),
 ('category_coverage','marketplace'),
 ('daily_operations','operations'),('workflows','operations'),('quality','operations'),('slas','operations'),
 ('service_delivery','operations'),('process_documentation','operations'),
 ('infrastructure','technology'),('ai_runtime','technology'),('platform','technology'),('security','technology'),
 ('apis','technology'),('devops','technology'),('reliability','technology'),
 ('accounting','finance'),('treasury','finance'),('budgets','finance'),('payments','finance'),
 ('revenue_recognition','finance'),('financial_forecasting','finance'),('collections','finance'),
 ('contracts','legal_gov'),('compliance','legal_gov'),('uae_regulations','legal_gov'),('policies','legal_gov'),
 ('risk_register','legal_gov'),('auditing','legal_gov'),('data_protection','legal_gov'),
 ('knowledge_base','knowledge'),('rag_retrieval','knowledge'),('sops','knowledge'),('company_memory','knowledge'),
 ('learning_loop','knowledge'),('knowledge_validation','knowledge'),
 ('dashboards','intelligence'),('analytics','intelligence'),('business_forecasting','intelligence'),
 ('competitive_intelligence','intelligence'),('market_intelligence','intelligence'),
 ('customer_intelligence','intelligence'),('supplier_intelligence','intelligence'),('kpi_instrumentation','intelligence'),
 ('innovation','evolution'),('ai_optimisation','evolution'),('organisational_design','evolution'),
 ('performance_improvement','evolution'),('cost_optimisation','evolution'),('process_reengineering','evolution'),
 ('outcome_ledger','evolution')
on conflict (responsibility) do nothing;

-- 3. OBJECTIVES at five horizons, per OS
create table if not exists public.os_objective (
  id         bigserial primary key,
  os_key     text not null references operating_system(os_key),
  horizon    text not null check (horizon in ('strategic','annual','quarterly','weekly','daily')),
  objective  text not null,
  measure    text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (os_key, horizon, objective)
);
alter table public.os_objective enable row level security;

-- 7/8. INPUT and OUTPUT contract - what each OS consumes and produces
create table if not exists public.os_interface (
  id            bigserial primary key,
  os_key        text not null references operating_system(os_key),
  direction     text not null check (direction in ('input','output')),
  kind          text not null,
  description   text,
  event_type    text,
  active        boolean not null default true,
  unique (os_key, direction, kind)
);
alter table public.os_interface enable row level security;
comment on table public.os_interface is
  'The standardized interface each OS exposes. Inputs are the events it subscribes to; outputs are what it produces for the rest of the company. No OS calls another for business logic - it emits and subscribes.';

-- 9. workflows belong to an OS
alter table public.workflow add column if not exists os_key text references operating_system(os_key);
update workflow set os_key='marketplace' where os_key is null and workflow_key ilike any (array['%rfq%','%quote%','%supplier%','%inquiry%','%match%']);
update workflow set os_key='operations' where os_key is null;

-- 12. memory belongs to an OS
alter table public.institutional_memory add column if not exists os_key text references operating_system(os_key);