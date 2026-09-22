# Knowledge audit — Marketplace department (7 agents)

Measured 6 Sep 2026, 02:02–02:40 UTC, read-only against `htdblwldjkcgjvmqkbeh`. No paid model call; the only routine executed per agent was the STABLE 2-argument `fn_agent_context(agent_key, 22000)`. Every number is measured; *derived* = read from a function body, not executed; *verify* = source not opened.

Founder's order (6 Sep 2026): each agent must carry the knowledge of top senior staff in its position and run ~90% of the time without going to the internet, with reasoning to match.

Scope: `org_agents.active and department = 'marketplace'` → **procurement (Marketplace Director), rfq_qualification_mgr, inquiry_router, spec_commercial (Supplier Matching & Dispatch Operator), quote_evaluation, rfq_success, doc_intel_manager**.

The shared findings S-1 (Layer 2 is empty for all 13 agents), S-4 (exam = file recall), S-5 (review chain has no rejections), S-6 (all runs deterministic, model routes 503) are stated in `docs/knowledge_audit/supply.md §0` and hold here identically. Marketplace differs from Supply in one respect: it has a `health_fn` (`fn_ws_marketplace`), so Layer 3 exists — and reads `{"kpis":{"rfqs":0,"hired":0,"active":0,"quotes":0,"avg_value":null,"transactions":0},"rows":[],"kanban":[],"quotes":[]}` (139 chars, pre-launch).

---

## 0. Department-level inventory (what a Marketplace agent can reach)

`fn_dept_scope('marketplace')` = `{doc_intelligence, marketplace, procurement, rfq_intelligence, supplier_knowledge}`.

| Source | Rows | Freshness | What it is | Reach |
|---|---|---|---|---|
| `ops_knowledge` dept_key=`marketplace`, module `marketplace_expert` | **97** | eff. 2026-09-02..04; avg ≈2.6k chars; all embedded, runtime_eligible, `active` | 21 decision_playbook (supply floor of three, bulk/multi-quantity RFQs, buyer intent scoring, capability verification beyond the licence, liquidity-impact triage, cold-start, dispute handling, match preview, match ranking, pricing outlier detection, quote quality scoring rubric, first-response probation signal, reveal-worthiness gate, RFQ intake normalisation, five-gate supplier approval, supplier standing, reveal notifies both parties, the one-question specification prompt, tie-breaking, redispatch, honest no-match) · 27 failure_mode (buyer-side fraud, collusion, cross-category supplier, duplicate/linked accounts, decline-as-signal, review manipulation, concentration risk, the 81-invited/0-registered funnel, the fake supplier, the ghost supplier, mismatched category, bait-and-switch after reveal, off-platform contact request, scope-omission quote, stale quote, two intake lexicons…) · 18 kpi (category margin, dispute rate, fill rate, group-per-class, run-rate vs total, AI cost per RFQ, liquidity, match precision, net revenue after refunds, reveal funnel, category health board, supply-count hygiene, reveal conversion, CAC vs LTV, onboarding funnel, retention, healthy decline, time-to-first-quote) · 10 policy (phone confirms never selects, PDPL in a marketplace, dispute evidence limits, regulated goods, sandbox-first, off-platform leakage, safe demo, supplier tone at reveal, supplier SLA, demo fixture convention) · 8 authority (money follows the chain, category expansion, escalation paths, honesty rule, refunds reach the founder, supplier approval authority, platform-as-channel T&C principle, founder sets boundaries) · 7 reference (taxonomy design, customs/import capability, **pricing benchmarks as a method**, retrieval quality keyword vs semantic, seasonality, UAE trade licence verification decision rule, VAT & pricing hygiene) · 6 remediation | dept arm (v3 slice, cosine match, and — because dept_key = the literal `marketplace` — also the Layer 2c keyword search) |
| `ops_knowledge` dept_key=`marketplace`, module `org_task_lane` | 8 | 2026-09-04 | the event→lane playbooks every run matched this week | dept arm |
| `ops_knowledge` dept_key=`procurement` (legacy Company Operations pack) | 558 | eff. 2026-07-31; 296 implemented / 140 partial / 122 target_state | 60 knowledge_domain topics (Boq Analysis/Extraction, Cad And Drawing Handling, Commercial/Technical Normalization, Confidence Scoring, Contact-Detail Redaction, Deviation Detection, Document Classification/Validation, Drawing Analysis, Duplicate Dispatch Prevention, Fan-Out Rules, Inquiry Routing/Scoring, Intent Classification, Legitimacy Checks, Mandatory Fields, Multi-Category Splitting, OCR, Pdf/Quotation Extraction, Quote Completeness/Lifecycle, Reveal Workflow, Rfq Qualification, Structured Brief Generation, Supplier Eligibility/Matching/Ranking, Top-Three Recommendation…) avg 2.4k chars · 60 data_and_evidence · 59 operational_application · 59 control_requirements · 33 live_data_binding · 30 SOP (File Intake, New Inquiry Intake, Supplier Matching, Intent And Category Routing, Follow-Up Question Sequencing, Boq Extraction, Drawing And Boq Analysis, Comparison And Scoring, Identity Redaction, Completeness Gate, Top-Three Recommendation, Award And Reveal, Multi-Trade Split, Supplier-Safe Package Generation, Coverage-Gap Escalation, Dispatch Eligibility…) · 30 decision_rule (the generic "rule 01–10" template × 3 sub-departments) · 30 exception_playbook · 66 yaml / 24 md pack files | dept arm (NOT the 2c keyword search) |
| `ops_knowledge` dept_key ∈ {doc_intelligence 132, rfq_intelligence 134, supplier_knowledge 136} | 402 | none on 372 | V2 pack yaml/md/json + failure_mode_case | dept arm |
| role-scoped (packaged roles) | 25–26 per role | none | pack files, avg ≈2.8k | role arm |
| `ops_knowledge` scope_type=`category` | 1,204 = 86 × 14 | none | V2/V3 packs per category, keyed `NNN_slug`: 01_EXPERT_QUALIFICATION_STRATEGY_V3.md (mandatory + route-specific fields with "why"), 02_FIELD_AND_QUESTION_BANK_V2.yaml, 02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml (ask order, stop rule, never_infer), 03_QUOTE_READINESS_AND_COMPARISON_V2.yaml, quote_comparison_contract.yaml, rfq_quality_gate.yaml, 06_RESEARCH_AND_ESCALATION_POLICY.yaml, retrieval_policy.yaml, specialist_manifest.yaml, source_route_manifest.json… | only through `p_category_key`; the 3-arg `fn_agent_context` passes NULL and `fn_ops_knowledge_match` has no category arm → *derived*: **unreachable at runtime**; they surface only as exam gap-fills in Layer 4 |
| `kb_chunks` per catalog category | 2,760 across 86 | most newest 2026-08-16 | 15 "QuotesDone trade knowledge" sections per category (Products & Services, Technical Knowledge, UAE Regulations & Authorities, Commercial & Pricing, Quotation Knowledge, Inquiry Qualification Logic, Documents Knowledge, Supplier Knowledge, Risk Assessment…) + web-researched docs; UAE-authority mention counts in `supply.md §0.1` | `kb_search` (RRF; functional staff get relevance-ranked, category-agnostic) |
| `kb_chunks` field corpus reachable by v3 `field_corpus` (`category = any(scope)`) | `procurement` **33,736** chunks (newest 2026-08-31) | | UNCITRAL Model Law & Guide (2,428), Philippines RA 9184 IRR (1,173), ADB IT procurement guide (880), UNCITRAL PPP guide (832), World Bank SBD Plant (820), SCOR 11 (740), UNOPS manual (600), UN Practitioner's Handbook (586), India GoI manuals (1,091), World Bank PPP guide (557), UNFPA (541)… — **international public-sector procurement, not UAE private B2B** | only when a task query is supplied |
| `kb_chunks` other field corpora (not in scope arms; reachable only by `kb_search` ranking) | e.g. construction-civil 51,688 (USACE EM, FEMA P-751, NIST, USDA Wood Handbook, QD-KB-001 pack 3,427), firefighting 36,275 (NFPA 1/101/13/72/99 editions 2005–2013, QD-KB-006 1,629), mep 27,466, legal 34,355 (UAE Civil Code 398, CCL 199, Labour Law 118), finance 53,718 (VAT Exec Reg 163, CT law 158) | 2026-08-28..31 | US codes and international references; UAE law only in legal/finance | `kb_search` |
| `qualification_playbooks` | 29 active, 10 questions each, with decision notes (e.g. "food establishment → DM food-safety + grease-duct certificate") | Jul 2026 | **old taxonomy slugs; 0 of 29 match a catalog slug** | — |
| `category_specs` | 56 (21 with supplier_requirements + compliance_checklist naming DCD/DM) | 2026-07-28 | old slugs, 0 match catalog | — |
| `category_quote_specs` | 141 mandatory/optional aspects across ≈30 spec groups (glazing, security, fire, hvac, electrical, joinery, plumbing…) | — | | used by completeness (*not traced*) |
| `category_keyword` 1,839 · `catalog_subcategories` 470 · `kb_category_aliases` 12 · `category_route_map` 16 · `category_licence_activity` 20 | | | routing data | code |
| `decision_policy` thresholds | 20 keys | | `match_relevance_floor` 35 · `match_max_fanout` 5 · `match_max_fanout_per_trade` 3 · `matching_strike_limit` 3 · `confidence_min` 0.6 · `fraud_score_max` 0.7 · score weights product 40 / brand 20 / project type 15 / size fit 10 / track record 15 · `sensitive_categories` [fire, security, electrical, structural, gas, lifts, medical] · `use_capability_matching` true · `auto_action_max_aed` 0 · `financial_review_aed` 10,000 · `refund_notify_after_working_days` 1 · `refund_call_after_working_days` 3 · `refund_admin_fee_aed` 250 · `refund_reveal_fee_pct` 3 · `legal_triggers` list | **not read by `fn_agent_context`** (derived): the agents act inside these numbers without seeing them |
| Deterministic code (read) | `route_inquiry` (completeness pre-gate → taxonomy prefilter via taxonomy_trade / lead_trade_map / subcategory_agent_map → `fn_match_capability` at floor 35 → model adjudicator, 503 → deterministic shortlist served) · `quote_compare/deterministic.ts` (per quote: price 1–5 span score, delivery 1–5, quality 1–5 from completeness ≥85/70/50/30 + itemised+warranty bump; composite **0.4 price + 0.4 quality + 0.2 delivery**; top-3; flags: expired, lump sum, no warranty / lead time / payment terms, failed completeness, missing mandatory fields; `includes`, `missing_from_request`, `spec_deviation` always empty; **no technical-compliance or VAT dimension**) · `dispatch_inquiry` · `inquiry_ai` (qualify) · `doc_extract`, `license_extract`, `doc_render` | | | |
| Measured competence signals | `kb_operational_route_test`: **344/344** `last_result.action = expected_action` (Arabic alias suite, last run 2026-09-06 02:05) · `match_eval` 2026-09-03: "precision 100%, recall 100% across 5 RFQs" (fixture; 1 error on 2026-08-10 seeding) · `route_inquiry` 32 ok / 30d, every one "adjudicator unavailable (503) → deterministic shortlist" · `quote_compare` 15 ok (all "every model attempt failed → DETERMINISTIC") + 8 error (fixture inquiry missing) · inquiries **0**, quotes **0**, inquiry_matches **0** — no real routing, matching or comparison has happened | | | |

---

## 1. `procurement` — Marketplace Director (Head of Marketplace Operations)

**What it does today.** Director, reports `ceo`, `scheduled_manager`, execute_medium, budget AED 10,000; personal authority: all 8 marketplace action classes **gated** (≤10,000). Runs/7d: **4** (`ok`, lane determinations, "executor none"). Exam: **30% (6/20; 0 partial, 8 wrong, 6 not covered)**, latest 3/5; `canon_eval_runs` 2026-08-03: 6/6. Retrievals/30d: **30**. review_chain: 341 authored (216 approve), **371 reviewed** (approve/owned only). KPIs: "primary objective 80%" NULL; "RFQ completion rate 80%" NULL. Packaged roles: marketplace-operations-director + document-intelligence-analyst-controller; readiness `tools_connected`.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **6** (4,982 chars) | 2026-07-24 | Role (15+ yrs two-sided marketplaces; owns intake→match→quote→reveal; 70+ completeness, floor + capped fanout, 70/100 quote gate; works within `decision_policy` weights, never silently changes them) · Quote fraud & collusion doctrine (price rings, multi-account, lowball-then-revise, bid suppression, off-platform push, fake RFQs; ladder: fraud_flags → hold → notify → ban founder-gated) · Marketplace quality SLAs (TTFQ ≤24 working h; ≥3 passing quotes; pass rate ≥60%; gate 70+; coverage ≥1 eligible for 95%) · Category expansion criteria (4 gates: demand, supply density, regulatory readiness naming SIRA/DCD/DEWA, knowledge readiness) · Supply-demand balancing (same-day coverage signal; seasonality; monthly balance report) · Matching fairness & rotation (rotate near-equal scores; concentration flag; sensitive categories weight approvals over rotation; log deviations) |
| agent_knowledge experience | 16 | 2026-09-05 | 6 real org lessons (fraud monitoring from day one; category-readiness matrix; instrument the funnel; 'Start invites' returning 0; alerting; density-gap → campaigns) + 10 exam gap-fills |
| employee_knowledge | 14 (5/12 layers) | — | procurement, supplier_mgmt, uae_authorities expert; company ×5; 4 awareness; os, communication working |
| ops_knowledge reachable | marketplace 105 + procurement 558 + doc/rfq/supplier_knowledge 402 + role 52 | | see §0 |
| fn_agent_context | 27,314 chars | live | Layer 2 empty (S-1); employee record 1,470 chars; authority 410; Layer 1 15 items 8,496; Layer 3 zeros; Layer 4 1 item |

**Senior-staff standard — Head of Marketplace Operations, UAE B2B RFQ marketplace**

| # | Domain | Depth |
|---|---|---|
| 1 | The core loop's gates with their numbers (completeness 70, relevance floor 35, fanout 5/3, quote pass 70/100, strike 3, confidence 0.6, fraud 0.7, sensitive categories, score weights) | expert |
| 2 | RFQ qualification standard per category (mandatory fields, never-infer, minimum-sufficient policy) | expert |
| 3 | UAE pricing benchmarks for the main trades (fit-out AED/sqm by grade; HVAC AED/TR; electrical AED/point; waterproofing, flooring, gypsum AED/sqm; manpower day rates; typical supplier margins; VAT 5%) | expert |
| 4 | Quote comparison rules (normalisation, best-3, technical vs commercial scoring, VAT-inclusive basis, validity, exclusions) | expert |
| 5 | Fairness and anti-circumvention (AED 15k / 3× rule; off-platform leakage detection; rotation; concentration) | expert |
| 6 | Fraud patterns and the response ladder | expert |
| 7 | SLA management (TTFQ, passing quotes, coverage) and breach diagnosis by stage | expert |
| 8 | Reveal economics and refund policy (3% fee; notify after 1 working day; call after 3; admin fee 250; founder-only refunds; net revenue after refunds) | expert |
| 9 | Taxonomy governance (86 categories, 470 subcategories, aliases, expansion/closure gates) | expert |
| 10 | What "verified supplier" means (licence activity, regulated approvals, capability confirmed vs derived) | working |
| 11 | UAE regulatory map per trade (DCD, SIRA, DM, DEWA/ADDC, MOIAT/ECAS, RTA, DHA/DoH) | working |
| 12 | Document-intelligence expectations (BOQ/drawing/spec extraction targets) | working |
| 13 | Marketplace metrics literacy (fill rate, match precision, reveal conversion, run-rate vs total, group per class) | expert |
| 14 | Dispute handling after reveal | working |
| 15 | Seasonality and demand rhythm (Ramadan, Q4, summer) | working |
| 16 | Escalation boundaries (refunds founder; bans founder-gated; no self-approval; no identity outside policy) | expert |
| 17 | Worked end-to-end RFQ cases per top category with the decisions taken | expert |
| 18 | Competitive benchmarks (what buyers get elsewhere; fee models) | aware |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) — 6 substantive rows, 0 in the prompt | Layer 2 budget fix in `fn_agent_context` | 1 SQL | **P1** |
| 1 Gates with numbers | expert | **partial** — rows name 70/floor/cap/70-100 qualitatively; the 20 `decision_policy` values are in no context and no knowledge record | `ops_knowledge` policy record (dept marketplace, `deterministic=true`, layer `policy`) generated from `decision_policy` on every change; it then enters Layer 2f automatically | 1.5k | **P1** |
| 3 UAE pricing benchmarks | expert | **missing** — "Pricing benchmarks" reference is method only; `category_price_stats` has no data (0 quotes); the 15 "Commercial & Pricing" trade chunks per category are narrative (*verify* whether they carry AED ranges — not opened) | `kb_chunks` category `pricing-benchmarks-uae` + one reference record per trade family: AED range per unit per spec bucket, with source and date (cost consultants' published indices, e.g. Turner & Townsend / Colliers / RICS UAE indices *verify*; supplier price lists in the lead pool) | 20 trades × 1.5k = 30k | **P1** |
| 2 Qualification standard per category | expert | **partial** — 86 × 14 pack records exist and are unreachable at runtime (derived); 29 old-slug playbooks | Make the category arm live: pass `p_category_key` (the routed `NNN_slug`) from `inquiry_ai`/`route_inquiry` into `fn_agent_context_v3`, or re-key the 1,204 records to catalog slugs and add them to `fn_ops_knowledge_match` | code + 0 text | **P1** |
| 5 Anti-circumvention | expert | **partial** — rotation row + "Off-platform leakage" policy; the AED 15k / 3× rule is not in any marketplace row (it is in Layer 1 "Penalty & collections model" *verify*) | authority record quoting the T&C clause and the detection signals (contact-detail leakage, supplier decline patterns, post-reveal silence) | 1.5k | P2 |
| 4 Quote comparison rules | expert | **partial** — quote_evaluation's row + deterministic 0.4/0.4/0.2; no technical dimension, no VAT rule | see quote_evaluation rows 2–3 | — | P2 |
| 17 Worked cases | expert | **missing** | 10 end-to-end ZZ DEMO cases (intake → route → dispatch → quotes → comparison → reveal) with the decision at each gate and why | 15k | P2 |
| 10 Verified supplier meaning | working | **partial** — "UAE trade license verification" + "five-gate approval" references reachable; derived-vs-confirmed capability (15,306 vs 1) explained nowhere | 1 reference record on capability states | 1k | P2 |
| 11 Regulatory map | working | **partial** — category chunks; 21 old-slug checklists | reference: authority × category matrix for the 86 | 6k | P2 |
| 12 Doc-intel expectations | working | **partial** (doc_intel KPIs visible in v3 identity; nothing narrative) | covered by doc_intel_manager rows | — | P3 |
| 18 Competitive benchmarks | aware | **missing** | reference 1.5k | 1.5k | P3 |
| 6, 7, 8, 9, 13, 14, 15, 16 | — | **present** (rows + dept-scoped records + Layer 1 pricing/canon) | — | — | — |

**Reasoning gap.** This is the richest agent in scope: six real doctrine rows, 97 senior-operator records in its dept scope (decision playbooks with explicit reasoning discipline, failure modes, KPI literacy). What it lacks is *numbers* — no threshold values, no price ranges, no worked cases — and none of its own rows reach the prompt. Exam 30% with 8 wrong (file recall). **P1 = 4.**

---

## 2. `rfq_qualification_mgr` — RFQ Qualification Manager

**What it does today.** Specialist, reports `procurement`, event_driven_operator, execute_low ≤1,000; `qualify_inquiry`, `compare_quotes`, `supplier_verify` autonomous, rest advisory. Runs/7d: **2** (`ok`, lane determinations). Exam: **30% (6/20; 7 wrong)**, latest 3/5. Retrievals/30d: **3** (last 2026-08-11). KPI "primary objective 80%" NULL. Packaged roles: rfq-inquiry-intelligence director + reviewer-auditor; readiness `tools_connected`. Owns: inquiry completeness ("no RFQ reaches suppliers without the mandatory fields for its category"); executor `inquiry_ai`.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (699 chars, priority 74) | 2026-08-06 | "Qualifying an RFQ before it costs supplier goodwill": ready = category, emirate, scope/BoQ, quantity, timeline, access constraints, internally consistent, and the category has approved suppliers; reject/return: budget an order of magnitude off the median, cross-category scope with no split, impossible timelines, regulated activity without licensed suppliers |
| agent_knowledge experience | 9 | 2026-09-05 | gap-fills incl. "Telecommunication Companies — Expert Qualification Strategy V3" (the one category pack it holds), one-confirmed-supplier bottleneck, buyer intent scoring, pricing outlier detection, intake normalisation, a failed handoff |
| employee_knowledge | 14 (5/12) | — | as procurement |
| ops_knowledge reachable | marketplace 105 (incl. "RFQ intake normalization", "Buyer intent scoring", "The RFQ specification prompt", "Bulk and multi-quantity RFQs") + procurement 558 (Mandatory Fields, Conditional Questions, Missing-Information Detection, Multi-Category Splitting, Completion Confidence, SOP 03 Follow-Up Question Sequencing, SOP 07 Completeness Gate) + rfq_intelligence 134 + role 52 | | |
| fn_agent_context | 27,250 chars | live | Layer 2 empty; Layer 1 15 items 9,456; Layer 4 = the Telecommunication V3 strategy (3,384 chars) |

**Senior-staff standard — RFQ qualification lead, UAE construction/industrial/services**

| # | Domain | Depth |
|---|---|---|
| 1 | Per-category mandatory fields and never-infer rules for all 86 categories | expert |
| 2 | BOQ reading: units (m, m², m³, nr, kg, LS, item), measurement bases (CESMM4, POMI, NRM2), provisional/prime-cost sums, rate vs amount checks | expert |
| 3 | Drawings and specifications: title blocks, revisions, MEP schedules, spec sections (CSI MasterFormat / UAE consultant conventions), approved-equal clauses | working |
| 4 | Completeness scoring (how the 70 gate is computed by `inquiry_ai`; which fields weigh what) | expert |
| 5 | Question strategy (minimum sufficient; one discriminating clarification; ask order; stop rule) | expert |
| 6 | Budget sanity against category medians | expert |
| 7 | Multi-trade split rules and per-trade fanout (3) | expert |
| 8 | Regulated-activity flags (which RFQs need DCD/SIRA/DEWA-licensed suppliers; `sensitive_categories`) | expert |
| 9 | Buyer intent scoring (serious vs tire-kicker; intelligence harvesting) | working |
| 10 | Buyer-identity redaction in the supplier brief (SOP 06) | expert |
| 11 | UAE timeline feasibility (working days, NOC/permit lead times, Ramadan hours, summer midday ban) | working |
| 12 | Site/access constraints that change price (DM permits, NOCs, high-rise logistics, free-zone gate passes, working hours) | working |
| 13 | Arabic-language inquiries | working |
| 14 | Boundaries (never dispatch; never confirm a supplier; never infer outside the category rules) | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 fix | 1 SQL | **P1** |
| 1 Per-category field sets | expert | **partial** — 86 V3 strategies + question banks + minimum-sufficient policies exist (1,204 records) and are unreachable (derived); the agent's Layer 4 happens to hold Telecommunication's | wire `p_category_key` (see procurement row 2) | code | **P1** |
| 4 Completeness scoring | expert | **partial** — Layer 1 "RFQ completeness rule" (470 chars) states the gate; the scoring rule inside `inquiry_ai` is not a knowledge record (*not traced* in this audit) | policy record (deterministic) generated from the scoring code: field weights, the 70 threshold, what `needs_detail` means | 1.5k | **P1** |
| 2 BOQ reading | expert | **missing** — legacy "Boq Analysis / Boq Extraction — operating knowledge" (≈2.4k, generic, eff. 31 Jul); no units/measurement-basis/arithmetic knowledge | reference records: BOQ anatomy (CESMM4/POMI/NRM2 basics, UAE consultant conventions), unit dictionary, arithmetic and rate-sanity checks, provisional sums (*verify* against the standards' own summaries) | 6k | **P1** |
| 6 Budget sanity | expert | **missing** — no category medians (0 quotes); the row says "order of magnitude off the median" | the pricing-benchmark book (procurement row 3) | shared | P2 |
| 3 Drawings & specs | working | **missing** — "Cad And Drawing Handling", "Drawing Analysis" legacy topics only | reference: reading drawings/spec sections for qualification (what to extract, what to ask) | 3k | P2 |
| 8 Regulated flags | expert | **partial** — `sensitive_categories` list not in context; catalog `regulated` flag | include in the thresholds policy record + authority×category matrix | shared | P2 |
| 11 UAE timeline feasibility | working | **missing** | reference: UAE working calendar, permit lead times by authority, seasonal constraints | 2k | P2 |
| 12 Site/access constraints | working | **missing** | reference: constraint checklist by site type (villa, tower, mall, free zone, industrial) | 2k | P2 |
| 10 Redaction | expert | **partial** — legacy SOP 06 + "Contact-Detail Redaction" topic (semantic reach only) | promote to a marketplace policy record with the exact rules (what is redacted, what a site address reveals) | 1k | P2 |
| 13 Arabic | working | **partial** — 344 Arabic route tests pass; no knowledge record | glossary record (Arabic ↔ English trade terms, 200 entries) | 3k | P3 |
| 5, 7, 9, 14 | — | **present** (dept-scoped playbooks + row + role) | — | — | — |

**Reasoning gap.** One 699-char row with real decision rules (reject conditions) plus strong dept-scoped playbooks; the category-level standard it is supposed to enforce exists 86 times over and reaches it once by accident. No numbers (medians, weights), no BOQ literacy, no worked example. **P1 = 4.**

---

## 3. `inquiry_router` — Inquiry Router

**What it does today.** Specialist, reports `procurement`, event_driven_operator, execute_low (`analysis` supervised). Runs/7d: **3** (`ok`, lane determinations). Exam: **35% (7/20)**, latest 4/5. Retrievals/30d: **0**. KPI "inquiries routed without escalation 90%" NULL. employee_knowledge **0/12**. Packaged role: rfq-inquiry-intelligence operations specialist (26); readiness `tools_connected`. Executor `route_inquiry`. Measured routing: `kb_operational_route_test` **344/344** action matches (Arabic alias suite, 2026-09-06); `route_inquiry` 32 ok/30d on the deterministic shortlist (adjudicator 503); 0 real inquiries.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (658 chars, priority 5) | 2026-08-11 | routing has a cost both ways; recognise the trade from the buyer's words ("false ceiling" → gypsum, "chiller" → HVAC, "cladding" → facade or ACP signage by context); split multi-trade; two roughly-equal categories = a clarifying question; unroutable = escalate with reason |
| agent_knowledge experience | 6 | 2026-09-04 | gap-fills (healthy decline, buyer intent, a qualification playbook, run-rate vs total, a comparison contract, a remediation file) |
| employee_knowledge | 0 | — | nothing bound |
| ops_knowledge reachable | marketplace 105 ("The mismatched category", "When two intake paths disagree", "Category taxonomy design") + procurement 558 (Inquiry Routing, Intent Classification, Multi-Category Splitting, Subcategory Aliases, SOP 02 Intent And Category Routing, SOP 08 Multi-Trade Split) + supplier_knowledge 136 + role 26 | | |
| routing data | `category_keyword` 1,839 patterns · `catalog_subcategories` 470 · `kb_category_aliases` 12 · `category_route_map` 16 · `taxonomy_trade`/`lead_trade_map`/`subcategory_agent_map` (used by code; not counted) | | data, not knowledge |
| fn_agent_context | 27,347 chars | live | Layer 2 empty; Layer 4 2 items + a Modular & Prefab qualification playbook |

**Senior-staff standard — routing / classification specialist**

| # | Domain | Depth |
|---|---|---|
| 1 | The full taxonomy (86 × 470) with UAE buyer vocabulary in English, Arabic and site-speak ("false ceiling", "MEP", "civil works", "ACP", "kitchen cabinets" vs joinery, "chiller", "AC servicing" vs "HVAC contractor") | expert |
| 2 | Multi-trade detection and split rules | expert |
| 3 | Ambiguity policy (one clarifying question; never nearest-thing) | expert |
| 4 | Regulated routing (sensitive categories → licensed pools only) | working |
| 5 | Confidence thresholds and fallbacks (`confidence_min` 0.6; adjudicator unavailable → deterministic shortlist; what the shortlist is) | expert |
| 6 | The route test suite and how to add a case (`kb_operational_route_test`, 344 cases) | working |
| 7 | Emirate/location normalisation (7 emirates, free zones, areas, "Dubai" meaning) | working |
| 8 | Arabic conventions (dialect terms, transliterations) | working |
| 9 | Off-catalog handling (escalate with reason; `v_llm_identity_route_offcatalog`) | expert |
| 10 | Taxonomy change process (never invent a category) | expert |
| 11 | Worked examples: 50 hard routings with the decision | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 fix | 1 SQL | **P1** |
| 1 Taxonomy + buyer vocabulary | expert | **partial** — 3 examples in the row; 1,839 keyword patterns and 470 subcategories exist as data the model never sees as text | reference record per category family (≈12): category → subcategories → buyer phrases (EN/AR) → confusable neighbours, generated from `category_keyword` + `catalog_subcategories` + `kb_category_aliases` | 12 × 2k | **P1** |
| 5 Thresholds & fallbacks | expert | **missing** — `confidence_min` 0.6 and the 503→deterministic behaviour are in code and `decision_policy` only | thresholds policy record (shared) + a 1k record describing `route_inquiry`'s stages (completeness pre-gate, taxonomy prefilter, capability retrieve at floor 35, adjudicator) | 1k | **P1** |
| 11 Worked examples | expert | **missing** | 50 hard routings: the 344 route-test inputs with expected action are a ready seed; add 50 multi-trade / ambiguous cases with the decision and the clarifying question | 8k | P2 |
| 6 Route test suite | working | **missing** as knowledge | SOP record: how a routing defect becomes a test row | 0.8k | P3 |
| 7 Location normalisation | working | **missing** | reference: emirates, free zones, common areas, service-radius conventions | 1.5k | P2 |
| 8 Arabic conventions | working | **partial** — tests pass; no glossary | shared glossary (rfq_qualification_mgr row 13) | shared | P3 |
| 4 Regulated routing | working | **partial** — `sensitive_categories` not in context | shared thresholds record | shared | P2 |
| 2, 3, 9, 10 | expert | **present** (row + role forbidden decisions + dept records) | — | — | — |

**Reasoning gap.** The row states the right policy (clarify, split, escalate) in prose; the deterministic router is measured 344/344 on aliases, but the agent that supervises it cannot name the taxonomy it routes into, its own confidence threshold, or what the fallback shortlist is. Nothing bound in `employee_knowledge`. **P1 = 3.**

---

## 4. `spec_commercial` — Supplier Matching & Dispatch Operator (role: Commercial Services Specialist)

**What it does today.** Specialist, reports `procurement`, event_driven_operator, `routine_employee_reasoning`, execute_low (threshold 0); `compare_quotes`, `qualify_inquiry`, `supplier_verify` autonomous; `match_inquiry`, `invite`, `route_category`, `capability_enrich`, `supplier_approve_clean` advisory. Runs/7d: **7** (`ok`, lane determinations). Exam: **25% (5/20; 8 partial)**, latest 2/5. Retrievals/30d: **12**. KPIs: five "primary objective 80%" rows (Commercial Services, Construction & Civil, Industrial & Energy, Interior & Fit-Out, MEP specialists — the merged personas), all NULL. employee_knowledge 24 (10 `cat:*` service categories at expert + procurement/supplier_mgmt/uae_authorities). Packaged role: marketplace-operations operations specialist; readiness **blocked**. Runtime: `dispatch_inquiry` 17 ok + 17 info ("supplier brief frozen for dispatch") /30d; `fn_match_capability` with floor 35, fanout 5/3, weights 40/20/15/10/15; eligible pool = 1 approved supplier; capabilities 15,306 derived / 1 confirmed.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (741 chars, priority 74) | 2026-08-06 | "Commercial services procurement in the UAE": comparable unit = cost per visit / man-hour at stated coverage; establish site count, frequency, consumables, supervision, replacement cover, minimum term; manpower must be licensed and visa sponsorship sits with the supplier; mobilisation (passes, inductions, clearances); a site address is a disclosure |
| agent_knowledge experience | 6 | 2026-09-04 | gap-fills: off-platform leakage, refunds reach the founder, bulk/multi-quantity RFQs, an rfq_quality_gate file, "Measured automation", a research policy |
| employee_knowledge | 24 | — | `cat:` accounting, cleaning, FM, HR/recruitment, IT services, law firms, logistics, management consulting, marketing agencies, security — expert; functional set as procurement |
| ops_knowledge reachable | marketplace 105 ("Match ranking", "When to redispatch", "Supplier standing", "Reading a supplier's decline") + procurement 558 (Supplier Eligibility/Matching/Ranking, Fan-Out Rules, Duplicate Dispatch Prevention, SOP 01 Supplier Matching, SOP 02 Inquiry Dispatch, SOP 09 Supplier-Safe Package Generation, SOP 10 Dispatch Eligibility) + role 26 | | |
| fn_agent_context | 27,265 chars | live | Layer 2 empty; KPI block 605 chars (5 null objectives); Layer 4 4 items |

**Senior-staff standard — dispatch/matching operator + merged category bench (commercial, construction/civil, industrial/energy, fit-out, MEP)**

| # | Domain | Depth |
|---|---|---|
| 1 | Matching rules with numbers (floor 35; fanout 5, per-trade 3; weights product 40 / brand 20 / project type 15 / size fit 10 / track record 15; strike 3; sensitive categories) | expert |
| 2 | Eligibility predicates (approved ∧ verified, licence unexpired, capability confirmed vs derived, emirate coverage, exclusions, availability, not banned, not struck out) | expert |
| 3 | Fairness/rotation and concentration logging | expert |
| 4 | Idempotent assignment; exactly one notification per supplier; recorded reason per selection and exclusion | expert |
| 5 | Category expertise for the 10 service categories and the 4 merged trade families: units of comparison, licensing, typical scopes and gotchas | expert |
| 6 | Supplier-safe brief (redaction; anonymity; address as disclosure) | expert |
| 7 | Redispatch rules (no supply, weak field) | expert |
| 8 | Refusal conditions (any gate fails → refuse; never bypass qualification or supplier-safe review) | expert |
| 9 | Notification channel rules (WhatsApp template status, email, `demo_rehearsal_active` hold) | working |
| 10 | UAE mobilisation realities (gate passes, inductions, security clearance, visa sponsorship) | working |
| 11 | Manpower licensing (MoHRE labour-supply licence; Tadbeer for domestic) | working |
| 12 | Worked dispatch examples (selection + exclusion reasons) | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 fix | 1 SQL | **P1** |
| 1 Matching numbers | expert | **missing** — none of floor/fanout/weights/strike appear in any knowledge row or context; the row is about commercial-service units | thresholds policy record (shared; deterministic) | shared | **P1** |
| 2 Eligibility predicates | expert | **partial** — role responsibilities list the rule names; the predicates as built (`fn_match_capability`, `v_supplier_match_exclusions`) are not a record; derived-vs-confirmed capability unexplained | policy record generated from `fn_match_capability` + `v_supplier_match_exclusions` bodies | 2k | **P1** |
| 5 Category bench expertise | expert | **partial** — 1 row on commercial services; the 4 merged trade personas have no row; 15 trade chunks per category reachable by `kb_search`; the category packs are unreachable | 4 profession rows (construction/civil, industrial/energy, fit-out, MEP): comparable units, licensing, scope gotchas, regulated approvals — sourced from the existing trade chunks and the V3 packs | 4 × 1.5k | **P1** |
| 3 Fairness/rotation | expert | **partial** — procurement's row holds the doctrine; spec_commercial's Layer 2 has its own row so the dept-peer fallback never triggers | copy procurement's "Matching fairness & rotation policy" row to spec_commercial | 0.9k | P2 |
| 12 Worked dispatch examples | expert | **missing** | 10 ZZ DEMO dispatches with the ranked list, each exclusion reason, and the notification produced | 6k | P2 |
| 9 Channel rules | working | **partial** — `demo_rehearsal_active` hold and template approval state are policy/data, not knowledge | policy record: which channel, which template, when held | 0.8k | P2 |
| 11 Manpower licensing | working | **partial** (one clause) | reference: MoHRE labour-supply licence, Tadbeer, free-zone labour rules | 1k | P3 |
| 4, 6, 7, 8, 10 | expert | **present** (role responsibilities, row, dept-scoped playbooks) | — | — | — |

**Reasoning gap.** The role contract is the most explicit in the estate (record every selection and exclusion, refuse on any gate failure), but the operator carries none of the numbers the deterministic matcher uses and has one profession row for one of its five personas. Readiness `blocked`. **P1 = 4.**

---

## 5. `quote_evaluation` — Quote Evaluation Specialist

**What it does today.** Specialist, reports `procurement`, event_driven_operator, execute_low (threshold 0); `compare_quotes`, `qualify_inquiry`, `supplier_verify` autonomous. Runs/7d: **2** (`ok`, lane determinations). Exam: **30% (6/20)**, latest 3/5. Retrievals/30d: **5** (last 2026-08-15). KPI "primary objective 80%" NULL. Packaged role: marketplace-operations analyst-controller; readiness `tools_connected`. Executor `quote_compare`: 15 ok / 8 error in 30d, every ok run on the deterministic fallback; 0 real quotes.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (737 chars, priority 74) | 2026-08-06 | normalise before comparing: scope inclusions/exclusions, quantities/units, brand or spec equivalence, lead time, validity, payment terms, warranty, who carries site access/lifting/disposal/making good; a quote missing any is incomplete, not cheaper; three distortions (low headline + exclusions, spec substitution, lead time assuming stock); surface the unstated |
| agent_knowledge experience | 8 | 2026-09-05 | gap-fills: escalation paths, supplier tone at reveal, run-rate vs total, the 81-invited funnel, retention, 03_HARD_GATES.json, a field bank, a remediation file |
| employee_knowledge | 14 (5/12) | — | as procurement |
| ops_knowledge reachable | marketplace 105 ("Quote quality scoring rubric", "Reveal-worthiness gate", "Tie-breaking near-equal quotes", "Match ranking", "Pricing outlier detection", "Pricing benchmarks (method)", "VAT and pricing hygiene", failure modes "scope-omission quote", "stale quote", "bait-and-switch") + procurement 558 (Commercial/Technical Normalization, Quote Completeness, Quotation Extraction, Top-Three Recommendation, Deviation Detection, SOP 06 Comparison And Scoring, SOP 07 Top-Three Recommendation) + role 26 | | |
| deterministic code | `quote_compare/deterministic.ts`: composite 0.4 price + 0.4 quality + 0.2 delivery, top-3, flags; no technical, no VAT, `spec_deviation` always empty | | |
| fn_agent_context | 27,240 chars | live | Layer 2 empty; Layer 1 15 items 9,456 |

**Senior-staff standard — quote evaluation / tender analyst, UAE**

| # | Domain | Depth |
|---|---|---|
| 1 | Normalisation rules (scope, qty/units, brand equivalence, lead time, validity, payment terms, warranty, site access/lifting/disposal/making good) | expert |
| 2 | Technical-compliance scoring (spec conformance, approved-equal, deviations, submittals) separated from commercial scoring, with category weightings | expert |
| 3 | UAE commercial conventions (5% VAT inclusive/exclusive; retention 5–10%; advance 10–30%; 30-day validity norm; delivery basis; LPO terms; AED only) | expert |
| 4 | Price sanity bands per category × spec bucket; outlier investigation | expert |
| 5 | Best-3 rule and the reveal-worthiness absolute bar | expert |
| 6 | Scope-omission, bait and stale quotes | expert |
| 7 | Buyer-facing comparison report contract (what is shown pre-reveal; no identity leakage; the per-category `quote_comparison_contract`) | expert |
| 8 | Tie-breaking rules | expert |
| 9 | Product/standards references a quote must carry (DCD/DM certificates, MOIAT/ECAS conformity, ESMA labels) | working |
| 10 | BOQ-based quotes: rate × qty arithmetic, unit mismatch, missing lines | expert |
| 11 | Boundaries (never choose the winner; never change a price; never reveal) | expert |
| 12 | Worked examples (3 quotes × 5 categories) | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 fix | 1 SQL | **P1** |
| 2 Technical vs commercial scoring | expert | **partial** — the deterministic comparer has no technical dimension (`spec_deviation` empty); `category_quote_specs` (141 aspects, ≈30 groups) exist as data; "Quote quality scoring rubric" record is prose | decision_playbook (deterministic): per spec group the mandatory aspects, how conformance is scored, how it combines with the 0.4/0.4/0.2 composite — generated from `category_quote_specs` | 4k + code | **P1** |
| 3 UAE commercial conventions | expert | **missing** — "VAT and pricing hygiene" reference exists (reachable) but the code does not normalise VAT and no record states retention/advance/validity norms | reference record (dept marketplace): UAE B2B quote conventions with numbers (*verify* norms against FTA VAT rules and common contract practice) | 2k | **P1** |
| 4 Price bands | expert | **partial** — method record only; no data (0 quotes) | pricing-benchmark book (procurement row 3) | shared | **P1** |
| 10 BOQ arithmetic | expert | **missing** | shared BOQ reference (rfq_qualification_mgr row 2) + an arithmetic-check rule record | shared + 0.8k | P2 |
| 7 Report contract | expert | **partial** — "Match preview design" playbook; the 86 `quote_comparison_contract.yaml` files are unreachable | wire `p_category_key` (shared) | code | P2 |
| 12 Worked examples | expert | **missing** | 5 ZZ DEMO comparison sets with the normalised table, scores and the flags raised | 8k | P2 |
| 9 Standards references | working | **partial** — trade chunks mention them; no per-category "must attach" list | authority × category matrix (shared with procurement row 11) | shared | P3 |
| 1, 5, 6, 8, 11 | expert | **present** (row + dept-scoped playbooks/failure modes + role) | — | — | — |

**Reasoning gap.** The row and the dept playbooks give it the right discipline (normalise first, absolute bar, tie-breaks); the deterministic comparer it supervises scores only price/delivery/completeness and the agent holds no numbers, no VAT rule, no technical rubric and no example. **P1 = 4.**

---

## 6. `rfq_success` — RFQ Success Specialist

**What it does today.** Specialist, reports `procurement`, event_driven_operator, execute_low (threshold 0); `nudge`, `refund_within_window`, `resolve_within_policy` all **advisory**. Runs/7d: **8** (`ok`, lane determinations). Exam: **30% (6/20; 7 not covered)**, latest 3/5. Retrievals/30d: **2**. KPI "primary objective 95% weekly" — actual **55.36**. employee_knowledge 11 (customer_success expert; procurement awareness). Packaged role: customer-success operations specialist (25); readiness `tools_connected`.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (674 chars, priority 74) | 2026-08-06 | "Making an RFQ answerable": most RFQs die at the brief; chase the missing field before dispatch; two silent killers (category no approved supplier serves → escalate to Marketplace OS, don't resend; budget an order of magnitude off → correct before quoting); success = one comparable quote, not ten dispatches |
| agent_knowledge experience | 9 | 2026-09-05 | gap-fills incl. match preview design, repairing a broken notification channel, reveal-funnel progress, supply floor of three, pricing outlier, a V3 strategy, 04_OPERATING_PRINCIPLES.json |
| employee_knowledge | 11 (5/12) | — | customer_success expert; company ×5; operations/procurement/sales_crm awareness; os, communication working |
| ops_knowledge reachable | marketplace 105 ("When to say no supply exists", "Dispute handling after a reveal", "The reveal that notifies both parties", remediation "buyer complaint that the revealed supplier was unreachable", "Repairing a broken notification channel", KPI "Reveal conversion", "Progress toward the revenue target") + procurement 558 (Inquiry Lifecycle, Reveal Workflow, Award Workflow, SOP 08 Award And Reveal) + role 25 | | |
| fn_agent_context | 27,358 chars | live | Layer 2 empty; Layer 1 16 items 9,839 |

**Senior-staff standard — RFQ success / lifecycle owner**

| # | Domain | Depth |
|---|---|---|
| 1 | RFQ lifecycle states and SLAs with numbers (dispatch → first quote ≤24 working h → comparison → reveal → notify supplier after 1 working day → founder call after 3 → refund path; admin fee 250; 3% recovered from a non-responding supplier) | expert |
| 2 | Chase cadence and channel rules (email/WhatsApp templates, timing, 21:00–07:00, Ramadan, tone) | expert |
| 3 | Honest no-supply messaging and escalation to coverage | expert |
| 4 | Budget-expectation correction using category medians | expert |
| 5 | Reveal flow and Stripe (3% fee, what the buyer sees, receipt, refund only via founder, refund window) | expert |
| 6 | Dispute handling and evidence limits | working |
| 7 | Supplier-unreachable-after-reveal remediation | expert |
| 8 | Notification-channel repair | working |
| 9 | Customer communication in brand voice ("smart engine", bilingual) | expert |
| 10 | Funnel metrics (reveal conversion, end-to-end) | working |
| 11 | Anti-circumvention messaging (AED 15k / 3×; CC-the-platform term) | working |
| 12 | Boundaries (no supplier-selection change; no identity; no price promises) | expert |
| 13 | Worked stalled-RFQ cases | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 fix | 1 SQL | **P1** |
| 1 Lifecycle SLAs with numbers | expert | **partial** — row + dept playbooks state the shape; the refund/notify day counts, admin fee and 3% are `decision_policy` values not in context; TTFQ ≤24h is in procurement's row, not this agent's | policy record (deterministic) with every SLA number the agent chases against; copy procurement's SLA row | 1.5k | **P1** |
| 5 Reveal flow & Stripe | expert | **partial** — Layer 1 "Pricing & fees (LIVE)" 929 chars; the reveal→notify→call→refund sequence as a numbered SOP is in no marketplace record (`refund_within_window` is an advisory tool it cannot explain) | SOP record: the reveal-to-refund path step by step with the policy keys and who acts (founder-only refund) | 1.5k | **P1** |
| 4 Budget correction | expert | **missing** — no medians | pricing-benchmark book (shared) | shared | P2 |
| 2 Chase cadence | expert | **partial** — brand rows in Layer 1; TDRA hours in bd's row; no template set | template record: chase sequence per stalled state with channel and timing | 2k | P2 |
| 11 Anti-circumvention messaging | working | **partial** (Layer 1 "Penalty & collections model" *verify*) | authority record shared with procurement row 5 | shared | P3 |
| 13 Worked cases | expert | **missing** | 8 ZZ DEMO stalled RFQs with the diagnosis and the message sent | 5k | P2 |
| 3, 6, 7, 8, 9, 10, 12 | — | **present** (row + dept-scoped playbooks/remediations + Layer 1 brand + role) | — | — | — |

**Reasoning gap.** Good causal rule (the two silent killers) and the best dept-scoped remediation coverage in the department; missing every number it chases against and the step list of the money path it is asked to advise on. KPI actual 55.36 is the only measured competence number in the department; its SQL basis was not opened. **P1 = 3.**

---

## 7. `doc_intel_manager` — Document Intelligence Manager

**What it does today.** Specialist (routing tier director), reports `procurement`, event_driven_operator, execute_low (`analysis` supervised). Runs/7d: **10** (`ok`, lane determinations). Exam: **30% (6/20)**, latest 3/5. Retrievals/30d: **0**. KPIs: documents parsed to structured output target 85% — **actual 60.00**; BOQ lines extracted correctly 95% NULL; drawings linked to RFQ items 70% NULL; inquiries complete before invite 85% NULL. employee_knowledge **0/12**. Packaged roles: document-intelligence director / operations specialist / reviewer-auditor + rfq-inquiry-intelligence analyst-controller (26 each); readiness `tools_connected`. Machinery: `doc_extract`, `license_extract` (model prompts: licence → legal_name, number, authority, emirate, issue/expiry, activities, TRN, confidence; certificate → doc_type, issuer, reference, expiry, covers), `doc_render`, `boq_fixture`/`boq_fixture_run` (exist; not measured here).

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (597 chars, priority 4) | 2026-08-11 | four stages (classify, extract, validate, link) each failing differently; native-text PDF is parsed not vision-read; never send a 200-page scan whole — chunk, retrieve, send the section; every extraction carries confidence + source location; unparseable → named reason, never silent empty |
| agent_knowledge experience | 8 | 2026-09-05 | gap-fills: ghost supplier, category expansion authority, a field bank, an rfq_quality_gate, regulated goods, the harness lesson, "The Supplier Categories We Cover", retrieval policy |
| employee_knowledge | 0 | — | nothing bound |
| ops_knowledge reachable | doc_intelligence 132 (pack) + procurement 558 (Boq Extraction, Cad And Drawing Handling, OCR, Pdf Extraction, Quotation Extraction, Datasheets, Image Understanding, Malware And File Safety, Document Classification/Validation, Source Lineage, Attachment Validation, Version Control; SOP 01 File Intake, SOP 02 File Classification, SOP 03 Text Extraction, SOP 04 Document/Boq Extraction, SOP 05 Drawing Analysis, SOP 08 Version Comparison, SOP 09 Document Review, SOP 10 Archive) + marketplace 105 + role 104 | Jul 2026 | |
| fn_agent_context | 27,453 chars | live | Layer 2 empty; KPI block 248 chars; Layer 1 16 items 9,768; Layer 4 3 items |

**Senior-staff standard — document intelligence lead for procurement documents, UAE**

| # | Domain | Depth |
|---|---|---|
| 1 | Document taxonomy: RFQ attachments (BOQ xlsx/pdf, drawings dwg/pdf, specs, tender docs, datasheets, catalogues, photos) and supplier documents (trade licence, VAT certificate, insurance schedules, ISO certificates, manufacturer letters, bank letters, Emirates ID/passport) | expert |
| 2 | Extraction schemas per document type with confidence and provenance | expert |
| 3 | BOQ structure and units; rate × qty arithmetic; provisional sums; multi-sheet workbooks | expert |
| 4 | Drawing reading (title block, revision, scale, legends, MEP schedules, room schedules) | working |
| 5 | UAE licence layouts per authority for classification and extraction (DET, ADDED, SEDD, JAFZA, DMCC, IFZA, RAKEZ…) | expert |
| 6 | OCR/vision economics (parse vs vision; chunking; the 200-page rule; Arabic OCR) | expert |
| 7 | Validation rules (self-consistency; expiry ≥ issue; TRN 15 digits; licence-number format per authority; date formats) | expert |
| 8 | File safety (malware, macros, size limits, password-protected PDFs) | working |
| 9 | Privacy and redaction (PDPL; contact details in supplier-safe packages; Emirates ID handling) | expert |
| 10 | Named-reason failure contract | expert |
| 11 | Accuracy measurement (KPIs; BOQ fixtures; how "parsed to structured" is scored) | working |
| 12 | Catalogue → `supplier_capabilities` extraction (products_norm, brands, authorised distributor, certifications, authority approvals) | expert |
| 13 | Worked examples (one per document type with the extraction and its failure modes) | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 fix | 1 SQL | **P1** |
| 5 UAE licence layouts | expert | **missing** — the extraction prompt names authorities; no layout/format knowledge; 1 licence in the data | UAE trade-licence handbook (shared with Supply) | shared 20k | **P1** |
| 3 BOQ structure & arithmetic | expert | **missing** — legacy "Boq Extraction" topic is generic; KPI "BOQ lines correct" NULL | shared BOQ reference + extraction schema record (columns, unit dictionary, sum checks) | shared + 1.5k | **P1** |
| 12 Catalogue → capabilities | expert | **partial** — 15,306 rows extracted (newest 2026-08-12) with `trades` on all, **0** certifications, **0** authority_approvals, 1 confirmed; no record explains the schema or what "confirmed" needs | policy record: the `supplier_capabilities` schema, extractor version, confidence/completeness meaning, review states (`derived`→`confirmed`) | 1.5k | **P1** |
| 2 Extraction schemas | expert | **partial** — licence and certificate schemas exist as prompts; BOQ/drawing/spec/quotation schemas not found as records (*not traced* in `doc_extract`) | one record per document type: fields, confidence, provenance, failure reasons | 4k | P2 |
| 7 Validation rules | expert | **partial** — expiry ≥ issue implicit in the cert prompt; no TRN/licence-number format rules | rule record (deterministic) | 1k | P2 |
| 4 Drawing reading | working | **missing** | reference 2k | 2k | P2 |
| 11 Accuracy measurement | working | **partial** — KPI 60% measured; `boq_fixture_run` exists (not opened) | SOP: how the 60% is computed and how a fixture run is read | 0.8k | P3 |
| 8 File safety | working | **partial** (legacy topic) | rule record 0.6k | 0.6k | P3 |
| 9 Privacy/redaction | expert | **partial** (legacy SOP 06/07; "Data minimisation" principle) | policy record (shared with rfq_qualification_mgr row 10) | shared | P2 |
| 13 Worked examples | expert | **missing** | one annotated example per document type (ZZ DEMO) | 6k | P2 |
| 1, 6, 10 | expert | **present** (row) | — | — | — |

**Reasoning gap.** The row is a compact, correct engineering doctrine (stage failures, cost discipline, named reasons) — and 597 characters. Everything domain-specific (what a DET licence looks like, what a BOQ column means, why a certification array is empty on 15,306 rows) is absent; nothing bound in `employee_knowledge`. **P1 = 4.**

---

## Department summary — Marketplace

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| procurement | 4 | 5 | 2 |
| rfq_qualification_mgr | 4 | 6 | 1 |
| inquiry_router | 3 | 3 | 2 |
| spec_commercial | 4 | 3 | 1 |
| quote_evaluation | 4 | 3 | 1 |
| rfq_success | 3 | 3 | 1 |
| doc_intel_manager | 4 | 5 | 2 |
| **Total** | **26** | **28** | **10** |

Seven of the 26 P1s are the same platform defect (S-1). Net of that: 19 P1 ingest/wiring items, of which several are shared (thresholds record, pricing book, category-arm wiring, BOQ reference, licence handbook).

**Top 5 ingest items (department)**

1. **Fix the Layer 2 budget in `fn_agent_context`** — the 12 profession rows of these seven agents (≈9.4k chars, including procurement's six doctrine rows) reach no prompt today.
2. **Publish the decision thresholds as a deterministic policy record** (dept marketplace, layer `policy`, generated from `decision_policy`): floor 35, fanout 5/3, score weights 40/20/15/10/15, strike 3, confidence 0.6, fraud 0.7, sensitive categories, refund days 1/3, admin fee 250, 3% — so Layer 2f carries them. Add the eligibility predicates from `fn_match_capability` / `v_supplier_match_exclusions` and the completeness scoring from `inquiry_ai` the same way.
3. **UAE pricing-benchmark book** — AED ranges per unit per spec bucket for the ~20 main trades (fit-out, HVAC, electrical, plumbing, waterproofing, flooring, gypsum, joinery, steel, cleaning/FM, security, manpower…), dated and sourced (*verify* sources), as `kb_chunks` category `pricing-benchmarks-uae` + one reference record per trade family. Today the estate has a benchmark *method* and no numbers; 0 quotes means none can be derived yet.
4. **Make the 1,204 category-pack records reachable**: pass the routed category as `p_category_key` into `fn_agent_context_v3` from `inquiry_ai`/`route_inquiry`/`quote_compare`, or re-key `NNN_slug` → catalog slug and add a category arm to `fn_ops_knowledge_match`. The V3 qualification strategies, minimum-sufficient policies and quote-comparison contracts are exactly the per-category senior standard and are currently invisible at runtime (derived from the scope arms).
5. **BOQ / drawing / UAE commercial-conventions handbook** for rfq_qualification_mgr, quote_evaluation and doc_intel_manager: units and measurement bases (CESMM4/POMI/NRM2), rate × qty checks, provisional sums, drawing title blocks and schedules, VAT 5% inclusive/exclusive, retention, advance, validity norms — plus a technical-compliance rubric generated from `category_quote_specs` so comparison is not price/delivery/completeness only.

**What could not be measured.** Real routing, matching and comparison accuracy (0 inquiries, 0 quotes, 0 matches — only fixture suites: 344/344 aliases, 5/5 match_eval); the scoring rule inside `inquiry_ai` and `doc_extract`'s schemas (not opened); `boq_fixture_run` results; `category_price_stats` (no data); whether the 15 "Commercial & Pricing" trade chunks per category carry AED figures (not opened — *verify*); semantic reach of `fn_ops_knowledge_match` (needs an embedding); the 3-arg/`_capped` path (VOLATILE, not executed); `dept_library`; `agent_evals` (no per-agent column); review quality (0 rejections); the SQL behind rfq_success's 55.36 KPI actual.
