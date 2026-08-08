-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726221611   name: knowledge_module_standard_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The Expert Knowledge Framework, encoded as an enforceable standard rather than
-- a document. Every category employee is measured against these rows.
create table if not exists public.knowledge_module_standard (
  module        text primary key,
  ord           int not null,
  spec_layers   text not null,          -- which of the founder's 24 layers this module carries
  intent        text not null,
  min_chars     int not null default 600,
  priority      int not null default 4,
  required      boolean not null default true,
  added_in      text not null default 'v2'
);
alter table public.knowledge_module_standard enable row level security;

insert into knowledge_module_standard (module, ord, spec_layers, intent, min_chars, priority, added_in) values
('Industry Knowledge',1,'L1 Domain Fundamentals','Terminology, acronyms, definitions, industry hierarchy, who buys, buying cycles, supplier tiers, seasonality.',600,5,'v1'),
('Products & Services',2,'L4 Products & Services','Product categories, variations, compatibility, alternatives, lifecycle, applications, selection criteria, wrapped services.',600,5,'v1'),
('Technical Knowledge',3,'L2 Technical','Components, materials, systems, specifications, installation methods, maintenance, performance characteristics.',600,4,'v1'),
('Brands & Manufacturers',4,'L5 Brands & Manufacturers','Global manufacturers, UAE distributors and agents, premium vs budget positioning, real quality differences, manufacturer documentation.',600,4,'v2'),
('Supplier Knowledge',5,'L6 UAE Supplier Market','Supplier archetypes, capabilities, specialities, limitations, delivery areas, lead times, reputation, certifications, what to verify.',600,4,'v1'),
('Commercial & Pricing',6,'L8 Commercial','Cost drivers, pricing factors, budget tiers, value engineering, payment terms, lead-time impact, negotiation levers, commercial risk.',600,5,'v2'),
('Customer Requirements & Trade-offs',7,'L9 Customer Requirements','Customer objectives, budget and time constraints, quality expectations, functional vs operational needs, future expansion, risk tolerance, the trade-offs an expert names.',600,4,'v2'),
('Quotation Knowledge',8,'L7 Procurement','Mandatory information to quote, what drives price and delivery, what makes suppliers reject an inquiry.',600,5,'v1'),
('Documents Knowledge',9,'L7 Procurement','BOQ, drawings, submittals, datasheets, method statements, test certificates, permits - and when each is needed.',600,4,'v1'),
('UAE Regulations & Authorities',10,'L3 Standards & Regulations','Named UAE/Dubai/Abu Dhabi authorities with real URLs, civil defence and municipality requirements, international standards, certification and HSE.',600,5,'v1'),
('Risk Assessment',11,'L15 Risk','Technical, commercial, legal, financial, operational, schedule, supplier and customer risks - with the early warning signs for each.',600,4,'v2'),
('Troubleshooting & Diagnostics',12,'L16 Troubleshooting','Common problems, root causes, diagnostic sequence, resolution options, escalation criteria, preventive action.',600,4,'v2'),
('Best Practices & Common Mistakes',13,'L12 Checklists, L13 Best Practices, L14 Common Mistakes','Professional checklists, industry best practice, and the frequent customer/supplier/documentation/compliance mistakes to prevent proactively.',700,5,'v2'),
('Inquiry Qualification Logic',14,'L10 Requirement Collection, L11 Decision Trees','Ordered question sequence, mandatory vs skippable, explicit if-A-then-X decision rules, confidence thresholds, when to escalate or reclassify.',600,5,'v1')
on conflict (module) do nothing;

-- Compliance is now a query, not an opinion.
create or replace view public.v_knowledge_compliance as
select a.slug as agent_slug, a.name, a.agent_class,
       count(k.topic) filter (where k.topic is not null) as modules_present,
       (select count(*) from knowledge_module_standard where required) as modules_required,
       string_agg(s.module, ', ' order by s.ord) filter (where k.topic is null) as missing_modules,
       case when count(k.topic) filter (where k.topic is not null)
                 = (select count(*) from knowledge_module_standard where required)
            then 'COMPLIANT' else 'INCOMPLETE' end as verdict
from category_agents a
cross join knowledge_module_standard s
left join agent_knowledge k on k.agent_key = 'cat:'||a.slug and k.topic = s.module
where s.required and a.agent_class <> 'internal_staff'
group by a.slug, a.name, a.agent_class;

comment on table public.knowledge_module_standard is 'Expert Knowledge Framework v2: 14 required modules mapping to the founder 24-layer spec.';
comment on view public.v_knowledge_compliance is 'Per-employee compliance against the knowledge standard. COMPLIANT requires all 14 modules.';
