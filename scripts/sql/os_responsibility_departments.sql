-- os_responsibility — which Operating System owns which DEPARTMENT.
--
-- os_responsibility maps 72 responsibilities onto the 10 operating systems, but only three of
-- those responsibilities are department keys: marketing, sales and procurement. Ten of the
-- thirteen active departments were owned by nobody, which is why explain-owning-os reads
-- "0 of 35 surfaced actions show an owning Operating System" — the chain from an acting agent to
-- its OS breaks at the department.
--
-- EVERY ROW BELOW IS READ OUT OF AN OS's OWN MANDATE, not invented. The mandate text that assigns
-- it is quoted in the note column, so anyone can check the assignment against the charter rather
-- than against my judgement.
--
-- THE ONE JUDGEMENT CALL IS hr. No operating system's mandate mentions people, hiring or
-- performance. Evolution's mandate is the only one that names "organisational design", and the
-- spec's own §35 is "Autonomous Hiring & Restructuring" driven by evolution_proposal — so HR sits
-- under Evolution. That is an org-design decision, it is flagged as one in the note, and it is the
-- founder's to overrule.
--
--   node scripts/apply_sql.mjs scripts/sql/os_responsibility_departments.sql
--   node scripts/promote_rows_to_production.mjs os_responsibility responsibility exec customer_success \
--     knowledge it finance legal knowledge_eng intelligence evolution hr
insert into public.os_responsibility (responsibility, os_key, note) values
  ('exec', 'leadership',
   'Leadership OS mandate: "Owns company goals, the priority hierarchy, the constitution, the weekly executive meeting and the daily operating rhythm."'),
  ('customer_success', 'marketplace',
   'Marketplace OS mandate: "Owns supplier acquisition, onboarding, verification, category coverage, inquiry qualification, matching, quotation and award." It already owns the responsibility "customers".'),
  ('knowledge', 'operations',
   'org_departments names dept_key "knowledge" as Operations, charter "Process, quality, project coordination and document control"; Operations OS mandate: "Owns process, SLAs, quality gates, documentation, project coordination and bottleneck removal."'),
  ('it', 'technology',
   'Technology OS mandate: "Owns infrastructure, application, AI runtime, model routing, security and deployment."'),
  ('finance', 'finance',
   'Finance OS mandate: "Owns accounting, VAT and corporate tax, budgeting, treasury, collections, invoicing and financial reporting."'),
  ('legal', 'legal_gov',
   'Legal & Governance OS mandate: "Owns contracts, compliance, PDPL and data protection, regulatory monitoring, risk register and the authority model."'),
  ('knowledge_eng', 'knowledge',
   'Knowledge OS mandate: "Owns the knowledge base, retrieval, embeddings, knowledge validation, decay and the auto-learning exam loop" — the Knowledge Engineering department charter word for word.'),
  ('intelligence', 'intelligence',
   'Intelligence OS mandate: "Owns analytics, KPI instrumentation, forecasting, market and competitive intelligence, supplier and customer intelligence."'),
  ('evolution', 'evolution',
   'Evolution OS mandate: "Owns innovation intake, the improvement loop, the outcome ledger, performance optimisation, cost efficiency and organisational design."'),
  ('hr', 'evolution',
   'JUDGEMENT CALL, not a quote. No OS mandate names people, hiring or performance. Evolution is the only one that names "organisational design", and spec section 35 (Autonomous Hiring & Restructuring) is driven by evolution_proposal. Overrule this row to move HR elsewhere.')
on conflict (responsibility) do update
  set os_key = excluded.os_key, note = excluded.note;
