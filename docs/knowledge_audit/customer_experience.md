# Knowledge audit — Customer Experience department (5 active agents)

Measured 6 Sep 2026, 02:03–02:30 UTC, read-only against production `htdblwldjkcgjvmqkbeh`. Every number below came
back from a query in that window; nothing was written and no paid model was called. Scope: `org_agents.active = true and
department = 'customer_experience'` — `followup` (Customer Success Director), `cs_support`, `cs_onboarding`,
`cs_retention`, `channel_specialist`. Founder's bar: knowledge equal to top senior staff in the role, enough to run 90%
of the time without the internet, and the reasoning (rules, thresholds, worked examples) to match.

## 0. What could and could not be measured

Same instruments as `docs/knowledge_audit/growth.md` §0 (tables, functions, and the two context routines that are
STABLE). Additionally read for this department: `company_faq`, `response_template`, `templates`, `wa_messages`
(count/dates/columns), `email_suppressions` (count), `phase_b_sla_policy` (all 34), `decision_policy` refund keys,
`org_onboarding`, the `comms` pack (`ops_knowledge.dept_key = 'comms'`, the role family `channel_specialist` is mapped
to), and the full text of two `customer_experience` playbooks. Not measurable: the FAQ answer rate — no log exists
(`kb_usage_log` has 0 FAQ rows) and `fn_faq_answer` is VOLATILE (it increments `response_template.used_count`), so it
was not run; the only trace is `used_count` (greeting 3, thanks 3, all other 11 intents 0). No table named for NPS,
CSAT, complaints, tickets, journeys or churn exists (`information_schema` search on those substrings returned none) — so
"CSAT above 95%" and "Customer SLA met 95%" in the director's responsibilities have no instrument this audit could find;
that is a bounded statement about table names, not about every view or function. "verify" marks a standard stated from
domain knowledge, not confirmed against a primary source in this session.

## 1. Findings that apply to all five agents

**C1 — The employee context delivers zero professional expertise.** `fn_agent_context(agent, 22000)` returns
27,085–27,215 chars per CX agent; `# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` is 40 chars (heading only) for all five. Same
mechanism as growth G1: the admission test `length(out)+length(piece) <= own_cap + 2200` (= 8,200) runs after ≈13k
chars of identity, genome, risk register and employee block have been emitted, so no profession row is ever admitted.
`followup` holds 9 profession rows (the richest in the company scope audited) — "Complaint handling & de-escalation
playbook", "Compensation & goodwill envelope", "Escalation severity matrix", "CSAT & voice-of-customer program", "Refund
dispute mediation flow", "Professional standard (customer success / RevOps)", "Verified references & key standards",
"Deepened professional playbook", "Role & expertise" — none of them reaches it.

**C2 — The task-time context drops the rules a support case needs.** `fn_agent_context_v3` for `cs_support` handling "the
revealed supplier did not respond, refund the 3% fee" returns 69 ids; `deterministic_rules` = 60 (100k chars) emitted as
alphabetical titles under a 2,000-char cap → 12 survive: `Authority: money movement is refunds AND credits…`, `Refunds and
any money movement always route to the human founder`, `The escalation matrix…`, then `Accessibility`, `Arabic Customer
Support`, `Comparison-Report Explanation`, `Complaint Resolution`, `Customer Communication`, `Customer Lifecycle`, `Customer
Onboarding`, `Customer Profiles`, `Customer Satisfaction` ("— controls and boundaries"). Of 15 task-relevant titles, 3
survive. Dropped: `Refund Policy — controls and boundaries`, `Reveal Support —`, `Sla And Response Targets —`, `Policy: the
reveal-fee refund policy boundary and how to communicate it`, `Data privacy and confidentiality in support (UAE PDPL
awareness)`, `Complaint categorization taxonomy…`, `Designing SLAs for a fully-automated support function`, `Playbook:
the buyer disputes the reveal charge itself`, `Decision: goodwill gesture vs refund vs nothing — and who decides which`,
`Playbook: duplicate or accidental reveal`, `Playbook: the buyer who wants to bypass the platform after revealing`,
`Playbook: the supplier who complains buyers ghost after revealing`. Identical survivor list for `followup` and
`channel_specialist` (the order is alphabetical, not by task). `role_knowledge` = the same 3–4 V2 pack docs at 1,800
chars each (`01_ROLE_EXPERTISE_V2.md`, `role_charter.md`, `senior_judgment.md` + one role yaml); `cs_onboarding` and
`cs_retention` both map to `Customer Success Operations Specialist`; `followup` maps to `Customer Success Reviewer /
Auditor`. `validated_experience` = 0 for all five. `field_corpus` (12 chunks) is Victorian Ombudsman complaint
guidelines, Saylor *Principles of Marketing*, one company chunk ("Reveal fee is 3% of accepted quotation value, unca…").

**C3 — `dept_library` has 0 rows for `customer_experience`, `customer_success` or `comms`** (36 rows, all `company`).

**C4 — The situational playbooks exist and are good; the numbers and the law do not.** `ops_knowledge dept_key =
'customer_experience'`: 95 records, all jurisdiction AE / freshness current, all runtime-eligible and embedded — 38
decision_playbook, 14 reference, 14 kpi, 13 failure_mode, 8 policy, 5 remediation, 3 authority. 49 playbook/policy/
authority titles cover the real situations: "I paid to reveal but the supplier never responded", chargeback arrives as a
fact, abusive customers, de-escalation, delivering the founder's refund decision, duplicate reveal, legal/regulatory
threat (gated), negative reviews in the UAE market, dispute mediation, Ramadan/holidays/prayer times, suspected fake RFQ,
bypass after reveal, win-back, PDPL awareness (gated), deletion requests (gated), "What a complete refund case for the
founder must contain", escalation matrix. Read in full, "Playbook: onboarding a first-time buyer for a satisfiable first
reveal" is senior-quality prose with a "[window]" placeholder where the number should be. Across the 95: content with a
number+unit 4, if/then arms 14, worked examples 0, `structured_data` 3 (the three lane-determination records). The
`customer_success` V2/V3 pack: 271 records (35 `review_required`), 20 knowledge domains incl. "Arabic Customer Support",
"Refund Policy", "Sla And Response Targets", "Privacy Requests", "Otp And Account Verification", SOPs 01–09 (Customer
Registration, Terms Acceptance Evidence, Inquiry Support, Comparison-Report Delivery, Reveal Support, Supplier
Non-Response Complaint, Refund Case Coordination, Customer Feedback And Retention, Pdpl Request Intake); numbers in
content 0/271. Term hits across the three CX dept keys: escalat 317 · complaint 176 · refund 172 · PDPL 110 · onboarding
62 · SLA 55 · WhatsApp 39 · non-response 36 · bounce 35 · suppression 27 · churn 25 · reveal fee 20 · Arabic 17 · tone 9 ·
CSAT 5 · sender reputation 5 · apology 3 · NPS 2 · opt-out 2 · template approval 2 · **0** for 24-hour, consumer
protection, Federal Law No. 15, Ministry of Economy, TDRA, DMARC, SPF, anti-circumvention, AED 15.

**C5 — The reference corpus is generic.** `kb_chunks category_norm = 'customer_success'`: 10,954 chunks, newest 31 Aug;
top sources Saylor *Principles of Marketing* (744), ITIL 4 Foundation (384), *Customer Centric Strategy* (349 ×2), arXiv
LLM/dialogue surveys (275, 191, 153, 142, 137, 135), People in Need journey-mapping guide (228), UNDP Ombudsman
complaint guide (193), SERVQUAL. UAE-cited: 3 citations / 27 chunks (0.25%). Term hits: churn 807 · complaint 581 ·
retention 427 · first response 215 · NPS 127 · template 98 · CSAT 90 · escalation 82 · Arabic 34 · refund 23 · SLA 21 ·
consumer protection 19 · UAE 9 · WhatsApp 8 · 24-hour window 4 · Federal Law No. 15 2 · PDPL 1 · Ministry of Economy 0.
`regulatory` (476, newest 10 Jul): consumer protection 25, TDRA 19, PDPL 15. `_global` (592): refund 38, PDPL 24,
WhatsApp 16.

**C6 — Company rules that DO reach every CX agent (Layer 1, 9.3–10.6k chars):** pricing & fees live (3%), "Company FAQ
(canonical answers)" (truncated), RFQ completeness rule, brand wording, constitution art. 6 "Customer promises" and art.
13 "Communication standards" via the genome. `company_faq`: 484 approved, 100% embedded, last update 18 Jul — public
151 (105 all + 25 customer + 21 supplier), internal 304; the refund FAQ says: revealed supplier silent 3 working days
and unreachable → reveal fee refunded, supplier fined the same amount "except where such a charge is not permitted under
UAE law", other requests reviewed within the 3-working-day window. FAQ hits: reveal 67 (34 public), 3% 47 (20), refund 12
(7), non-response 12 (5), PDPL 10 (3), WhatsApp 3 (1), complaint 1 (0 public), SLA 2 (0 public), Arabic 0, consumer
protection 0. `decision_policy`: `refund_notify_after_working_days` 1, `refund_call_after_working_days` 3,
`refund_claim_after_call_working_days` 3, `refund_reveal_fee_pct` 3, `refund_late_fee_annual_pct` 9,
`refund_admin_fee_aed` 250 (its own description carries a WARNING that no admin fee appears in the customer terms),
`founder_review_gates` = refunds only, `legal_triggers` = contract change, liability, indemnity, termination, dispute,
refund dispute, regulatory complaint, data subject request, subpoena, chargeback. `phase_b_sla_policy`: 34 SLAs, every
one classified "Internal target; not a public promise" — SLA-ACK-INSTANT 1 min, SLA-INQUIRY-FIRST-RESPONSE 5 min,
SLA-CUSTOMER-ONBOARD 30 min, SLA-CUSTOMER-INPUT 24 h, SLA-NOTIFICATION 5 min, SLA-QUOTE-WINDOW 48 h,
SLA-REFUND-TRIAGE 4 business hours, SLA-IDENTITY-VERIFY 5 min. No customer-facing complaint acknowledge/resolve SLA
exists. `response_template`: 13 intents (greeting, thanks, anonymity, apology, complaint, pricing, payment, delivery,
shipping, location, opening_hours, appointment, follow_up), channel `any`, 0 Arabic, used 6 times. `wa_messages`: 12
rows, 28 Jul–12 Aug 2026 (columns `lang`, `escalated`, `reply`). `email_suppressions`: 37.

**C7 — Three contradictions a senior person would have to resolve by hand today.** (a) `cs_support`'s profession row
(undelivered) says "do not quote an AED 250 admin fee to customers"; `decision_policy.refund_admin_fee_aed` = 250 with a
WARNING; the public FAQ mentions no fee. (b) `employee_authority` grants `followup` `refund_within_window` at tier
`autonomous`, 10,000 AED, while `org_role.customer_success_director.forbidden_decisions` includes "issuing a refund" and
`founder_review_gates` routes every refund to the founder. (c) `employee_authority` gives `cs_support`, `cs_onboarding`
and `cs_retention` a `refund_within_window` action class (advisory, 0 AED) whose window the FAQ defines as 3 working
days while `decision_policy` defines a 1 + 3 + 3 working-day notify/call/claim ladder.

**C8 — Curriculum bindings.** Each CX agent has 11 `employee_knowledge` rows: layer 1 `customer_success` expert, layer 2
five company domains, layer 4 `operations`, `procurement`, `sales_crm` at awareness, layer 5 `quotesdone_os`, layer 8
`communication`. **No `pdpl` and no `legal_uae` binding at any depth** (growth agents at least have both at awareness).
Layers 3, 6, 7, 9–12 unbound. `org_onboarding`: only `followup` has a row (`onboarding`); the other four have none, so
every context says "Employment status: onboarding" and none is certified.

**C9 — Exams and retrieval.** Latest exam (5 Sep, 5 questions): `cs_onboarding` 3 correct/2 partial (conf 0.71),
`cs_retention` 3/2 (0.70), `cs_support` 3/2 (0.72), `followup` 2 correct/3 partial (0.60), `channel_specialist` 0
correct / 4 wrong / 1 not covered (0.15). All-time: `channel_specialist` 3 of 26 correct, 12 wrong, 9 not covered — its
questions were medical-device procurement (MOHAP registration, CE certificate, ISO 13485, customs duty) and
category-pack files (`quote_comparison_contract.yaml`, `06_RESEARCH_AND_ESCALATION_POLICY.yaml`); the exam is invalid
for the role, not evidence about deliverability. The other four: 5–6 of 20 correct on "What does the company's operating
knowledge say about: <record>" questions. Gap-fill wrote `experience` rows such as `exam:1029
06_CATEGORY_REMEDIATION_AND_CERTIFICATION_V3.yaml` (cs_onboarding), `exam:790 02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml`
(cs_retention), `exam:827 01_SPECIALIST_EXPERTISE_V2.md` = "Waterproofing Suppliers — Category Specialist Expertise V2"
(followup) — these are what Layer 4 "what this organisation has learned" now shows the agents. `kb_usage_log` 30 d:
`followup` 55, `cs_support` 54 (all automatic assembly), the other three 0. Runs 7 d: `followup` 2 ok / 2 error ("The
model returned nothing… Prompt was 39,378 characters") / 6 skipped ("Inference is held (paidProviderGate / kernel
K12)"); `cs_retention` 3 ok, `channel_specialist` 3 ok, `cs_support` 2 ok, `cs_onboarding` 1 ok — every ok note is an
`org_task` lane determination from the `customer.registered` / `payment.received` / `KPI missed` playbook (cosine
0.88–0.92). `review_chain`: `followup` authored 135 approve / 35 owned / 45 null, reviewed 20 approve; specialists 6–15
approve each; 0 rejects, 0 holds by these agents (dept has 2 `hold` rows, author not in scope). `artifact_review`: 0.

**Arabic: 0 of 484 FAQ, 0 of 13 templates, 0 of 874 in-scope ops records, 1 of 108 agent_knowledge rows** — the
department charter promises support "across every channel including WhatsApp" in a market where the customer-facing
language is often Arabic.

Depth key: **expert** = sets the standard, decides edge cases unaided; **working** = executes against a written rule;
**aware** = knows it exists and when to hand off. **P1** blocks a correct decision today; **P2** senior quality; **P3**
completeness.

---

## 2. `followup` — Customer Success Director

**What it does today.** `org_role.customer_success_director`: scheduled_manager, execute_medium, budget 10,000 AED; owns
"customer journey and SLA definitions", "escalation path for a customer issue", "retention offers within policy", "which
lifecycle messages exist"; forbidden: issuing a refund, changing price, overriding a marketplace decision on quote
quality, approving its own department's output. Authority role for `customer_escalation` kind. Measured on "Customer
SLA met 95% weekly", "CSAT above 95%". Runs 7 d: 2 ok / 2 error / 6 skipped; 30 d: 24 runs, 15 ok, 3 error. Exam: 2/5
correct, 3 partial; all-time 5/20. Retrievals 30 d: 55 (automatic). Reviews: 135 approve / 35 owned / 45 null authored;
20 approve as reviewer; 0 reject/hold. `agent_knowledge`: 16 rows — 9 profession (all `unvalidated`) + 7 exam-derived;
avg 1,170 chars; 6 with rule arms, 0 with numbers, 0 examples. Standing deputy: `cs_onboarding`. The only agent in scope
with an `org_onboarding` row (`onboarding`).

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge (profession) | 9 rows: complaint & de-escalation, goodwill envelope, severity matrix, CSAT/VoC program, refund mediation, standards refs | undelivered (C1); unvalidated |
| ops_knowledge customer_experience | 95: 38 playbooks, 14 kpi ("KPI: SLA attainment, and reading it by owner not in aggregate", "KPI: complaint volume and rate…", "KPI: escalation rate…"), 8 policy, 3 authority | 4 records with numbers, 0 examples |
| ops_knowledge customer_success pack | 271; "Sla And Response Targets — operating knowledge", "Refund Policy —", "Escalation Procedures —", SOP 06/07/08/09 | 35 review_required |
| phase_b_sla_policy | 34 internal targets | none customer-facing |
| decision_policy | refund ladder 1/3/3 working days, admin fee 250 (WARNING), legal_triggers | live |
| company_faq | 484; refund FAQ; complaint 1 (internal) | |
| kb_chunks customer_success | ITIL 4, UNDP/Victorian Ombudsman complaint guides, SERVQUAL, journey mapping | no UAE law |
| fn_agent_context | 27,085 chars; Layer 2 = 40; Layer 4 = waterproofing category pack, "Monthly operating and financial review — duplicate event", "revealed supplier's contact details are wrong or dead" | |
| fn_agent_context_v3 | 70 ids; 12/60 rules; task-relevant 3/10; role = `Customer Success Reviewer / Auditor` | wrong archetype for a director |

**Senior-staff standard (Customer Success Director, UAE B2B marketplace)**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE consumer-protection frame: Federal Law No. 15/2020 + Cabinet Res. 66/2023 (Ministry of Economy; DET/DED consumer depts), what applies to a B2B buyer vs a consumer, complaint escalation routes outside the company — **verify** scope | expert |
| 2 | Complaint-handling standard: ISO 10002:2018 principles, severity matrix with SLA per severity, root-cause taxonomy, closure criteria, public-promise vs internal-target SLAs | expert |
| 3 | SLA design for a fully automated function: first response, resolution, escalation clocks, UAE working days (Mon–Fri), Ramadan hours, holidays; weekly attainment measurement by owner | expert |
| 4 | CSAT / NPS / CES program: instrument, timing (rating at the reveal moment — founder rule), sampling, B2B benchmarks, closed-loop follow-up | expert |
| 5 | Refund & goodwill regime end to end: 3-working-day non-response rule, 1/3/3 ladder, supplier charge, chargebacks as facts, founder-only decision, what a complete case contains, goodwill vs refund vs nothing, admin-fee status | expert |
| 6 | Escalation architecture: matrix (agent decides / director / founder / legal / security), legal_triggers, evidence pack | expert |
| 7 | Buyer and supplier journey maps with the lifecycle messages at each step (owned decision "which lifecycle messages exist") | expert |
| 8 | PDPL (FDL 45/2021) for support: DSAR handling & timelines (**verify**), deletion vs retention, breach notification path, confidentiality between anonymous parties | expert |
| 9 | WhatsApp Business Platform policy: 24-hour window, template categories & approval, opt-in, quality rating — as they constrain the journey | working |
| 10 | Churn & health signals with thresholds; win-back and retention-offer bounds | working |
| 11 | Arabic/English service standards: tone ladder, register, when Arabic-first | working |
| 12 | Anti-circumvention & dispute mediation (AED 15k / 3× rule, bypass patterns) | working |
| 13 | Anonymity/identity rules (BR-011) and OTP/verification support | working |
| 14 | VAT/invoice questions on the reveal fee (FTA tax-invoice basics) | aware |
| 15 | Supplier-side support: onboarding/verification, non-response consequences, suspension recommendation | working |
| 16 | Service-management frameworks (ITIL 4, COPC) as reference | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Consumer-law frame | expert | **missing** — consumer protection 0 / Federal Law 15 0 / Ministry of Economy 0 in ops; 19 generic kb hits; "Playbook: escalating a legal, regulatory, or consumer-protection threat" exists (gated) but names no law | Digest of FL 15/2020 + Cabinet Res. 66/2023 (scope, complaint rights, refund/return provisions, Arabic information duty), B2B applicability note, authority contact routes → `kb_chunks` regulatory (source_kind `regulation`, dated) + `ops_knowledge` customer_experience `policy` deterministic with "escalate to legal if" arms | 4 × 3k | P1 |
| 2 Complaint standard | expert | **partial** — profession rows "Complaint handling & de-escalation playbook", "Escalation severity matrix" (undelivered, unvalidated); "Complaint categorization taxonomy…" (dropped by cap); no complaint table; 0 numbers | Severity matrix as `structured_data` (S1–S4: definition, ack SLA, resolve SLA, owner, founder-gate flag) + closure criteria + ISO 10002 principles summary → `ops_knowledge` customer_experience `decision_playbook` deterministic; validate the two profession rows | 1 × 3k + JSON | P1 |
| 3 SLA design | expert | **partial** — 34 internal SLAs; "Designing SLAs for a fully-automated support function" (dropped); "KPI: SLA attainment…" (no numbers) | Customer-facing SLA set (EN/AR wording, working-day rules, Ramadan variant) + measurement spec per SLA (source event, clock start/stop) → `phase_b_sla_policy` rows classified public + `kpi` `structured_data` | 1 × 2.5k | P1 |
| 4 CSAT/NPS/CES | expert | **missing instrument** — no table by name; profession row "CSAT & voice-of-customer program" undelivered; CSAT 5 / NPS 2 ops hits; rating-at-reveal rule only in charter | Program spec: question set EN/AR, trigger (reveal moment), sampling, benchmark ranges, closed-loop rule; the instrument itself is an engineering item → `ops_knowledge` customer_experience `kpi` + `operational_template` | 1 × 2.5k | P1 |
| 5 Refund regime | expert | **partial with contradictions** (C7) — FAQ, decision_policy, SOP 06/07, "What a complete refund case…", "Decision: goodwill gesture vs refund vs nothing" (dropped), profession "Refund dispute mediation flow" (undelivered) | One reconciled deterministic record "Refund and goodwill rules" (3-day non-response, 1/3/3 ladder, supplier charge, chargeback-as-fact, founder-only, admin fee: state the truth once) + fix `employee_authority` row for `refund_within_window` → `ops_knowledge` customer_experience `authority` deterministic `structured_data` | 1 × 3k | P1 |
| 6 Escalation architecture | expert | **present** — "The escalation matrix…" (gated, survives cap), legal_triggers live, profession "Escalation severity matrix" | thresholds as `structured_data`; validate row | 500 | P2 |
| 7 Journey maps | expert | **partial** — charter; playbooks per moment; SOPs 01–09; no single map; lifecycle messages listed nowhere measured (`notifications` table exists, not audited) | Buyer & supplier journey map: stage → event → message (channel, template key, EN/AR) → owner → SLA → `ops_knowledge` customer_experience `reference` `structured_data` | 2 × 3k | P2 |
| 8 PDPL for support | expert | **partial** — "Data privacy and confidentiality in support (UAE PDPL awareness)" (gated, dropped), "Policy: balancing data retention against deletion requests", SOP 09 Pdpl Request Intake; DSAR timeline not stated; no `pdpl` curriculum binding | DSAR/deletion procedure with timelines (**verify**), breach path, anonymity-preserving disclosure rules → `policy` deterministic; bind `pdpl` + `legal_uae` in `employee_knowledge` | 1 × 2.5k | P2 |
| 9 WhatsApp policy | working | **missing** — 24-hour 0 (cx), template approval 2; WhatsApp 39 generic hits; `wa_messages` 12 | WhatsApp Business Platform digest (window, template categories/approval, opt-in, quality rating/limits, UAE numbers) dated → `kb_chunks` `_global` + `ops_knowledge` comms `policy` deterministic (shared with channel_specialist) | 1 × 3k | P1 |
| 10 Churn signals | working | **partial** — "Failure mode: the silent churn signal after a disappointing reveal", "Playbook: win-back for lapsed buyers", "Repeat usage —"; 0 thresholds | see cs_retention row 1 | — | P2 |
| 11 Arabic/English standards | working | **missing** — "Arabic Customer Support — operating knowledge" is English prose; 0 Arabic anywhere; "Reference: the tone escalation ladder" exists (EN) | bilingual tone ladder + register guide + Arabic variants of the 13 templates → `response_template` + `agent_knowledge` profession validated | 1 × 3k + 13 templates | P2 |
| 12 Anti-circumvention | working | **partial** — "Playbook: the buyer who wants to bypass the platform after revealing" (dropped); AED 15 / anti-circumvention 0 hits | add the T&C rule text and detection cues → `structured_data` on that playbook | 500 | P2 |
| 13 Anonymity/OTP | working | **present** — BR-011, FAQ, "Otp And Account Verification —" | — | — | P3 |
| 14 VAT/invoice | aware | **present** — FAQ VAT 28 hits | — | — | P3 |
| 15 Supplier-side support | working | **present** — "helping a supplier with onboarding and verification", "recommending a supplier suspension", "setting supplier response-window expectations from real data" | document list UAE (**verify**) | 800 | P3 |
| 16 Frameworks | aware | **present** — ITIL 4 384 chunks | — | — | P3 |

**Reasoning check.** If/then arms exist in 14 of 95 dept records and 6 of 16 own rows; thresholds: 4 records with a number;
worked examples: 0. The director's KPIs (95% SLA, 95% CSAT) have no instrument and its refund authority row contradicts
its role. P1 = 6.

---

## 3. `cs_support` — Customer Support Specialist

**What it does today.** `org_role.customer_support`: event_driven_operator, execute_low, budget 0; owns "answering a
customer question from validated knowledge", "raising an internal handoff"; forbidden: legal or regulatory conclusions,
refunds, exposing another party's identity. `employee_authority`: nudge / refund_within_window / resolve_within_policy
advisory (0 AED). Runs 7 d: 2 ok (lane routing). Exam 3/5 correct, 2 partial; all-time 6/20. Retrievals 30 d: 54
(automatic). Reviews 15 approve / 5 owned / 5 null. `agent_knowledge` 9 rows; the profession row "Support on a pre-reveal
anonymous marketplace" (read in full) is exactly right — the three top tickets, the 3-working-day rule, "refunded and a
non-response charge equal to that fee billed to the supplier", "do not invent goodwill credits", "never state a
commission" — and is `unvalidated` and undelivered (C1). 0 self-directed retrievals. "Answering from validated knowledge"
is the owned decision, and `validated_experience` is empty for it.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 9 rows (1 profession, 8 exam-derived incl. `quote_comparison_contract.yaml` ×2), 4 with rule arms, 0 numbers, 0 examples | undelivered |
| ops_knowledge customer_experience | playbooks for every common ticket (C4), "Reference: the tone escalation ladder — warmth scales…" | most dropped by cap (C2) |
| company_faq | 484 (151 public); customer section 25; refund FAQ | reaches via Layer 1 (truncated) |
| response_template | 13 intents, EN only, 6 uses | |
| decision_policy | legal_triggers (→ Legal), refund ladder | live |
| kb_chunks customer_success | complaint 581, apology 51, tone 62 (generic) | |
| fn_agent_context | 27,151 chars; Layer 2 = 40; Layer 4 = `01_EXPERT_QUALIFICATION_STRATEGY_V3.md` (swimming pools), "Failure mode: the green board over a real failure", "tone escalation ladder" | 1 of 3 relevant |
| fn_agent_context_v3 | 69 ids; 12/60 rules; task-relevant 3/15 (C2) | |

**Senior-staff standard (Support Specialist, UAE B2B marketplace)**

| # | Domain | Depth |
|---|---|---|
| 1 | The refund / non-response rule and the reveal promise, word-perfect, with the three ticket archetypes | expert |
| 2 | Anonymity & identity rules (pre-reveal, BR-011), OTP/verification support | expert |
| 3 | Complaint handling & de-escalation: tone ladder, apology standards, clarifying before acting, abusive-customer boundaries | expert |
| 4 | Escalation criteria: legal_triggers, severity matrix, when a question is a legal/regulatory conclusion (forbidden) | expert |
| 5 | WhatsApp customer-service mechanics: 24-hour window, template use outside it, opt-in, language tag | expert |
| 6 | Bilingual service: Arabic register, honorifics, RTL, the 13 intents in Arabic | expert |
| 7 | UAE consumer-protection awareness: what a buyer may cite, when to hand to Legal (never conclude) | working |
| 8 | PDPL in conversation: what may be disclosed to whom, DSAR intake | working |
| 9 | RFQ completeness & inquiry status semantics (rfq_ready, routed, dispatched, quoted, revealed) | expert |
| 10 | Payments: Stripe flows, VAT tax-invoice questions, chargeback as a fact | working |
| 11 | Supplier-side tickets: non-response consequences, verification, suspension path | working |
| 12 | UAE operating calendar (Mon–Fri, Ramadan, holidays) for promise-setting | working |
| 13 | Fraud/fake RFQ recognition | working |
| 14 | Anti-circumvention cues | working |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Refund/non-response rule | expert | **present but unreachable and contradicted** — profession row (undelivered), FAQ (Layer 1), `Refund Policy — controls` dropped by cap; admin-fee contradiction (C7) | Validate the profession row; deliver the reconciled refund record (followup row 5) with 5 worked ticket examples (EN/AR reply text) → `agent_knowledge` profession `validated` + `ops_knowledge` customer_experience `operational_template` | 1 × 3k | P1 |
| 2 Anonymity/OTP | expert | **present** — BR-011, FAQ anonym 41 hits, "Otp And Account Verification" | — | — | P3 |
| 3 Complaint & de-escalation | expert | **present** — "de-escalating the angry buyer", "boundaries with abusive…", "clarifying a vague complaint", tone ladder | worked examples ×5 → `operational_template`; fix delivery (C2) | 1 × 2k | P2 |
| 4 Escalation criteria | expert | **present** — matrix (survives cap), legal_triggers | — | — | P3 |
| 5 WhatsApp mechanics | expert | **missing** — 24-hour 0 hits in CX ops; 8 generic kb hits | shared WhatsApp policy digest (followup row 9) + 6 conversation examples inside/outside the window → `policy` deterministic + `operational_template` | 1 × 3k | P1 |
| 6 Bilingual service | expert | **missing** — 0 Arabic; templates EN only, 6 uses | Arabic variants of 13 templates + tone/register guide + 10 EN/AR reply pairs → `response_template` (channel `whatsapp`/`email`, lang `ar`) + `agent_knowledge` profession validated | 13 templates + 1 × 3k | P1 |
| 7 Consumer-law awareness | working | **missing** — 0 hits; legal_triggers cover the hand-off | 1-page awareness digest with "hand to Legal when the customer cites…" → `policy` (shared with followup row 1) | 1 × 1.5k | P1 |
| 8 PDPL in conversation | working | **partial** — PDPL awareness record (dropped), SOP 09 | disclosure matrix (who may see what) → `structured_data` | 800 | P2 |
| 9 Inquiry status semantics | expert | **partial** — RFQ completeness rule in Layer 1; profession row names `rfq_ready`; no status dictionary measured | status → meaning → customer wording table → `live_data_binding` | 1 × 1.5k | P2 |
| 10 Payments/VAT | working | **present** — FAQ Stripe 20, VAT 28, payment 23; "chargeback… arrives as a fact" | — | — | P3 |
| 11 Supplier tickets | working | **present** (C4) | — | — | P3 |
| 12 Calendar | working | **present** — Ramadan/holidays playbook | — | — | P3 |
| 13 Fraud/fake RFQ | working | **present** — playbook | — | — | P3 |
| 14 Anti-circumvention | working | **partial** — bypass playbook, no rule text | shared (followup row 12) | — | P2 |

**Reasoning check.** The agent's job is "answer from validated knowledge" and it has 0 validated rows; the rules it needs
are stored and dropped (C2); 0 worked examples of a reply. P1 = 4.

---

## 4. `cs_onboarding` — Customer Onboarding Specialist

**What it does today.** `org_role.customer_onboarding`: event_driven_operator, execute_low; owns "onboarding sequence for
a customer", "first-inquiry guidance"; forbidden: promising quotation outcomes, exposing supplier identity before reveal.
`employee_authority`: advisory ×3. Standing deputy for the director. Runs 7 d: 1 ok. Exam 3/5 correct, 2 partial; all-time
6/20 with 8 partial. Retrievals 30 d: 0. Reviews 6/2/2. `agent_knowledge` 7 rows (1 profession "Customer onboarding on an
anonymous marketplace"), 3 with rule arms, 1 with a number, 0 validated. Live: `SLA-CUSTOMER-ONBOARD` 30 min,
`SLA-IDENTITY-VERIFY` 5 min, `SLA-INQUIRY-FIRST-RESPONSE` 5 min (internal).

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 7 rows | undelivered |
| ops_knowledge | "Playbook: onboarding a first-time buyer for a satisfiable first reveal" (read: excellent, "[window]" placeholder), "Playbook: helping a buyer who can't articulate their RFQ", "buyer confusion before the reveal", "helping a supplier with onboarding and verification", SOP 01 Customer Registration, SOP 02 Terms Acceptance Evidence, SOP 03 Inquiry Support, "Customer Onboarding — operating knowledge"; growth: "Buyer onboarding: engineer the path to first reveal", "Reducing RFQ-form friction…" | onboarding 62 hits |
| Layer 1 | RFQ completeness rule; pricing; FAQ "What happens after I submit an inquiry?", "Can I upload drawings?" | reaches |
| phase_b_business_rule | BR-025 exact terms acceptance, BR-026 no certificate before acceptance | |
| kb_chunks customer_success | onboarding 42 (generic) | |
| fn_agent_context | 27,164 chars; Layer 2 = 40; Layer 4 = "KPI: complaint volume…", `06_CATEGORY_REMEDIATION_AND_CERTIFICATION_V3.yaml`, `06_RESEARCH_AND_ESCALATION_POLICY.yaml` | 0 of 3 onboarding |
| fn_agent_context_v3 | 69 ids; role = `Customer Success Operations Specialist`; 3 role docs | |

**Senior-staff standard (Onboarding Specialist, buyers and suppliers, UAE)**

| # | Domain | Depth |
|---|---|---|
| 1 | Buyer onboarding journey: register → verify (OTP, email unique) → terms (exact version/hash) → first RFQ → dispatch → quotes → reveal; the message at each step, EN/AR | expert |
| 2 | First-RFQ quality: completeness criteria, category mapping, BoQ/drawing expectations, minimum-sufficient-question rule, thresholds and worked examples per common category | expert |
| 3 | Expectation-setting facts: quote window (48 h default), typical time-to-first-quote, how many suppliers are contacted (fan-out 5 / 3 per trade), reveal promise, refund rule | expert |
| 4 | Supplier onboarding & verification: UAE documents (trade licence — mainland DET/DED or free zone, VAT TRN, signatory Emirates ID, category evidence — **verify** the list the platform requires), capability capture, first-quote-during-onboarding | expert |
| 5 | UAE buyer personas and their first-RFQ patterns (contractor vs FM vs SME vs corporate procurement) | working |
| 6 | PDPL at registration: consent capture, purpose text, marketing opt-in separate from service messages | working |
| 7 | Anonymity rules and what may be shown pre-reveal | expert |
| 8 | Onboarding SLAs and Mon–Fri/Ramadan clocks | working |
| 9 | WhatsApp/email onboarding sequence mechanics (templates, opt-in, 24-hour window) | working |
| 10 | Duplicate/identity edge cases (phone may confirm, never select; email is the identity) | working |
| 11 | Sensitive categories (fire, security, electrical, structural, gas, lifts, medical) needing extra qualification | working |
| 12 | Arabic-first onboarding copy | working |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Buyer journey | expert | **partial** — SOP 01/02/03, playbooks, BR-025/026; no single map; messages not enumerated | journey map (followup row 7) | — | P2 |
| 2 First-RFQ quality | expert | **partial** — RFQ completeness rule (Layer 1), "helping a buyer who can't articulate their RFQ"; `qualification_playbooks` table exists (category questions, not audited); 0 worked examples; `decision_policy.match_relevance_floor` 35 | Completeness scorecard (fields, weights, pass threshold) + 6 worked examples (good/bad RFQ per top category) EN/AR → `ops_knowledge` customer_experience `decision_playbook` deterministic `structured_data` + `agent_knowledge` profession validated | 1 × 3k + 6 × 600 | P1 |
| 3 Expectation facts | expert | **partial** — quote window 48 h, fan-out 5/3 live in `decision_policy`/SLA; "[window]" placeholder in the playbook; "setting supplier response-window expectations from real data" | fill the placeholders from live values via `live_data_binding` (never hard-code); one "what to tell a first-time buyer" template EN/AR → `operational_template` | 1 × 1.5k | P2 |
| 4 Supplier verification | expert | **partial** — playbook exists; UAE document list not in any store measured (trade licence/TRN 0 hits not probed — **verify**) | Supplier verification standard: documents, validity checks, free-zone vs mainland, red flags → `ops_knowledge` customer_experience `standard_operating_procedure` deterministic | 1 × 2.5k | P1 |
| 5 Personas | working | **missing** (growth persona pack) | shared | — | P2 |
| 6 PDPL at registration | working | **partial** — SOP 01/02, "Terms Acceptance —"; consent wording not measured | consent text EN/AR + purpose statements → `operational_template` | 800 | P2 |
| 7 Anonymity | expert | **present** | — | — | P3 |
| 8 SLAs/clocks | working | **present** — SLA rows + Ramadan playbook | — | — | P3 |
| 9 Sequence mechanics | working | **partial** — growth "Lifecycle email…" playbook; WhatsApp policy missing | shared WhatsApp digest | — | P2 |
| 10 Identity edge cases | working | **partial** — FAQ "When is my identity revealed?"; phone/email rule lives in engineering memory, not in a knowledge record | 1 record → `policy` | 500 | P2 |
| 11 Sensitive categories | working | **present as live data** — `decision_policy.sensitive_categories` | 1 line in playbook | 200 | P3 |
| 12 Arabic copy | working | **missing** | shared bilingual set | — | P2 |

**Reasoning check.** 3 rule arms in own rows; the decisive threshold (what makes a first RFQ "well-formed") is a prose
rule with no scorecard; 0 worked examples. P1 = 2.

---

## 5. `cs_retention` — Customer Retention Specialist

**What it does today.** `org_role.customer_retention`: event_driven_operator, execute_low; owns "retention outreach within
policy", "rating solicitation timing"; forbidden: discounting outside policy, contacting a customer who has opted out.
Runs 7 d: 3 ok (all `customer.registered` lane determinations — a registration event routed to retention). Exam 3/5,
2 partial; all-time 6/20, 7 wrong. Retrievals 30 d: 0. Reviews 15/5/5. `agent_knowledge` 9 rows (1 profession "Retention
and win-back for repeat B2B buyers"); 5 with rule arms, 2 with examples, 1 with a number — the most rule-shaped rows in
the department; 0 validated.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 9 rows | undelivered |
| ops_knowledge | "Playbook: win-back for lapsed buyers", "proactive post-reveal check-in", "post-resolution follow-up", "harvesting advocacy…", "encouraging more RFQs and reveals within honest bounds", "Failure mode: the silent churn signal…", "Retention —", "Repeat Usage —", SOP 08 Customer Feedback And Retention; growth: "Repeat-RFQ is the real business" (gated), "Cross-category expansion…", "Referral loops…" | churn 25 hits; 0 thresholds |
| authority | growth "Authority: discounts, subsidies, and free reveals are bounded and logged" (gated; not in the CX rule list) | |
| phase_b_business_rule | BR-034 consent/suppression/frequency | |
| kb_chunks customer_success | churn 807, retention 427, NPS 127 (generic, incl. arXiv churn-prediction papers) | |
| fn_agent_context | 27,154 chars; Layer 2 = 40; Layer 4 = `02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml`, "Memoranda Of Understanding — how the department uses it", "Remediation: correcting course after miscategorizing a wave of tickets" | 0 of 3 retention |
| fn_agent_context_v3 | 70 ids; role `Customer Success Operations Specialist` | |

**Senior-staff standard (Retention Specialist, B2B marketplace)**

| # | Domain | Depth |
|---|---|---|
| 1 | Churn & health signals with thresholds: days since last RFQ by segment, reveal without outcome, unopened/bounced lifecycle messages, complaint, low rating; scoring and trigger rules | expert |
| 2 | Rating/CSAT/NPS solicitation: timing (at reveal — founder rule), channel, frequency cap, EN/AR wording, what to do with each score band | expert |
| 3 | Retention-offer policy bounds: what may be offered (reveal credits? none?), by whom, logging; discount forbidden outside policy | expert |
| 4 | Consent & suppression for outreach: PDPL opt-out, BR-034 frequency/suppression, WhatsApp opt-in and window, email suppression list semantics | expert |
| 5 | Win-back and cross-category expansion playbooks with worked sequences | expert |
| 6 | Buyer personas and repeat-RFQ cadence per segment (FM monthly AMCs vs contractor project-based) | working |
| 7 | Referral mechanics (K-factor, reward on value event) | working |
| 8 | Supplier retention (lapsing suppliers — charter: "keeps lapsing suppliers engaged") | working |
| 9 | UAE calendar effects on activity (Ramadan/summer lulls are not churn) | working |
| 10 | Arabic/English outreach copy | working |
| 11 | Measurement: repeat-RFQ rate, 90-day retention, reveal-to-repeat | working |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Churn thresholds | expert | **partial** — signals described in prose (silent churn failure mode, profession row); 0 numeric thresholds in dept (numbers 4/95, none retention) | Health-score spec: signals, weights, thresholds by segment, trigger → action table → `ops_knowledge` customer_experience `kpi` deterministic `structured_data` | 1 × 2.5k | P1 |
| 2 Rating solicitation | expert | **partial** — owned decision; charter "asks for a rating at exactly the moment a quote is revealed"; no instrument, no wording, no score-band actions | rating program spec (followup row 4) + score-band playbook → `decision_playbook` `structured_data` | shared + 1 × 1k | P1 |
| 3 Offer bounds | expert | **partial** — growth authority record (gated, dropped; not scoped to CX); forbidden decision text only | threshold table (what/who/log/gate) scoped `dept_key='customer_experience'` `authority` deterministic | 1 × 800 | P2 |
| 4 Consent & suppression | expert | **partial** — BR-034; `email_suppressions` 37 live; opt-out 2 ops hits; WhatsApp window missing | consent/suppression rule sheet (PDPL opt-out, frequency caps, WhatsApp opt-in/window) → `policy` deterministic (shared with channel_specialist) | 1 × 2k | P2 |
| 5 Win-back/expansion | expert | **present** — playbooks; 2 examples in own rows | 3 worked sequences EN/AR → `operational_template` | 3 × 700 | P2 |
| 6 Personas/cadence | working | **missing** | shared persona pack with repeat cadence | — | P2 |
| 7 Referral | working | **present** (growth) | — | — | P3 |
| 8 Supplier retention | working | **partial** — charter names it; "supplier tiering", non-response playbooks; strike limit 3 live | supplier lapse signals & re-engagement steps → `decision_playbook` | 1 × 1.5k | P2 |
| 9 Calendar effects | working | **present** — Ramadan/holidays playbook (dropped) | one line in health-score spec | — | P3 |
| 10 Arabic copy | working | **missing** | shared bilingual set | — | P2 |
| 11 Measurement | working | **partial** — "Repeat usage —", growth kpi prose | metric definitions with formulas → `kpi` `structured_data` | 800 | P2 |

**Reasoning check.** The best rule density in the department (5 of 9 rows have arms) but no threshold anywhere; the
event that wakes it (`customer.registered`) is an onboarding event. P1 = 2.

---

## 6. `channel_specialist` — Lifecycle Channel Operations Specialist

**What it does today.** `org_role.lifecycle_channel_operations`: event_driven_operator, execute_low, budget null; owns
"outbox handling retries and dead letters", "suppression and opt-out enforcement", "sender reputation actions"; forbidden:
writing message content, sending to a suppressed or opted-out recipient. `employee_authority`: one row, `analysis`
supervised, seeded 14 Aug "an active role with no authority record is undefined, not restricted" — so none of its three
owned actions has an authority class. Runs 7 d: 3 ok (lane determinations of `KPI missed` and `payment.received`). Exam:
0/5 correct (4 wrong, 1 not covered, confidence 0.15); all-time 3/26 — but the questions were medical-device
procurement and category-pack files (C9): invalid for the role. Retrievals 30 d: 0. Reviews 15/4/5. `agent_knowledge` 6
rows (1 profession "Deliverability and sender reputation"; 1 rule arm; 0 numbers). Mapped by v3 to the `comms` pack role
`Notification & Communications Operations Specialist`. Live: `email_suppressions` 37, `notifications` table, `wa_messages`
12, `phase_c_event_outbox`, Postiz ids in `social_posts`.

**Knowledge inventory**

| Source | Count / freshness | Note |
|---|---|---|
| agent_knowledge | 6 rows | undelivered |
| ops_knowledge comms pack | 132 records (98 stable / 34 review_required): 66 yaml, 28 failure_mode_case, 24 md, 8 metric_definition; `01_ADVANCED_PROFESSIONAL_CURRICULUM.md` 40,850 chars; role docs ×4 roles; 106/132 `structured_data`, 26 with numbers in JSON, 0 numbers in content, 8 if/then | generic notification-ops curriculum |
| ops_knowledge customer_experience | bounce 35, suppression 27, sender reputation 5, opt-out 2, template approval 2 hits; "Customer Success exception 03 — Email delivery failure", "04 — WhatsApp or SMS outage" | |
| phase_b_business_rule | BR-034 consent/suppression/frequency/sender policy, BR-045 retry is a new attempt, BR-017 notification count = successful assignments, SLA-NOTIFICATION 5 min | present |
| kb_chunks | WhatsApp 8 (cs), 16 (_global); DMARC/SPF not probed in kb (0 in ops) | |
| fn_agent_context | 27,215 chars; Layer 2 = 40; Layer 4 = `quote_comparison_contract.yaml`, "silent churn signal", "Communication craft: substance over templates" | 0 of 3 channel-ops |
| fn_agent_context_v3 | 71 ids; 12/60 rules (the CX list — none about deliverability); dept docs `04_DEPARTMENT_CERTIFICATION_BLUEPRINT_V3.yaml` | |

**Senior-staff standard (Lifecycle Channel / Deliverability Operations, UAE)**

| # | Domain | Depth |
|---|---|---|
| 1 | Email deliverability: SPF/DKIM/DMARC alignment, Gmail & Yahoo bulk-sender rules (one-click unsubscribe, spam-rate < 0.3%, authenticated domain), warm-up, reputation signals, feedback loops, bounce classes (hard/soft/block) and the suppression rule for each | expert |
| 2 | WhatsApp Business Platform operations: template categories (marketing/utility/authentication) and approval workflow, rejection reasons, 24-hour window, quality rating tiers and messaging limits, opt-in evidence, per-conversation pricing, template pausing | expert |
| 3 | UAE messaging law & regulator rules: PDPL opt-out, Cybercrime Law unsolicited e-marketing, TDRA anti-spam policy, SMS sender-ID registration and content rules, telemarketing hours (Cabinet Res. 56/2024) — **verify** each | expert |
| 4 | Suppression & consent mechanics: suppression list semantics (`email_suppressions`), opt-out propagation across channels, frequency caps per recipient (BR-034), do-not-contact after strike limit | expert |
| 5 | Outbox / retry / dead-letter operations: retry classes, backoff, BR-045 new-attempt rule, dead-letter triage, digest, alerting; the actual tables (`notifications`, `phase_c_event_outbox`) | expert |
| 6 | Channel SLAs and measurement: SLA-NOTIFICATION 5 min, delivery/open/bounce/complaint rates, sender-reputation dashboard | expert |
| 7 | Postiz / social publishing mechanics, permalink and media checks (`social_posts` columns) | working |
| 8 | Incident playbooks: provider outage (email, WhatsApp/SMS), reputation hit, template rejection wave | working |
| 9 | Language tagging and Arabic template variants (template approval per language) | working |
| 10 | Security basics for senders (domain spoofing, phishing look-alikes, secrets in templates) | working |
| 11 | UAE calendar quiet hours and prayer/holiday timing for sends | working |
| 12 | Content boundary: it may not write content — knows who does (marketing_content / cs_support) | aware |

**Gap table**

| Domain | Depth | Today (evidence) | What to ingest → route | Size | Pri |
|---|---|---|---|---|---|
| 1 Email deliverability | expert | **missing** — DMARC 0, SPF 0, sender reputation 5 (prose), bounce 35 (mostly exception/failure prose); profession row undelivered | Deliverability standard: auth records, bulk-sender rules (dated), bounce taxonomy → suppression action table, warm-up schedule, reputation thresholds → `ops_knowledge` comms `standard_operating_procedure` deterministic `structured_data` + `kb_chunks` `_global` (source_kind `standard`, Google/Yahoo sender guidelines, dated) | 2 × 3k | P1 |
| 2 WhatsApp platform ops | expert | **missing** — template approval 2, 24-hour 0; `wa_messages` 12 | WhatsApp Business Platform ops digest (templates, approval, rejection reasons, window, quality tiers, opt-in evidence, pricing) dated → `kb_chunks` `_global` + `ops_knowledge` comms `policy` deterministic (shared with cs_support/followup) | 1 × 3.5k | P1 |
| 3 UAE messaging law | expert | **missing** — TDRA 0, cybercrime 0, telemarketing 0; PDPL 110 generic | regulation digest with "may send / may not send / hours / sender-ID" arms (**verify**) → `kb_chunks` regulatory + `policy` deterministic | 3 × 2k | P1 |
| 4 Suppression/consent | expert | **partial** — BR-034 (one sentence), `email_suppressions` 37, opt-out 2 hits; no cross-channel propagation rule | suppression rule sheet: list semantics, propagation, caps, strike limit 3 → `policy` deterministic `structured_data` | 1 × 2k | P2 |
| 5 Outbox/retry/DLQ | expert | **partial** — BR-045, exception playbooks 03/04, comms curriculum (generic); table-level runbook not measured | runbook bound to the real tables/columns and retry classes → `live_data_binding` + `standard_operating_procedure` | 1 × 2.5k | P2 |
| 6 SLAs & measurement | expert | **partial** — SLA-NOTIFICATION 5 min; comms metric_definition ×8 (no numbers in content) | metric dictionary with formulas and thresholds (bounce > x%, complaint > 0.1%, delivery < y%) → `kpi` `structured_data` | 8 × 400 | P2 |
| 7 Postiz mechanics | working | **partial** — `social_posts` columns show the checks (permalink_missing, media_missing) | 1 record → `live_data_binding` | 800 | P3 |
| 8 Incident playbooks | working | **present** — exceptions 03/04, "Repeated workflow failure" | add reputation-hit and template-rejection-wave playbooks → `remediation` | 2 × 1k | P2 |
| 9 Language/Arabic templates | working | **missing** — 0 Arabic templates | Arabic template set registered per channel → `response_template` + notification templates (engineering) | — | P2 |
| 10 Sender security | working | **partial** — IT security domain not bound (`it_security_knowledge` 0 items in v3) | bind `it_security_deep` scope for sender security → `employee_knowledge` | — | P3 |
| 11 Quiet hours | working | **present** — Ramadan/holiday playbook (CX) | add send-window table → `structured_data` | 300 | P3 |
| 12 Content boundary | aware | **present** — forbidden decision | — | — | P3 |

**Reasoning check.** The role's three owned actions have no authority class and no threshold (when is a bounce rate a
"sender reputation action"?); the comms pack carries 26 numeric fields in JSON but 0 in prose the agent reads; the exam
that scored it 0/5 asked about medical devices. P1 = 3.

---

## 7. Department summary — Customer Experience

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| followup | 6 | 6 | 4 |
| cs_support | 4 | 4 | 6 |
| cs_onboarding | 2 | 7 | 3 |
| cs_retention | 2 | 7 | 2 |
| channel_specialist | 3 | 5 | 4 |
| **Total** | **17** | **29** | **19** |

**Top 5 ingest items**

1. **Fix delivery first** (C1, C2, C3): Layer 2 admits 0 profession rows (8,200-char test after a ≈13k prefix); the v3
   rule list is alphabetical titles under a 2,000-char cap, so `Refund Policy`, `Sla And Response Targets`, the PDPL
   record and every refund/dispute playbook are dropped for a refund complaint; `dept_library` has 0 CX rows;
   `validated_experience` is always empty because no row is `validated`. Rank rules by task relevance and emit bodies;
   move the genome/risk blocks after Layer 2 or raise its budget; validate the 14 existing profession rows (9 of them
   the director's). Engineering, not ingest — but every item below is invisible until it is done.
2. **One reconciled refund-and-goodwill rule record** (followup, cs_support, cs_retention, cs_onboarding): the
   3-working-day non-response refund, the 1/3/3 notify/call/claim ladder, supplier charge "except where not permitted
   under UAE law", chargeback-as-fact, founder-only decision, what a complete case contains, and the admin-fee truth —
   with 5 worked ticket replies EN/AR. Also correct the `employee_authority` row that grants `followup`
   `refund_within_window` autonomous against its own forbidden list. ≈ 3k chars + JSON, `ops_knowledge`
   customer_experience `authority` deterministic.
3. **UAE consumer-protection + PDPL-for-support digest** (all five): FL 15/2020 + Cabinet Res. 66/2023 scope and
   complaint rights, B2B boundary, DSAR/deletion timelines, breach path, TDRA/Cybercrime/telemarketing messaging rules —
   dated `kb_chunks` regulatory sources plus deterministic `policy` records with "hand to Legal if" arms; bind `pdpl` and
   `legal_uae` in `employee_knowledge` for CX agents (currently absent). ≈ 15k chars. All **verify** against gazette text.
4. **WhatsApp Business Platform + email deliverability standard** (channel_specialist, cs_support, followup,
   cs_retention): 24-hour window, template categories/approval/rejection, quality tiers, opt-in evidence; SPF/DKIM/DMARC,
   Gmail/Yahoo bulk-sender rules, bounce taxonomy → suppression actions, frequency caps and cross-channel opt-out
   propagation. ≈ 10k chars, `kb_chunks` `_global` + `ops_knowledge` comms `policy`/SOP deterministic with
   `structured_data` thresholds.
5. **Numbers and Arabic for the playbooks that already exist**: severity matrix (S1–S4 with ack/resolve clocks and
   owner), customer-facing SLA set EN/AR, churn health-score thresholds by segment, first-RFQ completeness scorecard with
   6 worked examples, rating-solicitation program (question set EN/AR, score-band actions), Arabic variants of the 13
   `response_template` intents. The situational playbooks are senior-quality prose; what is missing everywhere is the
   threshold, the worked example and the Arabic sentence.

Close behind: a single buyer/supplier journey map naming every lifecycle message (owned by the director, enumerated
nowhere measured), and a real instrument for CSAT/NPS so the two 95% KPIs the director is measured on can be measured.
