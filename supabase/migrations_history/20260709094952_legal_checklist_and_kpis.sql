-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709094952   name: legal_checklist_and_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- required legal documents/agreements for a UAE B2B marketplace (the "can't miss any" legal checklist)
create table if not exists public.legal_checklist (
  id bigint generated always as identity primary key,
  requirement text not null unique,
  category text not null,          -- terms, policy, agreement, compliance
  applies_to text,                 -- customer, supplier, both, platform
  priority int not null default 2, -- 1 critical, 2 important, 3 nice-to-have
  match_slug text,                 -- legal_documents slug that satisfies it (if a doc)
  present boolean not null default false,
  notes text
);
revoke all on public.legal_checklist from anon, authenticated;

insert into public.legal_checklist(requirement,category,applies_to,priority,match_slug,notes) values
('Customer Terms & Conditions / User Agreement','terms','customer',1,'terms-of-service','Core marketplace contract with customers (governing law, liability, dispute resolution).'),
('Supplier Agreement / Terms','agreement','supplier',1,'supplier-agreement','Currently held as supplier_terms_html secret; should be a versioned legal_document.'),
('Privacy Policy (UAE PDPL / GDPR)','policy','both',1,'privacy',NULL),
('Cookie Policy','policy','both',2,'cookie-policy',NULL),
('Refund / Cancellation Policy','policy','customer',1,'refund-policy',NULL),
('Data Retention Policy','policy','platform',2,'data-retention-policy',NULL),
('KYC / AML Policy','policy','both',1,'kyc-policy',NULL),
('Anti-Bribery & Corruption Policy','policy','platform',2,'anti-bribery-policy',NULL),
('Acceptable Use Policy','policy','both',2,'acceptable-use',NULL),
('Complaints Handling Policy','policy','both',2,'complaints-policy',NULL),
('Disclaimer / Limitation of Liability','policy','both',2,'disclaimer',NULL),
('Information Security Policy','policy','platform',2,'information-security-policy',NULL),
('Governing Law & Dispute Resolution clause','terms','both',1,NULL,'Should be embedded in the customer T&C and supplier agreement.'),
('Intellectual Property / content-ownership terms','terms','both',2,NULL,NULL),
('NDA / confidentiality template','agreement','supplier',3,NULL,'For anonymous-marketplace confidentiality between parties.'),
('E-commerce / Consumer Protection compliance statement','compliance','platform',2,NULL,'UAE Federal consumer protection & e-commerce law.');

-- mark present where a matching legal_document exists
update legal_checklist lc set present = exists(select 1 from legal_documents d where d.slug = lc.match_slug);

-- log of ad-hoc contract/NDA/agreement reviews (AI-assisted, never legal advice)
create table if not exists public.legal_reviews (
  id bigint generated always as identity primary key,
  doc_kind text,                   -- nda, supplier_agreement, customer_agreement, contract, policy
  title text,
  source text,                     -- upload path / pasted / legal_document slug
  summary text,
  risk_flags jsonb default '[]'::jsonb,
  risk_level text,                 -- low, medium, high
  needs_licensed_review boolean default true,
  reviewed_at timestamptz not null default now(),
  reviewed_by text default 'legal_ai'
);
revoke all on public.legal_reviews from anon, authenticated;

-- consolidated legal KPIs
create or replace view public.legal_kpis as
select
  (select count(*) from legal_documents) as policies_published,
  (select count(*) from legal_documents where updated_at < now()-interval '365 days') as policies_stale,
  (select count(*) from legal_checklist) as required_total,
  (select count(*) from legal_checklist where present) as required_present,
  (select count(*) from legal_checklist where not present) as required_missing,
  (select count(*) from legal_checklist where not present and priority=1) as critical_missing,
  round(100.0*(select count(*) from legal_checklist where present)/nullif((select count(*) from legal_checklist),0),1) as coverage_pct,
  (select count(*) from customers) as customers,
  round(100.0*(select count(*) from customers where tos_accepted_at is not null)/nullif((select count(*) from customers),0),1) as customer_terms_acceptance_pct,
  (select count(*) from leads where approval_status='approved') as suppliers_approved,
  round(100.0*(select count(*) from leads where approval_status='approved' and accepted_terms_at is not null)/nullif((select count(*) from leads where approval_status='approved'),0),1) as supplier_terms_acceptance_pct,
  (select count(*) from agent_actions where kind='legal_flag' and status in ('pending','needs_review')) as open_legal_flags,
  (select count(*) from legal_reviews where risk_level='high' and needs_licensed_review) as high_risk_reviews;

create table if not exists public.legal_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date, kpis jsonb not null, created_at timestamptz not null default now()
);
create unique index if not exists legal_kpi_snap_day on public.legal_kpi_snapshots(snapshot_date);
revoke all on public.legal_kpis, public.legal_kpi_snapshots from anon, authenticated;
