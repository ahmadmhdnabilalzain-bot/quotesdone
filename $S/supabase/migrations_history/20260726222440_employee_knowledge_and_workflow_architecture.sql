-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726222440   name: employee_knowledge_and_workflow_architecture
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Employees, knowledge and workflows are now three separate things that bind at runtime,
-- rather than knowledge being hard-coded into each employee.

-- The 12 knowledge layers every employee must carry.
create table if not exists public.employee_knowledge_standard (
  layer_no   int primary key,
  layer      text not null unique,
  intent     text not null,
  binds_via  text not null,          -- knowledge_domain | company | workflow | runtime | memory | kpi
  required   boolean not null default true
);
alter table public.employee_knowledge_standard enable row level security;

-- Reusable knowledge domains. One domain, many employees. Update expertise without
-- redesigning the workforce.
create table if not exists public.knowledge_domain (
  domain_key  text primary key,
  name        text not null,
  kind        text not null,          -- product_category | functional | company | regulatory | sop | software
  description text,
  source      text,                   -- where the content actually lives
  active      boolean not null default true
);
alter table public.knowledge_domain enable row level security;

-- Which employee loads which domain, and at what depth.
-- depth='awareness' is the founder's Cross-Department layer: enough to collaborate, not to be the expert.
create table if not exists public.employee_knowledge (
  agent_key  text not null,
  domain_key text not null references public.knowledge_domain(domain_key) on delete cascade,
  depth      text not null default 'working',   -- expert | working | awareness
  layer_no   int references public.employee_knowledge_standard(layer_no),
  primary key (agent_key, domain_key)
);
alter table public.employee_knowledge enable row level security;

-- Reusable business processes.
create table if not exists public.workflow (
  workflow_key text primary key,
  name         text not null,
  trigger_event text,
  description  text,
  active       boolean not null default true
);
alter table public.workflow enable row level security;

create table if not exists public.workflow_step (
  workflow_key text not null references public.workflow(workflow_key) on delete cascade,
  step_no      int not null,
  step         text not null,
  actor_role   text,                  -- title or seniority expected to perform it
  action_class text,
  gate         text,                  -- none | dept_head | chief_of_staff | founder
  primary key (workflow_key, step_no)
);
alter table public.workflow_step enable row level security;

create table if not exists public.employee_workflow (
  agent_key    text not null,
  workflow_key text not null references public.workflow(workflow_key) on delete cascade,
  role_in_workflow text not null default 'participant',  -- owner | reviewer | approver | participant
  primary key (agent_key, workflow_key)
);
alter table public.employee_workflow enable row level security;

insert into employee_knowledge_standard (layer_no, layer, intent, binds_via) values
(1,'Domain Knowledge','The professional discipline the role is hired for.','knowledge_domain'),
(2,'Company Knowledge','Vision, mission, values, org chart, policies, SOPs, approval matrix, revenue model, customer and supplier journeys.','company'),
(3,'Department Knowledge','Everything within the employee''s own department.','knowledge_domain'),
(4,'Cross Department Knowledge','Enough of other departments to collaborate - not to be the expert. Bound at depth=awareness.','knowledge_domain'),
(5,'Software Knowledge','QuotesDone OS, CRM, portals, email, WhatsApp, calendar, dashboards, knowledge base.','knowledge_domain'),
(6,'Workflow Knowledge','The end-to-end processes the employee participates in.','workflow'),
(7,'Decision Knowledge','When to decide, escalate, reject, approve, ask more, or involve Legal/Finance/CoS/CEO.','runtime'),
(8,'Communication Knowledge','How to adapt tone and language per audience.','knowledge_domain'),
(9,'Experience Knowledge','Lessons learned, past decisions, customer and supplier behaviour, real-world judgement.','memory'),
(10,'Improvement Knowledge','Can this be improved, automated, made cheaper, faster, better, less error-prone?','runtime'),
(11,'KPI Knowledge','Own, department and company KPIs with weekly to annual targets.','kpi'),
(12,'AI Self Knowledge','Own limitations, confidence, reasoning, memory, tools, APIs, knowledge sources, escalation rules.','runtime')
on conflict (layer_no) do nothing;

-- Compliance for employees, parallel to v_knowledge_compliance for category knowledge bases.
create or replace view public.v_employee_knowledge_compliance as
select a.agent_key, a.title, a.department, a.seniority,
       count(distinct ek.layer_no) as layers_bound,
       (select count(*) from employee_knowledge_standard where required) as layers_required,
       (select count(*) from employee_workflow w where w.agent_key = a.agent_key) as workflows,
       (select count(*) from employee_kpi k where k.agent_key = a.agent_key and k.active) as kpis,
       (select count(*) from employee_authority ea where ea.agent_key = a.agent_key) as authorities,
       case when count(distinct ek.layer_no) = (select count(*) from employee_knowledge_standard where required)
             and (select count(*) from employee_kpi k where k.agent_key = a.agent_key and k.active) > 0
            then 'COMPLIANT' else 'INCOMPLETE' end as verdict
from org_agents a
left join employee_knowledge ek on ek.agent_key = a.agent_key
where a.active
group by a.agent_key, a.title, a.department, a.seniority;

comment on table public.knowledge_domain is 'Reusable knowledge domains. Employees bind to these; expertise updates without redesigning the workforce.';
comment on table public.workflow is 'Reusable business processes. Employees bind to these rather than each owning a private copy.';
