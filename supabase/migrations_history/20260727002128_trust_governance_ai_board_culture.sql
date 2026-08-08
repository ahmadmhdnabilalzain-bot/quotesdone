-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727002128   name: trust_governance_ai_board_culture
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ 13. TRUST & GOVERNANCE ============
create table if not exists public.governance_policy (
  id            bigserial primary key,
  domain        text not null check (domain in ('ethics','privacy','audit','retention','approval','security','compliance')),
  policy        text not null,
  rule          text not null,
  enforced_by   text,
  enforcement   text not null default 'declared' check (enforcement in ('code','database','process','declared')),
  owner_dept    text,
  created_at    timestamptz not null default now(),
  unique (domain, policy)
);

insert into public.governance_policy (domain, policy, rule, enforced_by, enforcement, owner_dept) values
('ethics','No fabricated facts','An employee may not assert a price, regulation, brand fact or supplier capability it cannot cite. Where knowledge is absent it says so and routes to research.','company_constitution art.3; knowledge_exam','process','knowledge'),
('ethics','No overselling','No employee may promise an outcome the marketplace cannot deliver - delivery dates, supplier availability or savings that are not evidenced.','company_constitution art.4','declared','exec'),
('ethics','Never blame the customer','Failures are the company''s to explain and fix. Customer-blaming language is a review-chain rejection reason.','review_rule','database','customer_success'),
('privacy','Anonymity is the product','Supplier identity is not disclosed before a paid reveal. Any content path that could leak a supplier name, phone, email, domain or licence number pre-reveal is a P0 defect.','qa_suite leak probes','code','it'),
('privacy','Minimum data','Buyer contact data is collected only where a workflow needs it, and is never sent to a model prompt when a reference id would do.','review','process','legal'),
('privacy','No personal data in URLs','Identifiers in query strings are treated as public. Tokens are single-use and short-lived.','code review','code','it'),
('audit','Every significant action is logged','Any action that spends money, contacts a third party, changes supplier or buyer state, or publishes content writes an audit row with actor, target and reason.','os_audit_log, agent_action_log, decision_log, company_event','database','it'),
('audit','Decisions carry evidence','No decision reaches approved status without business, financial, legal and customer impact plus at least one evidence reference.','trg_decision_gate','database','exec'),
('retention','Documents','Trade licences, IBAN documents and signed terms are retained for the life of the supplier relationship plus 5 years - UAE commercial record-keeping expectation.','process','declared','legal'),
('retention','Model logs','ai_cost_log and decision_log are retained 24 months; prompts containing buyer content are not retained beyond 90 days.','process','declared','it'),
('approval','Spend thresholds','Under AED 1,000 a department head decides alone. AED 1,000-10,000 needs Chief of Staff. Above AED 10,000 needs the founder. No employee may split a spend to stay under a threshold.','employee_authority','database','finance'),
('approval','Irreversible actions','Publishing externally, contacting a supplier for the first time, refunding, banning, and any schema change are irreversible-class and require a second employee in the review chain.','review_chain','database','exec'),
('security','Least privilege','SECURITY DEFINER functions have execute revoked from anon, authenticated and public unless a named workflow requires otherwise.','pg catalog audit','database','it'),
('security','Secrets never in code','Credentials live in the secrets store; no key is written to a table, a log line or a prompt.','code review','code','it'),
('compliance','UAE supplier verification','A supplier may not receive an RFQ until trade licence number, licensing authority and expiry are recorded and the licence is unexpired.','leads.verified + approval_status','database','supplier_success'),
('compliance','VAT','Reveal fees are UAE VAT-relevant. Invoices carry a TRN and sequential invoice number.','reveal_invoices','database','finance')
on conflict (domain, policy) do update set rule=excluded.rule, enforced_by=excluded.enforced_by,
  enforcement=excluded.enforcement, owner_dept=excluded.owner_dept;

-- ============ 4. AI GOVERNANCE BOARD ============
create table if not exists public.ai_model_register (
  id             bigserial primary key,
  model          text not null unique,
  provider       text not null,
  approved       boolean not null default false,
  approved_for   text[],
  forbidden_for  text[],
  approved_by    text,
  approved_at    timestamptz,
  review_due     date,
  note           text
);

insert into public.ai_model_register (model, provider, approved, approved_for, forbidden_for, approved_by, approved_at, review_due, note) values
('anthropic/claude-fable-5','openrouter', true, array['classification','extraction','routing','summarisation'], array['pricing decisions','legal text','supplier approval'], 'ai_governance_board', now(), (now()+interval '90 days')::date, 'Small tier. Cheapest approved model; default for high-volume mechanical work.'),
('anthropic/claude-sonnet-5','openrouter', true, array['drafting','knowledge authoring','quote extraction','matching explanation'], array['irreversible financial actions without review'], 'ai_governance_board', now(), (now()+interval '90 days')::date, 'Medium tier. The workhorse.'),
('anthropic/claude-opus-4.8','openrouter', true, array['strategy','ambiguous judgement','escalated disputes'], array['batch jobs','anything schedulable hourly'], 'ai_governance_board', now(), (now()+interval '90 days')::date, 'Large tier. Requires a task_class that justifies it in model_policy.')
on conflict (model) do update set approved=excluded.approved, approved_for=excluded.approved_for,
  forbidden_for=excluded.forbidden_for, review_due=excluded.review_due, note=excluded.note;

create table if not exists public.ai_governance_review (
  id           bigserial primary key,
  review_type  text not null check (review_type in ('safety','ethics','prompt_standard','model_approval','quality','hallucination','cost','version')),
  subject      text not null,
  finding      text not null,
  evidence     text,
  severity     text not null default 'info' check (severity in ('info','low','medium','high','critical')),
  action       text,
  status       text not null default 'open' check (status in ('open','actioned','accepted_risk','closed')),
  reviewed_by  text not null default 'ai_governance_board',
  created_at   timestamptz not null default now()
);

insert into public.ai_governance_review (review_type, subject, finding, evidence, severity, action, status) values
('hallucination','UAE regulator names','Models assert obsolete UAE authority names from training data. Medical/pharma moved from MOHAP to the Emirates Drug Establishment under Federal Decree-Law 38/2024 and models still name MOHAP.','Observed across category knowledge generation runs','high','Every knowledge module that names an authority must carry a verified URL; knowledge_exam checks a sample.','actioned'),
('prompt_standard','Prompt injection via supplier content','Supplier-submitted text (profiles, quotes, documents) reaches model prompts. A regression was observed where instruction-like content in a document changed downstream behaviour.','security_incident; qa_suite injection probe','critical','Treat all supplier and buyer content as data, never instruction. Wrap in explicit untrusted boundaries and re-assert the task after the untrusted block.','open'),
('cost','Web plugin billing','The OpenRouter web plugin is billed per search and was enabled on research paths that did not need live web access.','_shared/llm.ts plugins config','medium','Web plugin is opt-in per call, never a default. Assistant-side research must not use the founder OpenRouter key at all.','actioned'),
('model_approval','Model register','Only three models are approved. Any other model reaching production is an unreviewed dependency.','ai_model_register','medium','fn_select_model returns only registered, approved models.','actioned'),
('quality','Self-reported success','Agents reported successful writes that had not landed. Structured self-verification was added to every generation prompt.','category knowledge workflows','high','Every writer verifies its own row count from the database before reporting success.','actioned'),
('safety','Irreversible actions by autonomous employees','Employees with authority to contact suppliers, refund, ban or publish can act without a second pair of eyes unless the review chain is enforced.','employee_authority, review_chain','high','Irreversible-class actions require review_chain approval before the executor runs.','open');

-- ============ 15. COMPANY CULTURE ENGINE ============
create table if not exists public.culture_principle (
  id          bigserial primary key,
  principle   text not null unique,
  meaning     text not null,
  looks_like  text not null,
  violation   text not null,
  detectable_by text,
  created_at  timestamptz not null default now()
);

insert into public.culture_principle (principle, meaning, looks_like, violation, detectable_by) values
('Always helpful','Every interaction leaves the person better informed than it found them, even when the answer is no.','Explaining why a category has no suppliers yet and what happens next.','Dead-ending a buyer with "not available".','review_rule'),
('Always honest','State what is known, what is assumed and what is unknown. Uncertainty is disclosed, not smoothed over.','"Three suppliers quoted; two have not verified their licence yet."','Presenting an estimate as a quote.','review_rule'),
('Never oversell','No promise the marketplace cannot keep - no guaranteed savings, no guaranteed timelines, no invented supplier depth.','"Cheapest available today" only when it is measured.','Superlatives without evidence.','review_rule: superlative without figure'),
('Always explain','Every recommendation carries its reasoning and its trade-off.','"This one is 12% cheaper but its lead time is 3 weeks longer."','A ranked list with no reasons.','decision_record.recommendation'),
('Never fabricate','No invented prices, regulations, brands, certificates or supplier capabilities. Absent knowledge is stated as absent.','"I do not have verified 2026 pricing for this - routing to research."','A confident number with no source.','knowledge_exam; evidence required'),
('Never blame the customer','Failures are ours to explain and fix.','"We did not collect enough detail up front - here is what we need."','"You did not provide the drawings."','review_rule'),
('Protect anonymity','Supplier identity is the thing buyers pay for. It is never given away early, never leaked in a draft, never implied.','Anonymised quotes that survive a leak probe.','Naming or hinting at a supplier pre-reveal.','qa_suite leak probes'),
('Deterministic before clever','If code can decide it correctly, code decides it. A model is for judgement, not arithmetic.','Threshold rules, SQL and lookups instead of a prompt.','An LLM call to compare two numbers.','ai_cost_log.could_be_cheaper')
on conflict (principle) do update set meaning=excluded.meaning, looks_like=excluded.looks_like,
  violation=excluded.violation, detectable_by=excluded.detectable_by;

alter table public.governance_policy enable row level security;
alter table public.ai_model_register enable row level security;
alter table public.ai_governance_review enable row level security;
alter table public.culture_principle enable row level security;
