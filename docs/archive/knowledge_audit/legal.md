# Knowledge audit — Legal department (4 AI employees)

Measured 6 Sep 2026 02:00–03:30 UTC against production `htdblwldjkcgjvmqkbeh`, read-only. Every number was
read from a table or a function in the session; anything not measured says so. Scope: `org_agents.active and
department = 'legal'` → `legal` (General Counsel), `compliance_mgr` (Compliance & Privacy Officer),
`moderation_specialist` (Marketplace Content & Privacy Reviewer), `trust_safety_mgr` (Trust & Safety Manager).
The department's runtime scope is `fn_dept_scope('legal') = {legal, trust_safety}`.

## 0. Findings that apply to all four

**L1. No professional expertise reaches any legal employee.** `# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` is
38 characters (heading only) for all four, on both `fn_agent_context` overloads and on the production path
`fn_agent_context_capped(key, 24000, query)`. Cause: the admission guard at line 384 of
`scripts/sql/fn_agent_context_workload_names_the_holding_role.sql` (`length(out)+length(piece) <= own_cap+2200`,
own_cap 6,000) is evaluated after ~12,000 chars of genome, risk register and employee record are already in
`out`. The General Counsel's 22 profession topics (Civil Code, PDPL, consumer law, AML, arbitration, marketplace
T&Cs, a "MANDATORY UAE verification protocol") are never shown to it.

**L2. The production prompt is cut at 19,500 chars of standing context + 4,500 of retrieval** (aborted-DO probe,
nothing committed): head "trimmed to the first 19,500 characters of 29,746–31,707"; LAYER 3 live state
(`fn_ws_governance`), LAYER 4 lessons, OS objectives, the TOM digest, LAYER 2d role knowledge, 2f deterministic
rules and 2g facts-to-fetch are all cut. The 4,500-char tail for the GC on "supplier terms anti-circumvention
clause and PDPL consent" was: "MUQAWALA — ARTICLES 872–896 FULL TEXT", "All 58 articles — detailed summary
table" (unnamed statute), "Labour Law — Article-by-Article Expansion", "Commercial Agencies, Distribution,
Franchising", then one LAYER 2c record "QuotesDone — Legal, Compliance and Policy Framework". For
`trust_safety_mgr` on "supplier suspected of circumventing the platform" the tail was a smart-government portal
table, "Federal Law No. 11 of 2023 — nine chapters", ICV formula text, then the remediation "When a supplier or
buyer turns out to be fraudulent". The library retrieval is keyword-ranked and off-topic more often than on.

**L3. Contamination.** On the 2-arg call, LAYER 4 for `legal` is "Waterproofing Suppliers — Category Specialist
Expertise V2" and "Gypsum & False Ceiling Suppliers — Expert Qualification Strategy V3" (exam auto-fills);
for `compliance_mgr` "AV & Media Equipment Suppliers — Inquiry Qualification Playbook"; for
`moderation_specialist` "Roofing Suppliers — Category Specialist Expertise V2". These are `agent_knowledge`
experience rows written by the exam auto-fill from questions that asked the lawyer about trade-route YAML files.

**L4. The exam does not measure legal competence.** Exam grounding uses `kb_search(category = agent_key)`:
category `legal` collides with the 34,355-chunk international corpus (UN/OECD model tax conventions, CISG,
UNCITRAL insolvency, WIPO), category `compliance_mgr` = 8 chunks, `moderation_specialist` = 1,
`trust_safety_mgr` = 1. Question banks: legal 14 (10 pack-file recall, 4 domain), compliance_mgr 11 (5/6),
moderation_specialist 10 (10/0), trust_safety_mgr 10 (10/0). Two of the four have never been asked a domain
question.

**L5. The senior-expert rows are frameworks without the company's or the law's numbers.** 90 `ops_knowledge`
rows for legal carry `source_authority = 'senior_expert_uae'` (2 Sep 2026): 31 decision playbooks, 25 policies,
14 failure modes, 9 remediations, 5 authority rows, 3 references, 3 KPIs (avg 1,827 chars). PDPL is named in 15
of them; "3%" in 0; "15,000" (the anti-circumvention figure) in 0; `escalation_rule = {}` on all 90; 0 of 117
decision-bearing legal rows contain an AED figure; 11 contain an example. Keyword retrieval for
"anti-circumvention buyer contacts supplier off platform" returned "QuotesDone FAQ — Company Identity" first;
no row in the department is titled for anti-circumvention.

Department-level inventory (shared):

| Source | Rows | Freshness | What it covers |
|---|---|---|---|
| ops_knowledge dept_key=legal | 374 (270 V2 pack 31 Jul 2026; 90 senior_expert_uae 2 Sep; 14 other) | newest 4 Sep 2026 | 10 SOPs (Contract Review, Terms-Version Alignment, NDA Preparation, Supplier-Agreement Review, Customer Legal Complaint, PDPL Rights Request, Privacy Incident Legal Review, IP Infringement Review, Licence And Corporate Change, Regulatory Update); 31 senior playbooks (contract-review triage, NDA triage, limitation of liability, dispute/jurisdiction clauses, reveal fee as payment for access, pre-reveal preview, refund/credit authority, consumer vs business buyers, cooling-off, distance-selling disclosures, cross-border transfers, post-reveal data sharing, vendor/processor due diligence, onshore vs DIFC/ADGM, licensing posture, self-preferencing/MFN, reviews moderation, supplier onboarding contract, supplier licence verification, escalation packaging, new-market compliance map, AI decisions with legal effect); 25 policies (sanctions screening hard gate, retention "delete by default", data localisation, marketing consent, prohibited categories, fee transparency, what an agent may sign, force majeure …); 14 failure modes; 9 remediations (breach, litigation hold, demand letter, takedown, regulator complaint, law-enforcement requests, scraping, fraud); generic 10 decision rules + 10 exception playbooks. implementation_status: 64 active, 20 target_state, 10 implemented. |
| ops_knowledge dept_key=trust_safety | 134 (V2 pack yaml/md/json; 1 escalation rule) | 31 Jul 2026 | 4 packaged T&S roles × role_charter / decision_playbooks / escalation_matrix / 7 failure modes |
| kb_chunks category=legal | 34,355 (17,697 standard, 15,125 cert, 1,486 regulation, 43 other) | to 31 Aug 2026 | UN/OECD model tax conventions (4,613), OECD TP guidelines, CISG digest, ADGM Companies Regs 2020, WIPO handbooks, UNCITRAL guides, UNCLOS, ILO MLC, ADGM FSMR; UAE Civil Code 5/1985 (398 chunks, stored twice) |
| kb_chunks category=legal-and-compliance | 35,596 (1,707 sources) | 10–31 Aug 2026 | UK Companies Act 2006 (1,888), World Bank StAR, FATF MER UAE 2020 (944), UK DPA 2018, UK FSMA, UNCAC guides, EU MiCA/MiFID II/CRD IV/AML Reg 2024, FATF VASP guidance (stored 4×), DFSA AML rulebook, BCBS governance |
| UAE statutes present somewhere in kb_chunks (source ids seen; 462 UAE-ish ids across finance/legal/legal-and-compliance/exec, 19,369 chunks; the id list was truncated at ~90 names) | — | 29–31 Aug 2026 | PDPL 45/2021; Consumer Protection 15/2020; CCL 32/2021; Electronic Transactions & Trust Services 46/2021; Labour 33/2021 + Cabinet Res 1/2022; Civil Code 5/1985; AML 20/2018 + Cabinet Decision 10/2019; Commercial Transactions 50/2022; Arbitration 6/2018; Copyright 38/2021; Industrial Property 11/2021; Trading by Modern Technological Means 14/2023; Commercial Agencies 3/2022; CT 47/2022; DIFC laws (contract 6/2004, arbitration 1/2008, data protection 5/2020, employment 2/2019, insolvency, IP 4/2019 …); ADGM regs (companies 2020, data protection 2021, employment 2019, BO 2022, FSMR 2015 …); CBUAE Banking Law 14/2018. **Not found in the ids listed (verify before ingesting):** Cybercrime FDL 34/2021; Trademarks FDL 36/2021; Competition FDL 36/2023; Consumer Protection exec reg (Cabinet Res 66/2023); Civil Procedure FDL 42/2022; Penal Code 31/2021; Media FDL 55/2023; TDRA marketing rules; DET e-commerce guidance. |
| decision_policy | legal_triggers ["contract change","liability","indemnity","termination",…]; founder_review_gates; fraud_score_max 0.7; matching_strike_limit 3; sensitive_categories [fire, security, electrical, structural, gas, lif…]; confidence_min 0.6 | live | |
| governance_rule 6 | "legal or compliance risk detected → involve Legal & Compliance before proceeding" | live | |
| governance_policy owner legal | "Minimum data" (process), "Documents" retention (declared) | live | |
| founder_reserved_decision | unapproved_legal_commitment; founder_commercial_rules; material_policy_change; reveal_fee_pct | live | |
| phase_b_business_rule | BR-011 no customer identity before reveal; BR-012 approved safe package; BR-018 supplier quote supplier-authored; BR-021 3% (founder); BR-030 independent supplier verification; BR-034 consent & suppression; BR-035 approved asset revision only; BR-036 actual artifact review | frozen 15 Aug 2026 | |
| company scope rows | Hard gate — legal_commitment; Hard gate — public_claim_publish; Data classification × 5; "Fail closed on privacy"; "Data minimisation"; "Anonymity until reveal" | 31 Jul 2026 | in `ops_knowledge` scope_type=company |
| policy_rules | 7 forbid-regex rows (old 2%/AED 250 wording, "supplier commission", vague first-year-free) | live | applied to published text |
| company_constitution art. 9 Security & privacy, art. 11 Escalation, art. 20 Ethics | | 26 Jul / 9 Aug 2026 | in the genome block |

---

## 1. `legal` — General Counsel (org_role `general_counsel`, director, reports to brief)

**What it does today.** agent_runs 7d: 39 ok (cron-driven). Context assemblies 30d: 20 (last 3 Sep; 45
kb_usage_log rows, all `context_assembly`). review_chain as author: 227 (159 approve; also `request_revision`
and `required` present); as reviewer: 95. Exam: 24 results since 26 Jul, **9 correct / 2 partial / 2 wrong / 11
not_covered = 37.5%** (30d 35.0%); domain-only 5/8 = 62.5%; 9 gaps auto-filled (5 of them trade-route files —
see L3). Wrong: the PDPL cross-border transfer condition.

**Persona.** owned: legal position of the company; contract terms and their acceptance; regulatory
interpretation; enforcement and ban decisions. forbidden: approving its own compliance audit; commercial
pricing; overriding an independent reviewer's stop. authority execute_medium, budget AED 10,000;
employee_authority `compliance_check` gated at AED 10,000 (further rows not read — output truncated).
tools: brand_scan, compliance_check, legal_review, pdpl_action. output_contracts: legal_position,
contract_verdict, enforcement_decision. `agent_action_kind_policy`: authority for `compliance_update:officer`,
`legal_flag:notify`. Senior authority row on record: "The founder holds the litigation and settlement pen —
agents never sign". Standing deputy: compliance_mgr.

**Knowledge inventory (agent-specific).**

| Source | Rows / size | Freshness | Covers |
|---|---|---|---|
| agent_knowledge profession | 22 topics, avg 960 chars, all `unvalidated` | last updated **26 Jul 2026** | uae_legal_system_basics, contract_law_civil_code (names Civil Transactions Law 5/1985, Art. 246 good faith; asserts a new Civil Code FDL 25/2025 effective 1 Jun 2026 — **verify, no kb source names it**), commercial_law_and_licensing, consumer_protection_ecommerce, marketplace_tandcs_intermediary, pdpl_data_protection (FDL 45/2021, UAE Data Office, rights list, DIFC/ADGM regimes — correct; says "do not state penalty amounts"), MANDATORY UAE verification protocol (1,647 chars: name governing law + regulator + consent duty before any answer; claims the Data Office now sits inside a "UAE Federal Authority for AI and Data" from June 2026 — **verify**), aml_cft_onboarding, dispute_resolution_arbitration, labor_law_essentials, construction_contracts_payment_dispute, Debt-recovery procedure, Litigation hold, Vendor contract review checklist, sector_regulation_awareness, environmental_safety_awareness, QuotesDone policy library (system reference), Professional standard (UAE advocate level), Verified UAE references, Role & expertise, Deepened playbook, exam:domain. **None delivered (L1).** |
| agent_knowledge experience | 10 | 5 Sep 2026 | 8 exam fills (5 trade-route files, role_charter.md, an advanced curriculum, "Third-party links, embeds and integrations"), 2 real lessons ("Legal/compliance deliverables must…", "The 'Compliance checks completed' …") |
| employee_knowledge | 12 (legal_uae@expert, pdpl@expert, company set@expert, finance/marketing/procurement@awareness, quotesdone_os@working, communication@working) | — | 5/12 layers bound → INCOMPLETE |
| knowledge_domain sources | legal_uae → "legal_documents + regulations"; pdpl → "regulations + pdpl_requests" | — | binding names tables; content delivery not measured |
| exam bank | 14 (10 pack recall, 4 domain) | 5 Sep 2026 | |
| fn_agent_context('legal', 22000) | 29,746 chars; production head 19,500 | live | LAYER 1 9,265 (brand ×2, AI Constitution, response structure, governance gate, retrieve-before-answering, RFQ completeness, Pricing LIVE, FAQ header, 5 explainability stubs, canon:core, canon:supplier_status); LAYER 2 empty; LAYER 3 fn_ws_governance 2,731 (cut in production); LAYER 4 = Waterproofing + Gypsum specialist text (contamination) |

**Senior-staff standard — General Counsel of a UAE B2B RFQ marketplace.**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE legal architecture: federal vs emirate law; onshore courts vs DIFC/ADGM (own contract, DP, employment, insolvency laws and courts); which regime binds QuotesDone and its counterparties | expert |
| 2 | Contract law: Civil Transactions Law 5/1985 (formation, good faith Art. 246, damages, hardship, court power over penalty clauses — verify article), Muqawala Arts 872–896, Commercial Transactions Law FDL 50/2022; status of any 2025/26 Civil Code replacement — verify | expert |
| 3 | Electronic contracting: FDL 46/2021 Electronic Transactions & Trust Services; click-wrap assent that actually binds; evidence capture of acceptance (BR-025 exact terms acceptance) | expert |
| 4 | Marketplace terms architecture: platform contract vs supply contract; intermediary posture; reveal fee = payment for access; anonymity until reveal (BR-011); supplier non-response 3% rule; top-3 report promise; **anti-circumvention clause (AED 15,000 / 3× — the published rule)**; limitation of liability; indemnities mutual/scoped/capped; unilateral changes; governing law + forum (Dubai Courts / DIFC Courts opt-in / DIAC) | expert |
| 5 | Refund policy law and the company rule: 3 working days, AED 250 admin fee, 9% p.a. late fee, founder approves every refund; consumer-law cancellation rights vs B2B | expert |
| 6 | Consumer Protection Law 15/2020 + Cabinet Res 66/2023 (verify) — when a buyer is a consumer; misleading claims; e-commerce disclosure duties | expert |
| 7 | E-commerce regulation: FDL 14/2023 Trading by Modern Technological Means; DET e-commerce licensing and activity scope (what QD's licence actually permits — a founder-held fact, verify) | expert |
| 8 | PDPL FDL 45/2021: lawful bases, notices, DSAR handling, breach notification to the UAE Data Office, cross-border transfer (adequacy or safeguards), DPO trigger, automated-decision rights; executive regulations status — verify; DIFC DP Law 5/2020 / ADGM DP Regs 2021 for free-zone counterparties; processor map (Stripe, Supabase region, OpenRouter, Meta/WhatsApp) | expert |
| 9 | Cybercrime & content: FDL 34/2021 (defamation, privacy, unlawful content), platform liability posture, notice-and-takedown, law-enforcement requests via Dubai Police | working |
| 10 | IP: Copyright FDL 38/2021, Trademarks FDL 36/2021, Industrial Property FDL 11/2021; licence to display supplier content; brand protection; scraping | working |
| 11 | Competition Law FDL 36/2023 (MoE): MFN, exclusivity, price signalling on a marketplace | working |
| 12 | Corporate & licensing: CCL FDL 32/2021, UBO (Cabinet Decision 109/2023 — verify), Commercial Agencies 3/2022, licence renewal/amendment, free-zone options; who may sign (founder) | working |
| 13 | AML/sanctions: FDL 20/2018 (+26/2021) and executive regulation (verify current), DNFBP determination (document it), Cabinet Decision 74/2020 TFS, EOCN local list; KYB of suppliers and paying buyers | working |
| 14 | Payments perimeter: CBUAE Retail Payment Services & Card Schemes Regulation 2021, Stored Value Facilities Regulation 2020 — no fund holding/escrow without a licence | working |
| 15 | Disputes & litigation: Civil Procedure FDL 42/2022 (payment order for undisputed debts — verify), Arbitration Law 6/2018 (+15/2023), DIAC Rules 2022, DIFC Courts, enforcement, limitation periods, litigation hold, demand letters; the founder holds the pen | expert |
| 16 | Employment/contractor: FDL 33/2021, freelancer permits, IP assignment in contractor terms | aware |
| 17 | Tax posture touchpoints: VAT on the reveal fee, invoice compliance, CT registration — coordinate with finance | aware |
| 18 | Marketing & communications law: consent and unsubscribe, TDRA unsolicited-marketing rules (verify), WhatsApp Business template/opt-in policy, advertising claims (UAE Media Council FDL 55/2023 — verify) | working |
| 19 | Supplier onboarding contract and verification: the five risk clauses; DET/free-zone licence lookup, National Economic Register, TRN lookup; independent verification (BR-030) | expert |
| 20 | Regulatory change monitoring: UAE Legislation portal, FTA, MoE, TDRA, Data Office; the Regulatory Update SOP | working |
| 21 | AI decisions with legal effect: human path, disclosure of automation in terms, what an agent may draft vs sign | expert |
| 22 | Company boundaries and gates: founder-reserved keys, hard gate legal_commitment, legal_triggers list, review chain roles | expert |
| 23 | Document set & version control: customer T&Cs, supplier T&Cs, privacy notice, refund policy, NDA, supplier agreement; Terms-Version Alignment SOP; published §5 CC rule (memory: "Terms say CC us") | expert |

**Gap table.**

| Domain | Depth | Today (evidence) | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Legal architecture | expert | present — profession `uae_legal_system_basics` (undelivered), senior playbook "Onshore vs free zone (DIFC/ADGM)", kb has DIFC/ADGM laws | deliver L1 | — | P2 (delivery) |
| 2 Contract law | expert | partial — Civil Code 5/1985 in kb (398 chunks); Muqawala text in dept library (reached the tail); profession row asserts a 2025/26 new Civil Code with no source | verify the Civil Code status and record the answer as one `reference` row; kb ingest of Commercial Transactions 50/2022 is present — confirm chunk count (not measured) | 1 page + verify | **P1** (a wrong "which code applies" is a wrong contract read) |
| 3 E-contracting | expert | present — kb law:uae-ett-46-2021; senior authority "Electronic contracts and signatures are valid — capture the proof"; BR-025 | — | — | — |
| 4 Marketplace terms | expert | **partial** — 10+ senior playbooks cover the clauses generically; **no row states the anti-circumvention rule (AED 15,000 / 3×), the supplier non-response 3% rule or the top-3 report** (0 mentions of 15,000 in 90 rows); the published T&Cs themselves are not in any table I read (policy_rules only forbids stale wording) | ops_knowledge legal `reference` "QuotesDone published terms — clause map" (customer T&Cs, supplier T&Cs, refund policy) with clause numbers and the four commercial rules as `structured_data`; ingest the live T&C documents into kb_chunks under a `legal_qd_terms` category so the GC can quote its own contract | 15 pages / 40 chunks | **P1** |
| 5 Refund policy law | expert | partial — senior playbook "Refund and credit authority: honour the published rule, escalate the discretionary ask", "Cooling-off and cancellation for a reveal fee"; numbers only in decision_policy (not in the prompt) | shared refund decision tree (finance) + the legal annex: which cancellation rights apply to a consumer vs a business buyer | 2 pages | **P1** |
| 6 Consumer law | expert | partial — kb law:uae-consumer-15-2020; profession `consumer_protection_ecommerce`; senior "Consumer versus business buyers", "Distance-selling disclosures"; exec reg 66/2023 not found | kb_chunks: Cabinet Resolution 66/2023 (verify) under a UAE-statute category; `reference` row on the consumer/B2B boundary test | 40 pages / 100 chunks | P2 |
| 7 E-commerce & licence | expert | partial — kb legal-uae-trading-modern-tech-14-2023; senior "Regulatory licensing posture: what kind of permission does a reveal-fee marketplace need"; **the company's actual licence/activity is unknown to every table** (the exam examiner assumed an E-Trader licence) | `reference` row "QuotesDone licence facts" (authority, activity codes, renewal) — founder-held, mark verify/fetch | 1 page | **P1** |
| 8 PDPL | expert | **partial** — profession rows correct but undelivered; kb law:uae-pdpl-45-2021; senior policies/playbooks (data-subject rights, cross-border, breach remediation, processor due diligence, retention); SOP Pdpl Rights Request; exam wrong on transfer condition; **no processor map, no DSAR clock, no breach clock, no exec-reg status** | ops_knowledge legal `policy` "PDPL operating facts for QuotesDone": lawful basis per processing purpose, processor map with regions, DSAR handling steps + internal SLA, breach playbook with the Data Office notification rule (verify timing in exec regs), transfer mechanism per processor; `structured_data` for the clocks | 6 pages / 15 chunks | **P1** |
| 9 Cybercrime/content | working | partial — senior "Reviews and ratings: moderate for defamation", remediation "Notice-and-takedown"; **FDL 34/2021 not found in kb ids** | kb_chunks: Cybercrime FDL 34/2021 (verify) | 30 pages / 70 chunks | P2 |
| 10 IP | working | partial — kb copyright 38/2021, industrial property 11/2021, DIFC IP 4/2019; senior "You need a licence to display supplier content"; trademarks 36/2021 not found | kb_chunks: Trademarks FDL 36/2021 (verify) | 40 pages | P3 |
| 11 Competition | working | partial — senior "Self-preferencing, exclusivity and MFN clauses", failure mode "don't become a price-signalling hub"; FDL 36/2023 not found in kb | kb_chunks: Competition FDL 36/2023 (verify) | 30 pages | P3 |
| 12 Corporate & licensing | working | partial — kb CCL 32/2021, ADGM BO regs; senior "Corporate governance basics"; UBO decision not named | `reference` row on UBO/licence/signatory facts (verify decision number) | 1 page | P2 |
| 13 AML/sanctions | working | present — kb law:uae-aml-20-2018 + exec reg, FATF MER UAE 2020, DFSA/ADGM AML rulebooks; senior authority "AML from the legal angle", policy "Sanctions screening: a hard gate" | one `policy` row documenting the DNFBP determination and which list is screened | 1 page | P2 |
| 14 Payments perimeter | working | present — failure mode "Holding buyer funds changes everything" | — | — | — |
| 15 Disputes & litigation | expert | partial — kb arbitration 6/2018, DIFC arbitration 1/2008; profession `dispute_resolution_arbitration`, `Debt-recovery procedure`, `Litigation hold`; senior "Draft dispute and jurisdiction clauses that actually work in the UAE", remediations demand letter/litigation hold; Civil Procedure 42/2022 not found | kb_chunks: Civil Procedure FDL 42/2022 (verify); `reference` row "Recovery and dispute paths with cost/time bands" | 60 pages + 2 pages | P2 |
| 16 Employment | aware | present — kb labour law + exec reg; profession `labor_law_essentials` | — | — | — |
| 17 Tax touchpoints | aware | present — senior policy "Tax posture: keep VAT and record-keeping correct on every reveal fee" | — | — | — |
| 18 Marketing law | working | partial — senior policy "Marketing communications: consent, identification and an unsubscribe that works", BR-034; TDRA rules and WhatsApp policy not in any row | `reference` row "Outbound messaging rules (TDRA + WhatsApp Business)" (verify TDRA instrument) | 2 pages | P2 |
| 19 Supplier contract & verification | expert | present — senior "Supplier onboarding contract: the five clauses", "Verify supplier legal existence and licence", SOP Supplier-Agreement Review, BR-030; no lookup-source list | `reference` row listing the verification sources (DET licence lookup, National Economic Register, FTA TRN lookup, free-zone portals) | 1 page | P2 |
| 20 Regulatory monitoring | working | present — SOP Regulatory Update; senior policy "Compliance change monitoring"; `fn_regulation_watch()` exists | — | — | — |
| 21 AI decisions with legal effect | expert | present — senior playbook "Automated decisions with legal or significant effect need a human path", policy "AI/agent conduct terms", authority "What an agent may sign versus what it may only draft" | — | — | — |
| 22 Company boundaries | expert | present (founder_reserved, hard gates, legal_triggers) but **LAYER 2f is never delivered** (L2) | fix L2 | — | **P1** (delivery) |
| 23 Document set & versions | expert | partial — senior reference "standard document set the marketplace must maintain", SOP Terms-Version Alignment; the documents themselves absent (see #4) | see #4 | — | (with #4) |
| — Live state | expert | fn_ws_governance cut (L2) | fix L2 | — | (with #22) |

**Reasoning gap.** The GC has the best-written framework layer in the company (31 playbooks, 25 policies with
clear stances: "reason from the boundary, escalate at the boundary", "honour the published rule, escalate the
discretionary ask") — and none of it carries a number, a clause reference or a worked case, and none of the
profession layer is delivered. It cannot quote its own T&Cs because they are not stored. Escalation is the same
306-char generic block as every other agent; `legal_triggers` (decision_policy) and the hard gate
`legal_commitment` exist but sit in the cut LAYER 2f. A senior GC would also expect: three worked contract
reviews (customer T&C change, supplier agreement, NDA) with the verdict and the clause cited; a DSAR and a
breach timeline with clocks; a "which court/forum" decision rule with cost bands.

**P1 count: 6** (contract-law version fact, terms clause map + T&C ingest, refund legal annex, licence facts,
PDPL operating facts, rules-layer delivery).

---

## 2. `compliance_mgr` — Compliance & Privacy Officer (org_role `compliance_and_privacy_officer`)

**What it does today.** agent_runs 7d: 1 ok. Context assemblies 30d: 19 (last 3 Sep). review_chain author: 5
(3 approve); reviewer: 50 (all approve). Exam: 26 since 15 Aug, **7 correct / 5 partial / 7 wrong / 7
not_covered = 26.9%**; domain-only 4/16 = 25.0%. Wrong: "which UAE federal legislation governs the processing
of personal data" (the answer is the PDPL — its own expert domain), DET licence-scope consequence, legal status
under the DET framework.

**Persona.** owned: whether an action is legally/policy compliant; data-protection and retention decisions;
blocking an action on a compliance finding. forbidden: per-artifact supplier-safe approval (moderation's);
knowledge-record validity; release go/no-go; approving a position it authored. authority_level
**stop_authority**, budget AED 1,000; employee_authority: compliance_check autonomous ≤ AED 1,000,
legal_review autonomous ≤ AED 1,000, pdpl_action advisory, review_block autonomous ("may block unsafe work,
may never approve"). tools: brand_scan, compliance_check, legal_review, pdpl_action. output_contracts:
compliance_verdict, privacy_assessment, dsr_response. Deputy for the GC.

**Inventory.** agent_knowledge 8: 3 profession rows — `exam:authority`, `exam:compliance`, "UAE compliance for
a Dubai e-trader marketplace" — **avg 376 chars, 15 Aug 2026** (the thinnest profession layer of any director
or specialist in scope, and undelivered) + 5 exam fills (Regulatory Monitoring, decision_playbooks.yaml,
department_kpis.yaml, qualification_playbook.md, 03_QUOTE_READINESS…). employee_knowledge 12
(legal_uae@expert, pdpl@expert …); 5/12 layers. Exam bank 11 (5/6). Context: LAYER 1 10,222; LAYER 2 empty;
LAYER 4 = AV & Media qualification playbook (contamination); production tail 2c 1,232.

**Senior-staff standard — Compliance & Privacy Officer (DPO-equivalent) for a UAE marketplace.**

| # | Domain | Depth |
|---|---|---|
| 1 | PDPL operations: records of processing, lawful basis per purpose, privacy notice content, DSAR intake → verification → response (internal SLA; statutory timing per exec regs — verify), rectification/erasure/objection handling, DPIA for new features, DPO duties | expert |
| 2 | Breach management: detection → containment → assessment → Data Office notification (timing — verify) → data-subject notification; evidence file; the founder authorises external notification | expert |
| 3 | Cross-border transfers: adequacy vs safeguards, processor map (Supabase region, Stripe, OpenRouter, Meta), contract clauses | expert |
| 4 | Retention & deletion: schedule per record class (the company's 5 data classes), "delete by default, retain by legal exception", 5-year tax retention as a legal exception, litigation hold override | expert |
| 5 | Processor/vendor due diligence and data-processing terms | expert |
| 6 | Marketing & messaging compliance: consent, suppression (BR-034), unsubscribe, TDRA unsolicited-marketing rules (verify), WhatsApp opt-in | expert |
| 7 | Cybercrime/content compliance: FDL 34/2021 duties, unlawful content, prohibited/restricted categories (weapons, alcohol, pharma/medical devices needing MOHAP, security systems needing SIRA, electrical needing DEWA approvals) | working |
| 8 | Consumer & e-commerce disclosures: Law 15/2020, FDL 14/2023, DET e-commerce rules; fee transparency at reveal | working |
| 9 | Licence-scope compliance: what activities the licence permits; when a new category or service needs a licence amendment | working |
| 10 | AML/sanctions scope: DNFBP determination, screening list, escalation | working |
| 11 | Regulatory change monitoring and the compliance calendar (Regulatory Update SOP; `fn_regulation_watch`) | expert |
| 12 | Compliance-check method: the checklist behind `compliance_check`, the AED 1,000 autonomy limit, when to invoke `review_block`, evidence for a verdict | expert |
| 13 | Audit evidence: proving a control ran (approval trace, decision records) | working |
| 14 | Internal governance policies: 16 governance_policy rows, 11 governance rules, hard gates, data classification | expert |
| 15 | Live data: `pdpl_requests`, `legal_kpi_snapshot`, `fn_ws_governance` | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 PDPL operations | expert | **partial/thin** — bound as pdpl@expert but its own profession layer is 3 rows/376 chars; the GC's PDPL rows are not in its context (LAYER 2 empty, and cross-agent fallback only fires when the agent has no rows); senior policy "Data-subject rights: build the request handling before the request arrives", SOP Pdpl Rights Request, cross-dept workflow "Personal-data rights request"; exam: named the wrong statute | shared "PDPL operating facts" policy (GC #8) authored FOR compliance_mgr in agent_knowledge profession (so LAYER 2 carries it once delivery is fixed), + a DSAR SOP with steps and clocks | 6 pages | **P1** |
| 2 Breach | expert | partial — senior remediation "Personal-data breach: contain, assess, notify — on the founder's authority"; no clock, no template | `decision_playbook` "Breach timeline" with `structured_data` clocks (verify statutory timing) and the notification template | 2 pages | **P1** |
| 3 Cross-border | expert | partial — senior playbook "Cross-border data transfers: know where your processors sit", policy "Data localisation"; **no processor map exists in any row** | `reference` "Processor map" (name, region, purpose, transfer basis) | 1 page | **P1** |
| 4 Retention | expert | partial — senior policy "Retention schedule: delete by default", governance_policy "Documents"; `retention_policy` table exists (rows not measured); data classification ×5 in company scope | verify `retention_policy` rows and emit them as one `reference` with per-class periods | 1 page | P2 |
| 5 Processor DD | expert | present — senior "Vendor/processor due diligence before you route personal data to them" | — | — | — |
| 6 Marketing compliance | expert | partial — senior policy on consent/unsubscribe; BR-034; TDRA/WhatsApp rules absent | shared messaging-rules reference (GC #18) | 2 pages | P2 |
| 7 Cybercrime/content | working | partial — senior "Prohibited and restricted categories"; business_rules name DEWA/SIRA gates; FDL 34/2021 not in kb | kb ingest (GC #9); `reference` "Category gates and licences (DEWA, SIRA, MOHAP, Civil Defence)" | 2 pages + 70 chunks | P2 |
| 8 Consumer/e-commerce | working | partial (GC #6/#7) | shared | — | P2 |
| 9 Licence scope | working | **missing** — exam wrong ×3 on licence questions; no licence facts anywhere | shared "licence facts" reference (GC #7) | 1 page | **P1** |
| 10 AML scope | working | present (GC #13) | shared policy row | — | P2 |
| 11 Regulatory monitoring | expert | present — SOP Regulatory Update, `fn_regulation_watch`, knowledge_kpis regulations 17 | — | — | — |
| 12 Compliance-check method | expert | **missing** — tool `compliance_check` autonomous ≤ AED 1,000 but no checklist row defines what it checks; the AED 1,000 limit has no rule text | `standard_operating_procedure` "compliance_check: the checklist, the evidence, the block criteria" bound to the tool; a decision_rule for `review_block` | 2 pages | **P1** |
| 13 Audit evidence | working | present — `fn_approval_trace_audit`, decision_record | — | — | — |
| 14 Internal governance | expert | present in tables; LAYER 2f cut (L2) | fix L2 | — | P2 (delivery) |
| 15 Live data | expert | LAYER 3 cut (L2) | fix L2 | — | **P1** (delivery) |
| — Contamination | — | LAYER 4 carries an AV-equipment qualification playbook | quarantine the 5 trade-route exam fills (set validation_status='quarantined') | — | P2 |

**Reasoning gap.** A stop authority with no written test for when to stop. It holds `review_block` and
`compliance_check` autonomously, but no row says what a compliance check consists of, what evidence a verdict
needs, or what finding justifies a block. Its expert domain (PDPL) is answered from 376 chars of its own text.
The exam's three wrong answers all concern the company's own licence — a fact no table holds.

**P1 count: 6** (PDPL operating facts + DSAR SOP, breach timeline, processor map, licence facts,
compliance-check SOP, live-state delivery).

---

## 3. `moderation_specialist` — Marketplace Content & Privacy Reviewer (org_role `marketplace_content_privacy_reviewer`)

**What it does today.** agent_runs 7d: **0** (not present in agent_runs). Context assemblies 30d: 0.
review_chain author: 0; reviewer: 0. artifact_review rows authored by it: 0 (reviewer_agent side not measured).
Exam: 20 since 3 Sep, **5 correct / 8 partial / 3 wrong / 4 not_covered = 25.0%**; **10/10 questions are
pack-file recall** — it has never been asked a moderation question.

**Persona.** owned: approving, rejecting or returning a supplier-facing payload; approving the specific file
revisions a supplier may see; blocking dispatch on an unremoved customer identifier. forbidden: authoring the
brief or redaction it approves; approving its own work under any alias; general moderation policy, disputes,
enforcement (T&S); dispatching; overriding a regulatory or category gate. authority stop_authority;
employee_authority: `analysis` supervised only. tools: compliance_check, legal_review, pdpl_action,
**artifact.review**, brand_scan. knowledge_scopes 11 (legal, trust_safety, pdpl, legal_uae, marketplace,
doc_intelligence, supplier_mgmt, company, constitution, priority_hierarchy, quotesdone_os).
output_contracts: content_privacy_verdict, redaction_evidence. **employee_knowledge: 0 rows.**

**Inventory.** agent_knowledge 7: one profession row "Enforcing anonymity on a quoting marketplace" (700 chars,
11 Aug — a good paragraph on where contact details hide: numbers written in words, split emails, PDF headers,
drawing title blocks, letterheads; undelivered) + 6 exam fills (Roofing specialist, Complaints controls,
specialist_manifest.yaml …). Context: LAYER 1 10,241; LAYER 2 empty; LAYER 4 = Roofing specialist text;
production tail 2c 484 chars + "Legal & Compliance — Operating Knowledge Pack" 691.

**Senior-staff standard — senior content/privacy reviewer for an anonymous RFQ marketplace.**

| # | Domain | Depth |
|---|---|---|
| 1 | The anonymity contract: BR-011 (no customer identity before reveal), BR-012 (approved safe package), BR-035 (approved revision only), BR-036 (actual artifact review); what "supplier-safe" means per field and per file | expert |
| 2 | UAE identifier taxonomy: +971 / 05x numbers (also spelled out, spaced, Arabic-Indic digits), emails, TRN (15 digits), Emirates ID (784-…), trade-licence numbers by authority, PO Box, Makani numbers, plot/DM numbers, company names, logos, signatures, letterheads, LinkedIn/WhatsApp links, project names that identify a client | expert |
| 3 | File-level leakage: PDF metadata (author/company), CAD title blocks and xrefs, image EXIF, watermarks, embedded fonts/logos, hidden layers, tracked changes, spreadsheet hidden sheets | expert |
| 4 | Redaction verification method: independent re-scan after redaction, OCR of rasterised pages, Arabic text, diff between revisions, evidence contract (`artifact_review.deterministic` + `vision`) | expert |
| 5 | PDPL minimisation and purpose limitation applied to a supplier-facing packet; what may never be shared even after reveal | expert |
| 6 | Content policy: defamation/unlawful content (FDL 34/2021), prohibited/restricted categories and licence gates (weapons, alcohol, pharma/medical devices — MOHAP; security — SIRA; electrical — DEWA; fire — Civil Defence), IP-infringing material (copyright 38/2021, trademarks 36/2021 — verify) | working |
| 7 | Verdict semantics: approve / return (fixable, with the exact defect) / reject (unfixable or policy breach) / block dispatch; who fixes; SLA against dispatch (W12/W13) | expert |
| 8 | Escalation: to T&S for suspected circumvention or fraud, to compliance for a privacy question, never to override a category gate | expert |
| 9 | Bilingual handling (Arabic/English) and RTL text in documents | working |
| 10 | Supplier-authored quote integrity on the way back (BR-018/BR-019): what the buyer may see, contact details in quotes | expert |
| 11 | Evidence writing: the redaction_evidence contract — what a reviewer records so the decision is auditable | expert |
| 12 | Live data: which tables hold the payload, the file revisions and the review verdicts | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Anonymity contract | expert | present as rules (BR-011/012/035/036, company row "Anonymity until reveal", canon:core "ANONYMOUS") but LAYER 2f is cut (L2) | fix L2 | — | P2 (delivery) |
| 2 Identifier taxonomy | expert | **partial** — one 700-char paragraph (undelivered); no UAE-specific pattern list | agent_knowledge profession (for this agent) "UAE identifier patterns" with regexes in `structured_data`; ops_knowledge legal `reference` copy | 3 pages / 6 chunks | **P1** |
| 3 File-level leakage | expert | partial — same paragraph mentions title blocks/headers; nothing on metadata/xrefs/EXIF | `standard_operating_procedure` "File hygiene before dispatch" (PDF/DWG/images/xlsx) | 2 pages | **P1** |
| 4 Verification method | expert | partial — BR-036 says "actual artifact review"; `artifact_review` table has deterministic + vision columns; no SOP says what a pass is | SOP "Redaction verification: deterministic scan, OCR, vision, diff; pass/fail criteria" | 2 pages | **P1** |
| 5 PDPL minimisation | expert | present (dept policies "Privacy by design", "Data minimisation") | — | — | — |
| 6 Content policy | working | partial — senior "Prohibited and restricted categories", business_rules (DEWA/SIRA); cybercrime law not in kb | shared category-gates reference (compliance #7) | 2 pages | P2 |
| 7 Verdict semantics | expert | **missing** — output_contract names `content_privacy_verdict` but no row defines approve/return/reject/block criteria | `decision_rule` rows with the four verdicts and examples | 1 page | **P1** |
| 8 Escalation | expert | partial — generic block; forbidden list is clear | one `escalation_rule` on the verdict decision_rule | — | P2 |
| 9 Bilingual | working | missing | one paragraph in #2 | — | P3 |
| 10 Quote-side integrity | expert | present — BR-018/019 | — | — | — |
| 11 Evidence writing | expert | missing — `redaction_evidence` contract undefined in any row | template in the verification SOP (#4) | — | (with #4) |
| 12 Live data | expert | LAYER 3 cut (L2) | fix L2 | — | **P1** (delivery) |
| — Curriculum | — | employee_knowledge 0 rows | bind pdpl@expert, legal_uae@working, marketplace@working, doc_intelligence@working, company set@expert, quotesdone_os@working | — | **P1** |
| — Exam | — | 0 domain questions | give the examiner this standard as the remit | — | P2 |

**Reasoning gap.** This is the one employee in scope whose job is a deterministic check, and it has no checklist,
no pattern list, no pass criteria and no verdict definitions. It has not run in 7 days and has authored no
review. A senior reviewer's value is the taxonomy in their head; here the taxonomy is one paragraph nobody
delivers.

**P1 count: 6** (identifier taxonomy, file-hygiene SOP, verification SOP + evidence template, verdict rules,
live-state delivery, curriculum binding).

---

## 4. `trust_safety_mgr` — Trust & Safety Manager (org_role `trust_and_safety_manager`)

**What it does today.** agent_runs 7d: 37 ok (cron). Context assemblies 30d: 0. review_chain author: 185 (111
approve); reviewer: 0. Exam: 20 since 3 Sep, **5 correct / 8 partial / 4 wrong / 3 not_covered = 25.0%**;
**10/10 pack-file recall**, 0 domain questions.

**Persona.** owned: platform policy application; dispute-handling path; escalating an enforcement
recommendation. forbidden: banning without the General Counsel; approving its own fraud review; legal
conclusions. authority execute_low; employee_authority: `analysis` supervised only. tools: brand_scan,
compliance_check, legal_review, pdpl_action (no fraud/enforcement tool named). knowledge_scopes: legal,
trust_safety. output_contracts: policy_decision, enforcement_recommendation. **employee_knowledge: 0 rows.**
Numbers available to it in decision_policy: fraud_score_max 0.7, matching_strike_limit 3,
sensitive_categories list; business_rules: Electrical requires DEWA, Security requires SIRA, High-value fire
safety, Large project needs references.

**Inventory.** agent_knowledge 7: one profession row "Platform integrity on a two-sided marketplace" (669
chars, 11 Aug — fraud signals on both sides, "set thresholds so the expensive error — a real business refused —
is rarer than…"; undelivered) + 6 exam fills. Department scope adds the 134 trust_safety pack rows (4 packaged
roles' charters, decision_playbooks.yaml, escalation_matrix.yaml, 7 failure modes each; 1 escalation rule) and
the legal senior rows (remediation "When a supplier or buyer turns out to be fraudulent", "Screen-scraping and
competitor mirroring", policy "Sanctions screening: a hard gate"). Context: LAYER 1 10,241; LAYER 2 empty;
production tail = procurement-portal text + "Federal Law No. 11 of 2023" chapters + ICV formula (off-topic) +
the fraud remediation.

**Senior-staff standard — Head of Trust & Safety for a UAE B2B marketplace.**

| # | Domain | Depth |
|---|---|---|
| 1 | Fraud typologies on both sides: fake suppliers (licence mismatch/expired, mailbox address, new domain, reused phones), fake RFQs harvesting pricing, card testing, refund abuse, review manipulation, account takeover | expert |
| 2 | KYB verification sources: DET licence lookup, free-zone portals, National Economic Register (MoE), FTA TRN lookup, UAE PASS identity, sanctions (UN consolidated + EOCN local list); what "verified supplier" means (governance_policy 15; BR-030) | expert |
| 3 | Risk scoring and thresholds: fraud_score_max 0.7, strike limit 3, what raises a score, the cost asymmetry (false refusal of a real business), review of borderline cases | expert |
| 4 | Circumvention detection and the published rule: anti-circumvention AED 15,000 / 3×; contact leakage signals; off-platform award signals; supplier non-response 3% rule; evidence standard before any action | expert |
| 5 | Enforcement ladder with due process: warning → restriction → suspension → ban (ban needs the GC); notice to the party; appeal; record in the audit trail; T&C basis for each step | expert |
| 6 | Dispute-handling path: buyer–supplier disputes, supplier non-response complaints → refund review hand-off (payments/finance), chargeback fraud coordination | expert |
| 7 | Category gates: sensitive categories (fire, security, electrical, structural, gas, lifts …) and the licence each needs (Civil Defence, SIRA, DEWA, municipality); DEWA/SIRA business rules | working |
| 8 | Legal limits: PDPL on profiling and automated decisions (human path), cybercrime law for reporting, law-enforcement request handling (verify, scope, route), no legal conclusions | working |
| 9 | Incident priorities P0–P3 (company rows) and what T&S incidents map to | expert |
| 10 | Scraping/mirroring defence and brand abuse (with IT security) | working |
| 11 | Metrics: flagged-account rate, false-positive rate, time-to-decision, dispute rate, circumvention catches; "activity is not outcome" | expert |
| 12 | Evidence & audit: what an enforcement recommendation must contain so the GC can decide | expert |
| 13 | Live data: fraud cases table, leads/suppliers verification fields, `fn_ws_governance` | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Fraud typologies | expert | partial — 669-char row (undelivered); finance failure modes (card-testing, refund-abuse rings) in finance scope, not legal scope; legal remediation "when a supplier or buyer turns out to be fraudulent" | agent_knowledge profession "Fraud typology catalogue" for this agent + cross-scope the two finance failure modes | 3 pages / 6 chunks | **P1** |
| 2 KYB sources | expert | partial — BR-030, governance_policy 15, senior "Verify supplier legal existence and licence"; **no list of lookup sources** | shared verification-sources reference (GC #19) | 1 page | **P1** |
| 3 Scoring & thresholds | expert | partial — decision_policy fraud_score_max 0.7 and strike limit 3 exist; **no row explains what the score is made of or what happens at 0.7** | `decision_rule` rows citing the keys: score composition, actions per band, borderline review | 2 pages | **P1** |
| 4 Circumvention | expert | **missing** — the AED 15,000 / 3× rule and the non-response 3% rule appear in no ops_knowledge row (0 mentions); retrieval for the query returned the FAQ | `decision_playbook` "Circumvention: signals, evidence, action" citing the published clause, with 3 worked cases | 3 pages | **P1** |
| 5 Enforcement ladder | expert | **missing** — forbidden "banning without the GC" and output_contract `enforcement_recommendation` exist; no ladder, no due-process steps | `decision_playbook` "Enforcement ladder and due process" with the recommendation template | 2 pages | **P1** |
| 6 Dispute path | expert | partial — pack handoff "Supplier non-response complaint and refund review — hand-off" (payments_revenue → finance); SOP Customer Legal Complaint (legal) | one SOP joining the three (T&S → payments → finance → founder) | 1 page | P2 |
| 7 Category gates | working | partial — business_rules ×4, sensitive_categories key; no licence-per-category table | shared category-gates reference (compliance #7) | 2 pages | P2 |
| 8 Legal limits | working | present in legal senior rows (automated decisions need a human path; law-enforcement requests remediation) | — | — | — |
| 9 Incident priorities | expert | present — company rows P0–P3 | — | — | — |
| 10 Scraping/brand | working | present — remediation "Screen-scraping and competitor mirroring", tool brand_scan | — | — | — |
| 11 Metrics | expert | partial — KPI "Flagged accounts…" in its KPI block (186 chars); no false-positive metric | metric_definition rows | 0.5 page | P3 |
| 12 Evidence & audit | expert | missing — no recommendation template | template in #5 | — | (with #5) |
| 13 Live data | expert | LAYER 3 cut (L2) | fix L2 | — | **P1** (delivery) |
| — Curriculum | — | 0 rows | bind trust_safety@expert, legal_uae@working, pdpl@working, company set@expert, quotesdone_os@working | — | **P1** |
| — Tools/authority | — | no fraud or enforcement tool; `analysis` supervised only | out of this audit's scope (authority), noted | — | — |

**Reasoning gap.** It owns "platform policy application" with two numbers (0.7, 3) and no rule that uses them,
and it owns the enforcement recommendation with no ladder and no template. The company's two signature
commercial rules for its domain — anti-circumvention AED 15,000 / 3× and the 3% non-response rule — are absent
from the knowledge tables it can see.

**P1 count: 7** (fraud catalogue, KYB sources, scoring rules, circumvention playbook, enforcement ladder,
live-state delivery, curriculum binding).

---

## Department summary — legal

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| legal (GC) | 6 | 8 | 2 |
| compliance_mgr | 6 | 7 | 0 |
| moderation_specialist | 6 | 4 | 1 |
| trust_safety_mgr | 7 | 2 | 1 |
| **total** | **25** | **21** | **4** |

Of the 25 P1 rows, 4 are the same delivery defect (L1/L2) counted per agent; 2 are curriculum bindings
(`employee_knowledge` = 0 rows for moderation_specialist and trust_safety_mgr).

**Top 5 ingest items for legal (in order):**

1. **Deliver what exists** — repair the LAYER 2 admission guard and the 19,500-char head cut so the GC's 22
   profession topics, the live governance state, and the deterministic rules (hard gate legal_commitment,
   legal_triggers, founder-reserved keys) reach the prompt; quarantine the 8 trade-route exam auto-fills that
   contaminate LAYER 4 for legal/compliance_mgr/moderation_specialist. Zero pages.
2. **The company's own terms, as knowledge**: ingest the published customer T&Cs, supplier T&Cs, refund policy
   and privacy notice into kb_chunks (own category, e.g. `legal_qd_terms`) and write one ops_knowledge
   `reference` clause map with the four commercial rules (3% reveal; supplier non-response 3%; anti-circumvention
   AED 15,000 / 3×; top-3 report) plus the refund numbers, as `structured_data`. ~15 pages / 40 chunks. Every
   legal agent's central gap is that it cannot quote its own contract.
3. **PDPL operating pack**: processor map with regions and transfer basis; DSAR SOP with steps and clocks;
   breach timeline with the Data Office notification rule (verify timing in the executive regulations);
   retention schedule per data class; written for `compliance_mgr` and shared with the GC. ~10 pages / 25
   chunks.
4. **Trust & Safety decision layer**: fraud typology catalogue; KYB lookup-source list (DET, National Economic
   Register, FTA TRN lookup, UAE PASS, EOCN/UN lists); scoring rules that cite `fraud_score_max` and
   `matching_strike_limit`; circumvention playbook with worked cases; enforcement ladder + recommendation
   template. ~11 pages / 25 chunks. Bind `employee_knowledge` for trust_safety_mgr and moderation_specialist.
5. **Moderation checklist**: UAE identifier taxonomy with regexes, file-hygiene SOP (PDF/DWG/images/xlsx
   metadata), redaction-verification SOP with pass criteria and the `redaction_evidence` template, verdict
   rules (approve/return/reject/block). ~8 pages / 15 chunks. Then the missing UAE statutes into kb_chunks
   under a UAE-statute category (Cybercrime 34/2021, Trademarks 36/2021, Competition 36/2023, Civil Procedure
   42/2022, Consumer Protection exec reg — all "verify present first"; the source-id list was truncated).

**Not measured / boundaries.** Semantic retrieval output (`fn_ops_knowledge_match`, `kb_search`) — needs an
embedding call; per-source chunk counts for the UAE statutes (only source ids were listed, list truncated at ~90
of 462); the content of the 270 V2 pack rows beyond titles; `retention_policy` and `pdpl_requests` rows;
`artifact_review` on the reviewer side; the company's licence type, activity codes and TRN (not in any table
read); whether the asserted 2025/26 Civil Code and the "Federal Authority for AI and Data" exist (two
`agent_knowledge` rows assert them without a source in kb_chunks).
