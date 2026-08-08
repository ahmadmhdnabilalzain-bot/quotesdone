-- Departments describe WHO works. Operating Systems describe WHAT the company must be able
-- to do, who governs it, and how it adapts. Every department now sits inside exactly one OS,
-- every OS has a named executive owner and a mandate, and three genuine gaps get filled.

create table if not exists public.operating_system (
  os_key       text primary key,
  num          int not null,
  name         text not null,
  charter      text not null,
  mandate      text not null,
  owner_agent  text,
  adapts_by    text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
alter table public.operating_system enable row level security;

create table if not exists public.os_department (
  os_key   text not null references operating_system(os_key),
  dept_key text not null,
  note     text,
  primary key (os_key, dept_key)
);
alter table public.os_department enable row level security;

insert into operating_system (os_key, num, name, charter, mandate, owner_agent, adapts_by) values
('leadership', 1,'Leadership OS',
 'Sets direction, allocates priority, and holds every other OS to account.',
 'Owns company goals, the priority hierarchy, the constitution, the weekly executive meeting and the daily operating rhythm. Decides what the company works on and what it stops working on.',
 'ceo','Re-prioritises company goals when the executive meeting or CEO self-questioning shows the current ones are not moving.'),
('commercial', 2,'Commercial OS',
 'Creates and converts demand.',
 'Owns pipeline, campaigns, brand, partnerships and business development. Answerable for qualified demand reaching the Marketplace OS.',
 'sales_director','Reallocates spend and channel mix from campaign performance and attribution.'),
('marketplace', 3,'Marketplace OS',
 'Runs the two-sided market: suppliers, customers, RFQs and procurement.',
 'Owns supplier acquisition, onboarding, verification, category coverage, inquiry qualification, matching, quotation and award. This is the product.',
 'procurement','Rebalances category coverage and matching rules from supply-gap and match-evaluation data.'),
('operations', 4,'Operations OS',
 'Makes work flow and holds quality.',
 'Owns process, SLAs, quality gates, documentation, project coordination and bottleneck removal across every other OS.',
 'ops_director','Removes bottlenecks it detects in cycle time and quality-gate pass rates.'),
('technology', 5,'Technology OS',
 'Keeps the platform available, fast, secure and affordable to run.',
 'Owns infrastructure, application, AI runtime, model routing, security and deployment.',
 'cto','Switches model tiers, scales and self-heals from health, drift and cost signals.'),
('finance', 6,'Finance OS',
 'Protects and allocates money.',
 'Owns accounting, VAT and corporate tax, budgeting, treasury, collections, invoicing and financial reporting.',
 'cfo','Reallocates department budgets when spend, burn or runway move outside tolerance.'),
('legal_gov', 7,'Legal & Governance OS',
 'Keeps the company lawful and its decisions defensible.',
 'Owns contracts, compliance, PDPL and data protection, regulatory monitoring, risk register and the authority model.',
 'legal','Updates policy and authority limits when regulation or the risk register changes.'),
('knowledge', 8,'Knowledge OS',
 'Makes the company know things, and keep knowing them.',
 'Owns the knowledge base, retrieval, embeddings, knowledge validation, decay and the auto-learning exam loop.',
 'knowledge_director','Refreshes, re-validates and quarantines knowledge as confidence decays.'),
('intelligence', 9,'Intelligence OS',
 'Tells the company what is actually happening, and what happens next.',
 'Owns analytics, KPI instrumentation, forecasting, market and competitive intelligence, supplier and customer intelligence.',
 'intel_director','Changes what the company measures when the current metrics stop explaining outcomes.'),
('evolution', 10,'Evolution OS',
 'Makes the company better than it was last week, on purpose.',
 'Owns innovation intake, the improvement loop, the outcome ledger, performance optimisation, cost efficiency and organisational design.',
 'cpo','Grades every change against its own claim, promotes what worked, reverses what did not, and proposes structural change.')
on conflict (os_key) do nothing;

-- the 'knowledge' dept_key is a legacy misnomer: it holds ops_director, docs,
-- process_improvement_mgr, project_coordinator and qa_manager - an Operations team with
-- zero knowledge roles. Keep the key (it is referenced widely) and correct the label.
update org_departments set name = 'Operations' where dept_key = 'knowledge';

insert into os_department (os_key, dept_key, note) values
('leadership','exec',null),
('leadership','hr','People, org design and capability sit with Leadership.'),
('commercial','sales',null),
('commercial','marketing',null),
('marketplace','procurement',null),
('marketplace','customer_success',null),
('operations','knowledge','dept_key is a legacy misnomer - this is the Operations team.'),
('technology','it',null),
('finance','finance',null),
('legal_gov','legal',null)
on conflict do nothing;