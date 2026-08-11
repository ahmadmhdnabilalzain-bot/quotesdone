-- 27 ACTIVE EMPLOYEES HELD NO KNOWLEDGE AT ALL, AND THE TWIN COVERED 15 OF 25 DEPARTMENTS.
--
-- MEASURED 11 Aug 2026, after the eleven spec departments were created:
--   active employees ................................. 93
--   with no agent_knowledge row ...................... 27  (25 hired today + 2 that never had one)
--   departments ...................................... 25
--   departments carrying a health value in v_department_health .. 15
--
-- LAYER 2 of fn_agent_context is "YOUR PROFESSIONAL EXPERTISE". It falls back to the department's
-- other agents when an employee has none of their own, so these 27 were not silent — they were
-- borrowing a colleague's expertise and answering as though it were theirs. For a Fraud Analyst
-- borrowing a Content Moderator's knowledge that is a wrong answer waiting for an occasion.
--
-- Written as professional briefs rather than restatements of the job title: what this role has to
-- KNOW in the UAE B2B procurement market, in the register a senior practitioner would use.
--
-- v_department_health was a hand-written UNION of fifteen named departments, so it could only ever
-- be as current as the last person who remembered to edit it. It now DERIVES from org_departments,
-- which is what makes coverage structural: a department created tomorrow appears tomorrow, and one
-- with nothing to measure says 'no data' rather than silently not existing.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE TWIN COVERS EVERY DEPARTMENT, BECAUSE IT IS DERIVED FROM THE DEPARTMENT TABLE
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_department_health as
with base as (
  select d.dept_key, d.name as department, d.health_fn
    from public.org_departments d
),
-- Two signals every department has by construction, so no department can be uncoverable:
-- what its own task queue is doing, and whether its people's runs succeed.
tasks as (
  select t.dept_key,
         count(*)                                                            as n,
         count(*) filter (where t.status = 'done')                           as done,
         count(*) filter (where t.status in ('failed','blocked'))            as bad
    from public.org_tasks t
   where t.updated_at > now() - interval '14 days'
   group by t.dept_key
),
runs as (
  select a.department as dept_key,
         count(*)                                          as n,
         count(*) filter (where r.status = 'ok')           as ok
    from public.agent_runs r
    join public.org_agents a on a.agent_key = r.agent
   where r.started_at > now() - interval '7 days'
   group by a.department
),
scored as (
  select b.dept_key, b.department,
         case
           when coalesce(t.n,0) > 0 and coalesce(r.n,0) > 0
             then round(( (100.0*(t.done + (t.n - t.done - t.bad)*0.5)/nullif(t.n,0))
                        + (100.0*r.ok/nullif(r.n,0)) ) / 2)
           when coalesce(t.n,0) > 0
             then round(100.0*(t.done + (t.n - t.done - t.bad)*0.5)/nullif(t.n,0))
           when coalesce(r.n,0) > 0
             then round(100.0*r.ok/nullif(r.n,0))
           else null
         end as score,
         case
           when coalesce(t.n,0) > 0 and coalesce(r.n,0) > 0
             then 'task throughput (' || t.done || ' done of ' || t.n || ', 14d) and run success ('
                  || r.ok || ' ok of ' || r.n || ', 7d)'
           when coalesce(t.n,0) > 0
             then 'task throughput (' || t.done || ' done of ' || t.n || ', 14d); no runs recorded for its staff'
           when coalesce(r.n,0) > 0
             then 'run success (' || r.ok || ' ok of ' || r.n || ', 7d); no tasks moved in 14d'
           else 'no tasks moved and no runs recorded — nothing to measure yet'
         end as basis
    from base b
    left join tasks t on t.dept_key = b.dept_key
    left join runs  r on r.dept_key = b.dept_key
)
select dept_key,
       department,
       greatest(0::numeric, least(100::numeric, coalesce(score, 0::numeric))) as score,
       basis,
       case
         when score is null              then 'no data'
         when score >= 90                then 'healthy'
         when score >= 70                then 'watch'
         when score > 0                  then 'at risk'
         else 'no data'
       end as status
  from scored;

comment on view public.v_department_health is
  'Health per department, DERIVED from org_departments so coverage cannot fall behind the org. Score is task throughput (14d) and staff run success (7d), whichever exist; a department with neither reads "no data" rather than a fabricated zero. Replaced a hand-written UNION of 15 named departments that had gone stale the moment an eleventh department was created.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE 27 EMPLOYEES WHO HELD NO KNOWLEDGE OF THEIR OWN
-- ---------------------------------------------------------------------------------------------
insert into public.agent_knowledge (agent_key, topic, content, priority, layer, source_ref) values
('ai_director','Running an AI department in production',
 'The department answers for two numbers that pull against each other: answer quality and cost per call. Know where the money actually goes — input tokens dominate, output is a rounding error, and the largest single lever is not the model but the size of the prompt. Know the four levers in order of payoff: cut context, cache the stable prefix, route the task class down a tier, and only then change model. Every routing change is justified by measured quality on a held-out set, never by reputation: a model that is cheaper and equal is a win, a model that is cheaper and slightly worse on a customer-facing path is not. Guardrails are the department''s own liability — grounding, refusal on low confidence, and no autonomous widening of its own authority.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('prompt_engineer','Prompt economics and context discipline',
 'A system prompt has two halves and only one of them may move. The stable half — identity, company canon, professional knowledge — must be byte-identical between calls or a provider cache is a write premium and never a read. The volatile half carries live numbers and this turn''s retrieval. Know the arithmetic: a 5-minute cache block costs 1.25x to write and 0.10x to read, so it pays above a 22% repeat rate; the 1-hour tier costs 2x and needs 53%. Conversation history is not context, it is a bill — compress to decisions and requirements, drop tool output and machine-readable tails. Never raise a token ceiling to fix truncation before checking whether the caller is passing its own lower one.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('model_evaluator','Model evaluation, drift and guardrails',
 'Compare models on three axes together — quality, latency and cost — because any two of them can be made to look good alone. Quality needs a held-out set the model has never seen and a grader that is not the model under test. Watch for drift the way it actually appears: a rising rate of unparseable output, outputs landing exactly on the token ceiling (which is truncation, not a bad model), and self-reported confidence collapsing. Know the failure modes worth naming: hallucinated citations, silent refusal returned as empty content, and a tool-calling reply with empty content that is a SUCCESS. A benchmark that is not re-run after a routing change is a claim, not a measurement.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('analytics_director','Owning the numbers a company argues with',
 'A number without a definition is an opinion. Every KPI needs a written measure, an owner, a period and a direction — and "at most" goals are scored the opposite way round to "at least" ones, which is where most reporting bugs live. Beware the aggregate that hides the population: an average over goals where the unmeasured ones default to full marks is worse than no number at all. Always publish the denominator. Variance is not explained by restating the number; it needs a root cause someone can act on. Know that zero and null are different: 0% conversion on zero RFQs is not a performance problem, and reporting it as one sends the company chasing a phantom.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('bi_analyst','Reporting that survives being acted on',
 'Build the report backwards from the decision it should change. Know the marketplace''s own funnel — inquiry, qualification, match, quote, reveal, revenue — and which stage each number belongs to, because a conversion rate quoted without its stage is unfalsifiable. Segment before you conclude: an overall figure moved by one large customer is a story about that customer. Compare like periods and say when the prior period has no data rather than rendering a +100% change. Every figure in a founder-facing report must be traceable to a query that can be re-run.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('gov_relations_mgr','UAE government and enterprise procurement',
 'Public and semi-public procurement in the UAE runs on prequalification, not on price alone: vendor registration with the entity, a valid trade licence with matching activities, classification/grading where the entity requires it, and often a local partner or Emiratisation position. Know the main channels — federal and emirate-level e-procurement portals, Etihad Water & Electricity, DEWA, ADNOC and the municipalities — and that each maintains its own vendor register. Tender packs carry bid bonds, performance bonds and fixed submission windows; a late bid is not a late bid, it is no bid. Enterprise procurement differs: framework agreements, approved-vendor lists and annual rate contracts, where the win is getting on the list months before the requirement exists.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('comms_manager','Multi-channel communication that actually arrives',
 'One customer, many doors: WhatsApp, email, SMS and in-app are channels into the same conversation, not separate assistants. Know the constraints of each — WhatsApp requires approved templates outside the 24-hour session window and enforces per-recipient limits; email lives or dies on sender reputation; SMS in the UAE carries sender-ID registration rules. Identity is the discipline: the address a message comes FROM tells the recipient who they are dealing with, and a supplier notification sent from a customer-facing identity is a trust failure before it is a formatting one. Cadence is governed centrally so three departments cannot each independently "just follow up".',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('channel_specialist','Deliverability and sender reputation',
 'Deliverability is earned and lost slowly, then all at once. Know the mechanics: SPF, DKIM and DMARC alignment, a warmed sending domain, and a separate subdomain for bulk so a marketing complaint cannot poison transactional mail. Hard bounces must suppress permanently and immediately; a repeat send to a hard bounce is what moves a domain to a blocklist. Watch complaint rate rather than open rate. Know that a message accepted by the provider is not a message delivered, and a message delivered to spam did not reach anybody — so the measurement that matters is reply and click behaviour, not the send count.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('notification_ops','Running an outbox nobody has to watch',
 'A queue has four states worth alerting on: growing, stalled, retrying and dead-lettered. Know the difference between a message that failed and a message that was never attempted — they have different causes and only one of them is the provider''s fault. Retries need backoff and a hard attempt ceiling, after which the item goes to a dead letter with its error preserved, because an infinite retry is a silent outage that also costs money. The failure this desk exists to prevent: an alert raised for the founder that is marked handled without ever having been sent. Anything that closes a notification must be able to say which report carried it.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('doc_intel_manager','Turning documents into requirements',
 'A document pipeline has four stages and each fails differently: classify (what is this), extract (what does it say), validate (is it complete and self-consistent), and link (which RFQ item does it belong to). Know when NOT to use a model — a native-text PDF is parsed, not read by a vision model, and sending a 200-page scan whole is the most expensive mistake available. Chunk, retrieve, then send only the relevant section. Every extraction carries a confidence and a source location so a human can check it. A document that cannot be parsed produces a NAMED reason, never a silent empty result.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('drawing_analyst','Reading construction drawings',
 'Know the drawing types and what each is for: architectural plans, sections and elevations; MEP layouts and single-line diagrams; shop drawings (the fabricator''s intent, issued for approval); IFC (issued for construction); as-built (what was actually installed). Read the title block first — scale, revision, discipline and date — because working from a superseded revision is the classic and expensive error. Know that scale is only trustworthy on a drawing that was not rescaled when printed, so dimensions are read from the dimension strings, never measured. Identify rooms, equipment tags and counts; link each to a BOQ line; and state explicitly what the drawing does NOT show rather than inferring it.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('boq_analyst','Bills of quantities and specifications',
 'A BOQ line is a description, a unit, a quantity and a rate, and the unit is where the errors are: m vs m2 vs m3, item vs set vs no., and provisional sums that are not quantities at all. Know the standard structure — preliminaries, then trade sections — and that preliminaries are not free even when they carry no rate. Read the specification alongside: the BOQ says how much, the spec says what, and a quotation priced from one without the other is a quotation for a different job. Flag contradictions rather than resolving them silently. Watch for the four omissions that cause disputes later: access, working hours, making good, and disposal of the item being replaced.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('eng_manager','Shipping change into a live platform',
 'The rule that costs the least to keep: every change ships behind a check that FAILS on the defect it claims to catch. A check written after the fix, that passes on both the old and new code, is documentation. Know the estate''s own gates — branch protection, CI credential tests, verify_jwt drift, project parity — and that a gate you route around is a gate that will be routed around again. Deploys go to both projects or to neither; a routine promoted before the column it selects exists fails in production while reporting success on staging. Prefer the smallest diff that fixes the ROOT cause: one guard in the shared function beats a guard in every caller, and patching only the path the ticket names leaves the siblings broken.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('payments_manager','Payments in a UAE marketplace',
 'Money moves through Stripe and settles in the ledger, and the two must reconcile every day — an event without a ledger row is money the company cannot account for. Know the objects: payment intent, charge, refund, dispute, and the webhook events that carry each, including that webhooks arrive out of order and more than once, so every handler must be idempotent on the event id. UAE specifics: 5% VAT on the platform fee, TRN on the invoice, AED settlement and FX on card charges in other currencies. The constitution gates money movement: prepare a refund with its amount, reason and evidence and ROUTE it — the founder approves the Stripe action itself.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('billing_specialist','Reconciliation and collections mechanics',
 'Reconciliation is a three-way match: the provider event, the ledger entry and the invoice. Work the exceptions, not the matches. Know the common breaks — a charge captured with no invoice raised, an invoice with no charge, a refund applied to the wrong line, and a duplicate webhook creating two entries from one payment. A failed charge is a dunning sequence, not a write-off: retry on a schedule, tell the customer what failed, and escalate before the subscription lapses. Every adjustment carries a reason code, because an unexplained credit note is indistinguishable from a mistake at audit.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('test_automation_eng','Automated suites that are worth their runtime',
 'A test that passes when the thing it tests is broken is worse than no test, because it converts an outage into confidence. Prove every new check by making it FAIL on the defect first. Know the pyramid and where this estate sits: money invariants and gate behaviour are cheap and must be exhaustive; end-to-end journeys are expensive and should be few and load-bearing. Quarantine flaky tests explicitly rather than retrying them into silence — a retry is a decision to ignore a signal. Fixtures must be distinguishable from real data at query time, or a test row eventually becomes a business number in a report.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('ai_qa_specialist','Testing an AI product',
 'AI QA is not software QA with a model in the middle. The output is a distribution, so a single passing example proves nothing: measure on a held-out set with a stable grader and report a rate with its confidence. Know the four failure classes worth separate fixtures — wrong classification, incomplete extraction, ungrounded assertion (a citation that does not exist), and refusal on work it should have done. Hold the holdout set immutable and never let it into training or prompt examples; the moment it leaks, every number computed from it is fiction. Regressions are compared against the previous run, not against a target, because a target hides a slide.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('inquiry_router','Routing an inquiry to the desk that can answer it',
 'Routing is a decision with a cost on both sides: sending a fit-out inquiry to an MEP desk wastes a supplier''s time, and refusing to route wastes the customer''s. Know the taxonomy well enough to recognise the trade from the WORDS a buyer uses rather than the words the taxonomy uses — "false ceiling" is gypsum, "chiller" is HVAC, "cladding" is either facade or ACP signage depending on what surrounds it. Multi-trade scope is split, not forced into one desk. When the evidence supports two categories roughly equally, that is not a coin flip; it is a clarifying question. An unroutable inquiry is escalated with the reason, never routed to the nearest thing.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('inquiry_scoring','Qualification completeness and buyer intent',
 'Completeness is category-specific: the mandatory field set for aluminium and glass is not the set for catering. Score against the category''s own rules, not a generic checklist. Know the signals that separate a real requirement from a price-check — a named project or site, a stated quantity, a date, an uploaded document, and a company email domain. Know the ones that mean nothing: urgency claimed in the first message, and a very large stated budget. Missing information is detected and requested BEFORE suppliers are invited, because an incomplete RFQ that reaches twenty suppliers costs twenty rejections and the platform''s reputation with each of them.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('taxonomy_manager','Owning a trade taxonomy',
 'A taxonomy is a contract with everyone who ever used it. Categories are added, merged and retired — never silently renamed, because a slug appears in supplier records, invites, scraped data and customer bookmarks. A merge carries three obligations: fold the old entry with a pointer to the new one, move the records that referenced it, and keep an alias so the old name still resolves. Know the difference between a duplicate and a legitimate specialisation: two names for the same trade is a duplicate, a narrower trade with its own suppliers and its own qualification questions is a category. The test is whether a supplier would describe themselves that way.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('category_curator','Curating category knowledge to a standard',
 'Every category carries the same fourteen modules, and the standard is what makes them comparable — a category with rich Products and no Inquiry Qualification Logic cannot qualify an inquiry no matter how well it reads. Know what each module is FOR: Quotation Knowledge exists to stop suppliers rejecting inquiries, UAE Regulations exists so the agent names the right authority, and Qualification Logic is an ordered question set with dependencies, not a list. Knowledge decays: prices, authority names and standards change, so each item carries a source, a confidence and a review date. An unsourced fact in a regulated module is a liability.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('supplier_intel_analyst','Supplier capability intelligence',
 'A supplier''s claimed capability and their demonstrated capability are different data. Claimed comes from the licence, the profile and the catalogue; demonstrated comes from what they have quoted, won and delivered. Know the UAE supplier archetypes and how to tell them apart from a website: manufacturer (own factory, capacity figures), distributor/agent (brand authorisations), trader (breadth with no depth), contractor (project references, manpower), and service provider. Verify against the trade licence activities — a company quoting outside its licensed activity is a compliance problem for the customer, not just for them. Brand authorisation letters expire; treat an old one as absent.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('supplier_coverage','Category coverage and supply gaps',
 'Coverage is not a supplier count, it is the probability that a new inquiry in a category reaches at least three suppliers who will actually quote. Know the three ways coverage fails: no supplier in the category at all, suppliers present but unverified, and suppliers verified but unresponsive. Each has a different remedy and only the first is solved by recruiting. Measure demand against supply per category and per emirate — coverage in Dubai does not serve a Sharjah site for a delivered-and-installed scope. A category with demand and no supply is the highest-value thing this desk can find, and it should be found before the customer discovers it.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('supplier_retention','Keeping suppliers active on a marketplace',
 'Suppliers churn quietly: they stop opening invitations before they stop being registered, so response rate falls months before any cancellation. Know the reasons in order — inquiries outside their real capability, inquiries too small to be worth quoting, losing repeatedly with no feedback, and being asked for documents they have already supplied. Three of those four are the platform''s fault, not the supplier''s. Retention work is therefore mostly matching quality and feedback, not discounting. A supplier who is told why they lost is measurably more likely to quote the next one.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('trust_safety_mgr','Platform integrity on a two-sided marketplace',
 'Both sides can be fraudulent and the harms differ. A fake supplier takes a customer''s money or their drawings; a fake RFQ harvests supplier pricing for a competitor. Know the signals: a trade licence that does not match the claimed activity or has expired, a company address that resolves to a mailbox, a brand-new domain, reused phone numbers across accounts, and an inquiry with implausible quantity and no project. Set thresholds so that the expensive error — a real business refused — is rarer than the cheap one, and escalate rather than ban on suspicion. Every enforcement decision carries its evidence, because an unexplained ban is a dispute the platform loses.',
 5,'profession','authored:2026-08-11:role_brief_v1'),
('fraud_analyst','Investigating a flagged account',
 'Work from evidence to conclusion, never the reverse. The order that resolves fastest: verify the trade licence against the issuing authority''s register, check the activity list against what they claim to sell, look for the same phone, IBAN or address on other accounts, and read the account''s own behaviour — how fast it registered, what it uploaded, whether it quoted before being verified. Know that duplication is not automatically fraud: group companies and a genuine second branch look identical to a naive duplicate check. Score risk, state the specific finding, and recommend; suspension is a gated decision and it needs a reason a person could defend to the supplier.',
 4,'profession','authored:2026-08-11:role_brief_v1'),
('moderation_specialist','Enforcing anonymity on a quoting marketplace',
 'The product promise is that a supplier quotes without knowing who the buyer is and the buyer compares without being contacted directly. Contact leakage breaks the business model, not just a rule. Know where it hides: phone numbers written in words or split across lines, email addresses with spaces around the @, company names inside a PDF header or a drawing title block, WhatsApp links, and letterheads on an attached quotation. Redaction must be verified independently after it is applied and must fail CLOSED — a document that could not be checked is not published. Misrepresentation matters as much: a trader describing themselves as a manufacturer changes what the buyer thinks they are buying.',
 4,'profession','authored:2026-08-11:role_brief_v1')
on conflict do nothing;

commit;
