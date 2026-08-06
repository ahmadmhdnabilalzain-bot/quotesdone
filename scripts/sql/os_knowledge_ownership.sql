-- os-exclusive-ownership — "No duplicated ownership" (blueprint §15), and the coverage half of it.
--
-- MEASURED BEFORE WRITING: 107 distinct knowledge domains. 2 owned by TWO OSes, 47 owned by NONE.
-- Founder decision of 6 Aug 2026: the mapping below, proposed and approved.
--
-- The 31 unowned `cat:*` rows are resolved by RULE, not by a hand-written list. marketplace already
-- owns 52 of the 83 supplier categories and the blueprint gives it Customers, Suppliers, RFQs,
-- Matching, Quotes, Procurement and Supplier Performance — so a supplier category with no owner
-- belongs to marketplace by construction. A hand-typed list of 31 slugs would be a second
-- vocabulary for a fact the data already carries, and this codebase has six of those already.
insert into public.os_knowledge_domain (os_key, domain_key, ownership)
select 'marketplace', d.domain_key, 'owns'
  from (select distinct domain_key from public.os_knowledge_domain) d
 where d.domain_key like 'cat:%'
   and not exists (select 1 from public.os_knowledge_domain o
                    where o.domain_key = d.domain_key and o.ownership = 'owns')
on conflict (os_key, domain_key) do update set ownership = 'owns';

-- The 16 functional domains ARE named individually, because each is a judgement about which OS owns
-- a body of knowledge and no rule derives them. Every target is the OS the blueprint's own
-- "Owns" list assigns it to:
--   finance        -> Accounting, Treasury, Budgets, Payments, Revenue, Forecasting
--   legal_gov      -> Contracts, Compliance, UAE Regulations, Policies, Risk, Auditing
--   technology     -> Infrastructure, AI, Platform, Security, APIs, DevOps, Reliability
--   commercial     -> Marketing, Sales, Business Development, Partnerships, Brand, Revenue Growth
--   operations     -> Daily Operations, Workflows, Quality, SLAs, Automation, Service Delivery
--   marketplace    -> Suppliers
--   leadership     -> Vision, Mission, Strategy, Company Goals, Priorities, Governance
-- hr goes to leadership rather than a People OS because this blueprint has no People OS and
-- leadership owns Governance and Resource Allocation; that is the founder's call, recorded here so
-- the next reader sees a decision rather than an accident.
insert into public.os_knowledge_domain (os_key, domain_key, ownership)
values
  ('finance',    'finance',              'owns'),
  ('legal_gov',  'legal_uae',            'owns'),
  ('legal_gov',  'pdpl',                 'owns'),
  ('legal_gov',  'uae_tax',              'owns'),
  ('legal_gov',  'uae_authorities',      'owns'),
  ('technology', 'engineering',          'owns'),
  ('technology', 'ai_engineering',       'owns'),
  ('commercial', 'customer_success',     'owns'),
  ('commercial', 'communication',        'owns'),
  ('operations', 'operations',           'owns'),
  ('marketplace','supplier_mgmt',        'owns'),
  ('leadership', 'company',              'owns'),
  ('leadership', 'constitution',         'owns'),
  ('leadership', 'priority_hierarchy',   'owns'),
  ('leadership', 'universal_objectives', 'owns'),
  ('leadership', 'hr',                   'owns')
on conflict (os_key, domain_key) do update set ownership = 'owns';

-- THE TWO DOUBLE-OWNED DOMAINS. Both are supplier categories, so both resolve to marketplace and
-- the SECOND owner is demoted to 'queries' rather than removed — the querying OS still needs the
-- knowledge, it simply does not own it, which is exactly the distinction §6 of the blueprint draws
-- ("Leadership OS should not duplicate this knowledge; it queries Finance OS when needed").
-- Deleting the row would have destroyed the access, not the duplication.
update public.os_knowledge_domain set ownership = 'queries'
 where ownership = 'owns'
   and domain_key = 'cat:bearings-and-power-transmission-suppliers' and os_key = 'leadership';
update public.os_knowledge_domain set ownership = 'queries'
 where ownership = 'owns'
   and domain_key = 'cat:elv-and-security-systems-suppliers' and os_key = 'technology';

-- os-operations: the spec lists 'automation' among Operations OS's responsibilities and NO OS owned
-- it. os_responsibility's primary key is the responsibility itself, so this cannot create a
-- duplicate — if another OS already claimed it the insert is a no-op and the gap was misdiagnosed.
insert into public.os_responsibility (os_key, responsibility)
values ('operations', 'automation')
on conflict (responsibility) do nothing;

-- comp-06-knowledge-independent: three OSes had ZERO knowledge domains of their own. An OS with no
-- domain cannot be queried by another, which makes §6's whole "queries the owning OS" contract
-- unbuildable for them.
-- Each domain below is taken verbatim from that OS's "Owns" list in the blueprint, so the knowledge
-- boundary and the responsibility boundary are the same boundary rather than two drifting ones.
insert into public.os_knowledge_domain (os_key, domain_key, ownership)
values
  ('knowledge', 'kb_corpus',            'owns'),
  ('knowledge', 'rag_retrieval',        'owns'),
  ('knowledge', 'sop_library',          'owns'),
  ('knowledge', 'company_memory',       'owns'),
  ('knowledge', 'knowledge_validation', 'owns'),
  -- evolution was the last OS owning NOTHING. Innovation, AI Optimization, Organizational Design,
  -- Performance Improvement, Cost Optimization, Process Re-engineering — its six, from the file.
  ('evolution', 'innovation',              'owns'),
  ('evolution', 'ai_optimization',         'owns'),
  ('evolution', 'organizational_design',   'owns'),
  ('evolution', 'performance_improvement', 'owns'),
  ('evolution', 'cost_optimization',       'owns'),
  ('evolution', 'process_reengineering',   'owns'),
  -- operations and intelligence each owned a single domain, which is a boundary too thin for
  -- another OS to query meaningfully. Both lists are the blueprint's.
  ('operations', 'daily_operations',    'owns'),
  ('operations', 'workflows',           'owns'),
  ('operations', 'quality',             'owns'),
  ('operations', 'slas',                'owns'),
  ('operations', 'service_delivery',    'owns'),
  ('intelligence', 'dashboards',              'owns'),
  ('intelligence', 'analytics',               'owns'),
  ('intelligence', 'forecasting',             'owns'),
  ('intelligence', 'competitive_intelligence','owns'),
  ('intelligence', 'market_intelligence',     'owns'),
  ('intelligence', 'customer_intelligence',   'owns'),
  ('intelligence', 'supplier_intelligence',   'owns')
on conflict (os_key, domain_key) do update set ownership = 'owns';
