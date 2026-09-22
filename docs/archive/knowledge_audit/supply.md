# Knowledge audit — Supply department (6 agents)

Measured 6 Sep 2026, 02:02–02:40 UTC, read-only against `htdblwldjkcgjvmqkbeh` (one project). No paid model call was made; the only routine executed per agent was the STABLE 2-argument `fn_agent_context(agent_key, 22000)`. Every number below is measured; anything derived from reading a function body rather than executing it is marked *derived*; sources I could not open are marked *verify*.

Founder's order (6 Sep 2026): each agent must carry the knowledge of top senior staff in its position and be able to run ~90% of the time without going to the internet, with the reasoning to match.

Scope: `org_agents.active = true and department = 'supply'` → **bd, onboarding, partnerships_mgr, supplier_coverage, supplier_retention, supplier_verification**.

---

## 0. How knowledge reaches a Supply agent today (shared findings)

**Runtime path (read from `supabase/functions/agent_brain/index.ts` and the deployed function bodies).** `agent_brain` → `fn_agent_context_capped(key, 24000, message)` → the 3-arg `fn_agent_context`, which is the 2-arg base plus query-dependent layers 2b (dept_library), 2c (`fn_ops_knowledge_search`, `dept_key = 'supply'` literal only), 2d/2f/2g (`fn_agent_context_v3`: `fn_dept_scope('supply')` = `{bizdev, supplier_success, supply}` + `org_role_identity` packaged roles), plus `kb_search` (kb_chunks) and `fn_ops_knowledge_match` (ops_knowledge, cosine, same scope arms). The 3-arg path is VOLATILE (it writes `agent_context_retrieval`), so it was not executed for this audit.

**Finding S-1 — the profession layer never reaches the prompt (13/13 agents, measured).** In every one of the 13 in-scope contexts the section `# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` is **1 character long**; a grep of all 13 saved contexts for the agents' own profession topic titles ("Verifying a UAE supplier before approval", "Professional standard (KYC & UAE licensing)", "Quote fraud & collusion doctrine") returns **0 hits**. Cause (*derived* from the function body): Layer 2 admits a piece only while `length(out)+length(piece) <= own_cap + 2200`, with `own_cap = least(22000/2, 6000)` ≈ 6,000–6,090; but `out` already holds identity (≈1.4k) + company genome (2.6k) + risk register (2.98k) + the employee block (0.6–1.5k + authority/KPI/workload/OS/goals/objectives ≈ 3–5k) ≈ 10.5–12k characters before the loop starts. The budget is exhausted before the first profession row is considered, for every agent. **Everything in the "agent_knowledge (profession)" rows below is therefore inventory, not prompt content, until this is fixed.** (Layer 1 global rows still fit because they are budgeted against `cap` = 22,000.)

**Finding S-2 — no live state for Supply.** `org_departments.supply.health_fn` is NULL, so no `# LAYER 3 - LIVE OPERATIONAL STATE` section exists in any Supply context (measured: absent in all 6). A Supply agent cannot see the lead pool, approvals or licence expiries from its context. (Marketplace has `fn_ws_marketplace`; it returns all zeros pre-launch.)

**Finding S-3 — what does reach the prompt (measured, 2-arg call, 26,410–26,656 chars per Supply agent):** identity (1.45k) · genome (2.6k) · risk register (2.98k) · employee record (0.55–1.35k) · authority (84–436) · KPIs (99–730) · workload (410) · Supply OS block (503) · company goals (655) · dept objectives (153) · self_review findings (1,027) · decision_record (320) · **Layer 1 = 15–17 global items, 8.9–10.5k chars** (brand wording, document branding, AI Constitution, response structure, governance gate, retrieve-before-answering, RFQ completeness rule, Pricing & fees LIVE, Company FAQ truncated to 1,500 of 197,956 chars, 5 explainability rows, company:self_knowledge, canon:core) · **Layer 4 = 3,502 chars of `exam:NNNN` gap-fills** · target-operating-model digest (971). Layer 4 is largely off-role: supplier_verification's Layer 4 carries "Monthly operating and financial review — handoff 4: executive_office to strategy_evolution" and a Cold Room minimum-sufficient-question policy.

**Finding S-4 — the exam does not measure domain competence.** All questions for these agents are of the form *"What does the company's operating knowledge say about: `<ingested file name>`?"* (difficulty `core`); the score is recall of ingested files. Scores below are reported as measured but should not be read as a senior-staff test.

**Finding S-5 — review outcomes carry no signal.** `review_chain` decisions for these agents are only `approve`/`owned` (0 rejections across 270 authored rows); `artifact_review` has 0 rows for them.

**Finding S-6 — all runs in the last 7 days are deterministic playbook lane determinations** (`used_llm=false`, cosine 0.87–0.93 against the 8 `org_task_lane` playbooks). No model reasoning ran; the LLM routes returned 503 (paid hold) wherever they were tried.

### 0.1 Department-level inventory (what a Supply agent can reach through the scope arms)

| Source | Rows | Freshness | What it is | Reach |
|---|---|---|---|---|
| `ops_knowledge` dept_key=`supply` | 8 | eff. 2026-09-04 | `org_task_lane` decision playbooks (campaign.launched, content.published, KPI missed, quote.received, rfq.classified, rfq.created, supplier.applied, supplier.approved) | dept arm |
| `ops_knowledge` dept_key=`supplier_success` (legacy, scoped in) | 416 | eff. 2026-07-31; 210 implemented / 118 partial / 88 target_state | 40 knowledge_domain topics (Trade Licences, Certifications, Document Fraud, Duplicate Accounts, Licence And Document Expiry, Sanctions And Restrictions, Risk Scoring, Supplier Scoring/Lifecycle/Onboarding/Coaching/Performance, Coverage-Gap Management, SLA Management, Appeals…) avg 2,353 chars; 40 data_and_evidence; 39 operational_application; 39 control_requirements; 21 live_data_binding; 20 decision_rule (the generic 10 "rule 01–10" × Supplier Success and Trust & Safety); 20 SOP (Licence Extraction And Verification, Capability Confirmation, Automated Approval Gate, Document Reminder, Supplier Suspension, Appeal Review, Supplier Score Refresh, Supplier Complaint Handling…); 20 exception_playbook; 66 yaml / 24 md pack files | dept arm (v3 slice + cosine match); NOT the 2c keyword search (literal `supply`) |
| `ops_knowledge` dept_key=`bizdev` (legacy) | 128 | no effective_date on 120 | 66 yaml, 24 md, 24 failure_mode_case, 8 metric_definition pack files | dept arm |
| `ops_knowledge` dept_key=`trust_safety` | 134 | — | fraud/verification pack incl. "Supplier Verification — how the department uses it" | **not in `fn_dept_scope('supply')`** — unreachable from Supply |
| `ops_knowledge` dept_key=`marketplace` `marketplace_expert` | 97 | eff. 2026-09-02..04, avg 2.6k chars, all embedded | 21 decision playbooks, 27 failure modes, 18 KPI, 10 policy, 8 authority, 7 reference, 6 remediation — includes "UAE trade license verification: the decision rule", "Supplier approval decision: the five-gate onboarding funnel", "Supplier standing", "Supplier reactivation", "Grow verified supply safely", "Liquidity by category", "Building a supply floor of three" | **dept_key=marketplace → not reachable by any Supply agent** (derived from the scope arms) |
| role-scoped `ops_knowledge` (packaged roles) | 25–26 per role | none | V2 pack yaml/md/json + failure_mode_case, avg ≈2.8k chars | role arm |
| `ops_knowledge` scope_type=`category` | 1,204 = 86 × 14 | none | V2/V3 category packs (qualification strategy, field & question bank, minimum-sufficient policy, quote readiness, rfq_quality_gate, quote_comparison_contract, research & escalation policy…), keyed `NNN_slug` | only via `p_category_key`, which the 3-arg `fn_agent_context` passes as NULL → *derived*: unreachable except as exam gap-fills |
| `kb_chunks` per catalog category | 2,760 across 86 (min 6: lifts, signage; typical 15–33) | most newest 2026-08-16 | 15 "QuotesDone trade knowledge" sections per category (incl. "UAE Regulations & Authorities" ≈1k chars, "Supplier Knowledge", "Documents Knowledge") + a few web-researched docs. UAE mentions in these 2,760 chunks: Civil Defence 622, DED 612, DEWA 578, Dubai Municipality 523, ESMA 345, SIRA 323, Trakhees 170, UAE FLS Code 142, ISO 9001 140, MOIAT 125, MoHRE 67, Estidama 43, Al Sa'fat 39, Dubai Building Code 30, EIAC 27, FTA 22, ISO 45001 11 | `kb_search` (RRF, category-agnostic for functional staff) |
| `kb_chunks` field corpora (v3 `field_corpus` = `category = any(scope)`) | 0 chunks match `bizdev`/`supplier_success`/`supply` | — | — | **empty for Supply** |
| `category_licence_activity` | 20 of 86 categories | — | activity regex + notes (SIRA, DCD, MoE auditor, MOCCAE, RERA, FTA tax agent, DET tourism) | used by `fn_check_licence_activity` |
| `qualification_playbooks` | 29 active, 10 q each | Jul 2026 | old taxonomy slugs; **0 of 29 match a catalog slug** | — |
| `category_specs` | 56 (21 with supplier_requirements + compliance_checklist) | 2026-07-28 | old slugs; **0 of 56 match a catalog slug** | — |
| `decision_policy` | 20 threshold keys | Jul–Sep 2026 | `matching_strike_limit` 3, `match_relevance_floor` 35, fanout 5/3, `confidence_min` 0.6, `fraud_score_max` 0.7, `sensitive_categories`, refund timings, `auto_action_max_aed` 0 | **not read by `fn_agent_context`** (derived) |
| Live data the roles act on | leads 21,665 non-demo: **1** with licence no/expiry/doc/TRN, **0** with `license_activity`, 1 verified, 1 approved; `supplier_capabilities` 15,306 rows (all `trades`, **0** certifications, **0** authority_approvals, **1** confirmed, newest 2026-08-12); `supplier_capability_confirmation` 0; invite pool 19,725, `invite_enabled=false` | | | |

Deterministic gates the department owns (read from function bodies): `fn_supplier_autoapprove_clean` (approves when: registration submitted ∧ licence doc ∧ OCR ran ∧ licence no > 3 chars ∧ `license_expiry > today+30` ∧ owner email verified; notifies "trade licence checks passed"), `fn_supplier_licence_gate` (doc present, number read, not expired), `fn_check_licence_expiry`, `fn_check_licence_activity` (regex per category; refuses when no rule or no captured activity), `license_extract` (model extraction of legal_name, licence no, authority, emirate, issue/expiry, activities, TRN; certificates: insurer/body, reference, expiry), `doc_expiry_scan` (4 runs/7d, 0 actions), `supplier_invites` (planned & HELD).

---

## 1. `bd` — Business Development Manager

**What it does today.** Director, reports to `ceo`, `scheduled_manager`, execute_medium, budget AED 1,000; personal authority: `outreach_draft` autonomous, `outreach_send` advisory (≤1,000). Runs/7d: **2** (both `ok`, both `org_task` lane determinations, no model). Exam: **54% correct all-time (14/26; 6 partial, 2 wrong, 4 not covered)**, latest day 3/5. kb_usage_log retrievals/30d: **2**. review_chain: 40 authored (24 approve, 16 owned), 36 reviewed. KPI: "primary objective 100% monthly" — actual NULL. Packaged roles: BD&P director / analyst-controller / reviewer-auditor (25 records each); readiness `restricted_to_advisory`.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | 4 (2,654 chars) | 2026-06-23..25 | B2B sales methodology (BANT/MEDDIC/SPIN), PDPL 45/2021 + TDRA unsolicited-comms + DNCR with sources, role (20k-lead DB, best-rated first, plan-only mode), cadence playbook (6–8 touches/3–4 wks) |
| agent_knowledge experience | 3 | 2026-09-04 | exam gap-fills: a category quote_comparison_contract, a field bank, a research/escalation policy — off-role |
| employee_knowledge | 12 domains | — | sales_crm expert; company ×5 expert; customer_success/finance/legal_uae/procurement awareness; quotesdone_os working; communication working (5 of 12 layers bound; verdict INCOMPLETE) |
| ops_knowledge reachable | bizdev 128 + supplier_success 416 + supply 8 + role 75 | Jul 2026 / none | see §0.1 |
| fn_agent_context (2-arg) | 26,410 chars | live | Layer 2 empty; Layer 1 15 items 9,456 chars; Layer 4 3 gap-fills |

**Senior-staff standard — supplier-acquisition BD director, UAE B2B marketplace**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE supplier landscape per category and emirate (top players, where supply clusters: Al Quoz, DIP, Mussafah/ICAD, Sharjah Industrial, Ajman, RAKEZ) | expert |
| 2 | QuotesDone's supplier value proposition and the exact commercial facts he may state (free registration to 31 Jul 2027, first-1,000 permanent exemption, buyer pays 3% reveal, supplier non-response 3% charge, AED 15k / 3× anti-circumvention, anonymity until reveal) | expert |
| 3 | Objection library for UAE SMEs (lead quality, "another commission", anonymity, non-response charge, "we get enough work", WhatsApp-only firms) | expert |
| 4 | Outreach compliance: PDPL, TDRA unsolicited-communications policy, DNCR, WhatsApp Business policy, SMS hours | expert |
| 5 | Sales methodology (BANT/MEDDIC/SPIN), relationship-led UAE selling, bilingual etiquette, Ramadan/summer timing | working |
| 6 | Funnel economics: invite→register→verify→activate benchmarks, CAC vs LTV, deliverability ramps (cap 50/day), bounce thresholds | expert |
| 7 | Category prioritisation (liquidity-impact triage; supply floor of three before marketing) | working |
| 8 | Trade-licence regimes as a qualification filter (mainland/free-zone/offshore; activity must cover the trade) | working |
| 9 | Enterprise & government pipeline (Dubai eSupply, ADGPG, ADNOC ICV, DEWA/ADDC vendor registration, DM vendor registration, ICV programme) | working |
| 10 | Association/channel partners (Dubai/Sharjah/Abu Dhabi Chambers, Dubai SME, Society of Engineers, EmiratesGBC, MEFMA, business councils) | working |
| 11 | Competitive landscape and fee models (Tradeling, ProTenders, Alibaba UAE, classifieds) | aware |
| 12 | Sender reputation & deliverability engineering (SPF/DKIM/DMARC, warm-up) | working |
| 13 | Pipeline reporting: stages, weekly numbers, KPI definitions | working |
| 14 | Boundaries: no signing, no commercial terms, no supplier confirmation | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** — Layer 2 = 1 char (S-1) | Fix the Layer 2 budget in `fn_agent_context` (platform, not ingest) | 1 SQL change | **P1** |
| 2 Value proposition & commercial facts | expert | **partial** — "Pricing & fees (LIVE)" 929 chars and canon:money 945 chars in Layer 1; the supplier-side promises (3% non-response, 15k/3×, first-1,000) appear only in partnerships_mgr's row, not bd's | One `agent_knowledge` profession row "What BD may promise a supplier" built from the published T&C §§ and Supplier Agreement (verify clause numbers) + `ops_knowledge` policy (dept supply) | 3–4k chars | **P1** |
| 3 Objection library | expert | **missing** — no row, no dept record | `ops_knowledge` decision_playbook (dept supply): 15 objections × answer × proof point | 6–8k chars | **P1** |
| 1 UAE supplier landscape | expert | **missing** — no record names any supplier cluster or emirate pattern; Layer 3 absent (S-2) | `kb_chunks` category `supply` (new): per-category "who supplies this in the UAE" from the 19,725-lead pool + `lead_category` scores; plus a `health_fn` for supply so the pool is visible live | 86 × ~1k chars + 1 SQL fn | **P1** |
| 6 Funnel economics | expert | **partial** — onboarding holds the 0.58% invite→approval actual and the ramp-cap lesson; bd's context has neither | `agent_knowledge` state row refreshed weekly from `employee_kpi` (onboarding's 7 KPIs) + benchmark record (industry invite→register 2–5%, verify 40–60% *verify*) | 2k chars | P2 |
| 7 Category prioritisation | working | **partial** — "Choosing which category to fix first", "Building a supply floor of three" exist with dept_key=marketplace, unreachable from supply | Re-scope those 5 marketplace_expert records to `supply` as well (`org_department_alias` or duplicate rows dept_key=supply) | 0 new text | P2 |
| 4 Outreach compliance | expert | **present** — PDPL/TDRA/DNCR with sources in 2 rows | — | — | — |
| 5 Sales methodology | working | **present** | — | — | — |
| 8 Licence regimes as filter | working | **partial** — nothing in bd's rows; onboarding's rows cover it | Share onboarding's "Verified references & key standards" row to bd (copy at priority ≥6) | 1.4k | P2 |
| 9 Government/enterprise pipeline | working | **missing** — `government-tenders-and-procurement-support` corpus (67,181 chunks) exists in kb_chunks but is generic and not in any Supply scope | `ops_knowledge` reference (dept supply): UAE public-buyer registration map (Dubai eSupply, ADGPG/ADNOC ICV, DEWA, ADDC, DM, RTA, federal DPP) with prerequisites | 5k chars | P2 |
| 10 Associations/channels | working | **missing** — partnerships row lists types only | reference record: named UAE bodies, membership terms, contact route (verify each) | 3k | P2 |
| 12 Deliverability engineering | working | **partial** (ramp-cap experience row on onboarding only) | SOP record: sender setup, warm-up curve, bounce/complaint thresholds, suppression | 2k | P2 |
| 13 Pipeline reporting | working | **partial** — single KPI with NULL actual | Replace "primary objective" with 3 measurable KPIs (`employee_kpi.measure_sql`): invites sent, registrations, approvals/week | SQL | P2 |
| 11 Competitors | aware | **missing** | reference record, 1.5k | 1.5k | P3 |
| 14 Boundaries | expert | **present** (forbidden_decisions + employee_authority in context) | — | — | — |

**Reasoning gap.** The rows it does hold are prescriptive (cadence, consent) and carry one real decision rule (stop on reply/opt-out). Nothing carries a worked example of qualifying a supplier lead, a threshold for "good enough to invite" (`lead_category.score`), or a pipeline number it could reason from — and Layer 3 does not exist for Supply. Exam 54% is the best in scope but tests file recall. **P1 = 4** (one of them the shared Layer 2 fix).

---

## 2. `onboarding` — Supplier Onboarding Specialist (supplier onboarding / KYC)

**What it does today.** Specialist, reports `bd`, event_driven_operator, execute_low ≤1,000; personal authority: `supplier_verify`, `qualify_inquiry`, `compare_quotes` autonomous; `invite`, `route_category`, `match_inquiry`, `capability_enrich`, `supplier_approve_clean` advisory. Runs/7d: **48**, all `ok`, latest counts `{reviewed:0, rows_written:0, licence_alerts:0, queued_approval:0}` — the cron ticks find nothing to review. Exam: **13% correct (2/16; 9 partial, 2 wrong, 3 not covered)**, latest day 1/5; `canon_eval_runs` 2026-08-10: 2/6 (33%). Retrievals/30d: **14**. KPIs with live actuals: total approved suppliers **1** (target 860), categories at 10-supplier target **0/86**, categories with a viable pool **25/86**, invite→approval **0.58%** (target 5%), verified per active category **0.03** (target 10), lead pool growth 0 (target 2,000). Packaged roles: supplier-success director + reviewer-auditor; readiness `restricted_to_advisory`.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | 6 (6,197 chars) | 2026-06-23..07-24 | KYC standard for a marketplace (not AML); verified references (DET/DED, free zones IFZA/DMCC/JAFZA, offshore RAK ICC; establishment card; UBO Cabinet Decision 109/2023; TRN Decree-Law 8/2017; PDPL); supplier lifecycle & activation definition with stage-conversion reporting; role; supplier due-process policy (notice/hearing/decision/appeal/record; bans founder-gated); deepened risk-based KYC playbook (7-day pre-expiry reminder) |
| agent_knowledge experience | 7 | 2026-09-05 | 2 real org lessons (diagnose supplier pool before invites; respect deliverability ramp caps) + 5 exam gap-fills (data minimisation, a category remediation file, KPI-missed lane…) |
| employee_knowledge | 14 domains (5/12 layers) | — | procurement, supplier_mgmt, uae_authorities expert; company ×5; customer_success/finance/legal_uae/operations awareness; os & communication working |
| ops_knowledge reachable | supplier_success 416 (incl. SOP 01 Supplier Registration And OTP, SOP 03 Licence Extraction And Verification, SOP 05 Capability Confirmation, SOP 06 Automated Approval Gate, SOP 07 Document Reminder) + bizdev 128 + supply 8 + role 52 | eff. 2026-07-31 | generic pack; the 10 decision rules are the same "rule 01–10" template as every department |
| fn_agent_context | 26,439 chars | live | Layer 2 empty; KPI block 730 chars (the 7 KPIs with actuals — the one place its numbers are real); Layer 1 16 items 8,879 chars |

**Senior-staff standard — supplier onboarding / KYC lead, UAE**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE licence regimes and how to read each: DET Dubai, ADDED/TAMM, SEDD, Ajman DED, RAK DED, Fujairah, UAQ; free zones (JAFZA, DMCC, DAFZA, DSO, IFZA, RAKEZ, SHAMS, SAIF, KEZAD, twofour54, Meydan, DWTC); offshore (JAFZA Offshore, RAK ICC); e-trader/instant licences; legal forms (LLC, sole est., branch, civil company); licence-number formats and expiry conventions per authority | expert |
| 2 | Activity-to-category mapping for all 86 categories (which licensed activities cover which trade; regulated add-ons) | expert |
| 3 | Verification methods per authority (DET licence-verify service, MoE National Economic Register, free-zone registries, ICP establishment card, MoHRE establishment card, FTA TRN lookup, Dubai Chamber membership) | expert |
| 4 | Document set and authority-to-act (licence, establishment card, MoA/POA, signatory Emirates ID/passport, VAT certificate, bank letter/IBAN name match) | expert |
| 5 | Regulated-category permits and what valid proof looks like (DCD, SIRA, DM food/health/pest/environment, DEWA/ADDC contractor grades, RTA, MOCCAE, MOIAT/ECAS, DHA/DoH, ADAFSA, TDRA, Legal Affairs, RERA) | expert |
| 6 | KYC/AML posture (marketplace facilitator, not a DNFBP; no goAML; PDPL basis; retention) | working |
| 7 | UBO regime (Cabinet Decision 109/2023) | aware |
| 8 | VAT/TRN (Decree-Law 8/2017; 15-digit TRN; AED 375k mandatory-registration threshold; when a supplier may quote ex-VAT) | working |
| 9 | Onboarding funnel design & deliverability (invite caps, OTP flows, WhatsApp template rules, drop-off diagnostics, benchmarks) | expert |
| 10 | Supplier lifecycle & activation definition; stage-conversion reporting | expert |
| 11 | Due process for adverse actions | expert |
| 12 | Licence expiry & re-verification cadence; auto-pause and recovery | working |
| 13 | Capability confirmation (derived vs confirmed; what confirmation requires; catalogue extraction) | expert |
| 14 | Supplier Agreement obligations it must explain (non-response charge, anonymity, anti-circumvention, refund flow) | expert |
| 15 | Coaching a supplier through the portal (steps, common errors, Arabic support) | working |
| 16 | Risk-rating model (document quality, consistency, duplicate accounts, disposable domains, sanctions stance) | expert |
| 17 | The deterministic gates it owns (`fn_supplier_autoapprove_clean` criteria; `fn_check_licence_activity` coverage; `doc_expiry_scan`) | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) — 6 good rows, 0 reach the prompt | Layer 2 budget fix | 1 SQL | **P1** |
| 1 Licence regimes per authority | expert | **partial** — regime names and one line each; no layouts, number formats, expiry conventions, legal forms | `ops_knowledge` reference (dept supply, kind `reference`, jurisdiction AE): "UAE trade licence handbook" — one section per issuing authority (≈25 authorities) with layout, fields, number format, verify method; source each from the authority's own site (*verify*) | 25 × 800 chars ≈ 20k | **P1** |
| 2 Activity-to-category mapping | expert | **partial** — `category_licence_activity` covers 20/86; `leads.license_activity` captured for 0 of 21,665 | Extend `category_licence_activity` to 86 rows (regex + regulated note) and store the DET/ADDED activity names per category as a `kb_chunks` category record; wire `license_extract.activities` → `leads.license_activity` (today never written — the activity gate can only refuse) | 66 rows + 86 chunks | **P1** |
| 3 Verification methods | expert | **missing** — rows say "verify with the issuing authority" and name no method | reference record: per-authority verification portal / API / QR, NER, ICP, MoHRE, FTA TRN check, with what each returns (*verify* availability of each service) | 4k | **P1** |
| 17 Its own deterministic gates | expert | **missing** — no knowledge row states the auto-approve predicate (doc ∧ OCR ∧ licence no ∧ expiry > +30d ∧ email verified) or that the activity check refuses on 66 categories | `ops_knowledge` policy (dept supply, deterministic=true): "Supplier approval gates as built", generated from the function bodies; refresh on deploy | 1.5k | **P1** |
| 5 Regulated permits & proof | expert | **partial** — authority names in category chunks; `category_specs` checklists on 21 old-slug categories; notes on 8 `category_licence_activity` rows | reference per regulator (≈12): what the permit looks like, number format, verify route, which of the 86 categories need it | 12 × 1k | P2 |
| 4 Document set & authority to act | expert | **present** (rows) — missing forgery tells beyond IBAN mismatch | see supplier_verification row 6 | — | P2 |
| 13 Capability confirmation | expert | **partial** — SOP 05 exists (legacy, eff. 31 Jul); 15,306 derived / 1 confirmed; no rule for what turns derived into confirmed | decision_playbook (dept supply): confirmation contract (which fields, evidence, who signs, version bump) with 3 worked examples | 3k | P2 |
| 9 Funnel design & deliverability | expert | **partial** — 2 experience rows; no benchmarks; KPI actuals show 0.58% | reference: stage benchmarks + diagnosis tree (bounce, OTP drop, doc upload drop) | 2.5k | P2 |
| 8 VAT/TRN | working | **partial** — law cited; no format/threshold | 400 chars appended to "Verified references" row | 0.4k | P3 |
| 14 Supplier Agreement obligations | expert | **partial** — "Penalty & collections model" (1,453 chars, Layer 1) and canon:money reach it; clause-level text does not (*verify* against published T&C) | reference record with clause quotes | 3k | P2 |
| 15 Portal coaching | working | **missing** — no walkthrough of the supplier portal steps | SOP with the registration screens and the 10 commonest errors (from `kyc` OTP flow and registration form) | 2.5k | P2 |
| 16 Risk-rating model | expert | **partial** — legacy topics (Risk Scoring, Disposable Domains, Duplicate Accounts) ≈2.4k each, semantic reach only | decision_playbook with a scored rubric (0–100) and thresholds tied to `fraud_score_max` 0.7 | 3k | P2 |
| 12 Expiry & re-verification | working | **present** (row; `doc_expiry_scan` runs) | — | — | — |
| 6, 7, 10, 11 | — | **present** | — | — | — |

**Reasoning gap.** The best-written rows in Supply (lifecycle definition, due process, risk-based KYC) are here — and none reach the prompt. There is no worked example of an approve/refuse decision, no scored rubric, and the agent does not know the predicate its own auto-approver uses; with `license_activity` never captured, the activity gate can only say "not captured". Exam 13% (lowest in scope) tests file recall. **P1 = 5.**

---

## 3. `partnerships_mgr` — Partnerships Manager (canonical role: Strategic Partnerships & Government Relations Manager)

**What it does today.** Specialist, reports `bd`, on_demand_specialist, execute_low ≤1,000; `outreach_draft` autonomous, `outreach_send` advisory. Runs/7d: **2** (`ok`, lane determinations, "executor none"). Exam: **31% (5/16; 6 not covered)**, latest 3/5. Retrievals/30d: **0**. KPI "primary objective 100%" actual NULL. Packaged role: BD&P operations specialist (25 records); readiness `restricted_to_advisory`. Merged `gov_relations_mgr` (org_role.source_agent_keys) — the government-relations half has no knowledge row at all.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (772 chars, priority 74) | 2026-08-06 | "Partnerships that add supply, not logos": the three things a partner cannot be promised (fee share, identity pre-reveal, off-platform intros), what can be offered (exposure, free registration to 31 Jul 2027, first-1,000 exemption), commercial commitments are founder decisions |
| agent_knowledge experience | 9 | 2026-09-05 | all exam gap-fills (category packs, lane determinations, retrieval policy) — off-role |
| employee_knowledge | 12 (5/12 layers) | — | same set as bd |
| ops_knowledge reachable | bizdev 128 + supplier_success 416 + supply 8 + role 25 | — | see §0.1 |
| fn_agent_context | 26,656 chars | live | Layer 2 empty; Layer 1 17 items 10,533 chars |

**Senior-staff standard — strategic partnerships & government relations, UAE**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE public-procurement landscape (federal Digital Procurement Platform/MoF, Dubai eSupply & Smart Procurement, Abu Dhabi ADGPG, ADNOC ICV & vendor portal, DEWA/ADDC, Dubai Municipality, RTA, Etihad Rail) | expert |
| 2 | Vendor prequalification requirements (ICV certificate, ISO 9001/45001/14001, trade licence, audited financials, HSE) | working |
| 3 | ICV programme (MOIAT national ICV, ADNOC ICV, certification bodies, scoring) | working |
| 4 | Association partners: named bodies, membership terms, what they can circulate | working |
| 5 | Channel partners: distributors, equipment dealers, business councils (BBG, AmCham, IBPC, GBC…) | working |
| 6 | Partnership economics and boundaries (no fee share; no identity; no off-platform; founder-gated commitments) | expert |
| 7 | Contract basics: MoU vs binding agreement; UAE Civil Code/CCL essentials; `legal_triggers` that go to GC | working |
| 8 | Outreach compliance (PDPL, TDRA) | working |
| 9 | UAE event/exhibition calendar as partnership venues (Big 5 Global, WETEX, Gulfood, Intersec, Index, GITEX, Cityscape, Middle East Energy) | working |
| 10 | Enterprise-buyer procurement cycles (developers, main contractors, FM companies; vendor-list mechanics) | working |
| 11 | Partner pipeline reporting and attribution (RFQ volume per partner) | working |
| 12 | Anonymity/T&C constraints on partner data sharing | expert |
| 13 | Regulatory-commitment boundary (never commit; GC speaks) | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 budget fix | 1 SQL | **P1** |
| 1 Public-procurement landscape | expert | **missing** — 0 rows; the 67,181-chunk `government-tenders-and-procurement-support` corpus is not in any Supply scope and is not UAE-specific | `ops_knowledge` reference (dept supply): UAE public-buyer map — portal, registration prerequisites, fee, renewal, contact (*verify* each) | 6k | **P1** |
| 6 Partnership economics & boundaries | expert | **present** (the one row) | — | — | — |
| 2 Prequalification requirements | working | **missing** | reference: standard prequal pack contents per buyer class | 2k | P2 |
| 3 ICV | working | **missing** | reference: ICV programme mechanics and how a supplier's ICV score affects its eligibility | 1.5k | P2 |
| 4 Associations | working | **missing** (types only) | reference: ≈15 named bodies with terms (*verify*) | 3k | P2 |
| 5 Channel partners | working | **missing** | reference: dealer/distributor archetypes + business councils | 2k | P2 |
| 7 Contract basics & legal triggers | working | **partial** — `legal_triggers` exist in `decision_policy` but are not in the context; forbidden_decisions name GC | policy record (dept supply) copying `legal_triggers` + MoU/agreement distinction | 1k | P2 |
| 8 Outreach compliance | working | **missing for this agent** (bd holds it) | copy bd's PDPL/TDRA row | 1.3k | P2 |
| 9 Events calendar | working | **missing** | reference with dates (*verify* annually) | 1k | P3 |
| 10 Enterprise procurement cycles | working | **partial** — one exam gap-fill "Developer Partnerships — how the department uses it" (2,126 chars) | reference: developer/contractor procurement cycle and vendor-list entry | 2k | P2 |
| 11 Pipeline reporting | working | **partial** — KPI NULL | replace "primary objective" with measurable KPI (partnerships qualified/month; RFQs attributed) | SQL | P2 |
| 12, 13 | expert | **present** (Layer 1 canon + role forbidden decisions) | — | — | — |

**Reasoning gap.** One 772-char row is the entire profession; it is a good boundary rule but contains no evaluation method for a proposal (no scoring, no example), and the government-relations half of the merged role has nothing. **P1 = 2.**

---

## 4. `supplier_coverage` — Supplier Coverage & Liquidity Specialist

**What it does today.** Specialist, reports `bd`, on_demand_specialist, authority `advisory` only (`analysis` advisory). Runs/7d: **3** (`ok`, lane determinations). Exam: **19% (3/16; 7 partial)**, latest 1/5. Retrievals/30d: **86** (highest in scope, 1 category) and 86 `decision_log action_gate` rows (conf 1.0). KPIs: categories with ≥3 quoting suppliers target 70% — actual NULL; demand with no supply — 0 (weekly). employee_knowledge: **0 domains bound (0/12 layers)**. Packaged role: supplier-success analyst-controller (26); readiness `restricted_to_advisory`.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (652 chars, priority 4) | 2026-08-11 | coverage = probability an inquiry reaches ≥3 suppliers who quote; three failure modes (none / unverified / unresponsive) and remedies; measure per category × emirate; demand-with-no-supply is the highest-value find |
| agent_knowledge experience | 6 | 2026-09-04 | exam gap-fills incl. a comms weekly report, a failed handoff, "Developer Partnerships" — off-role |
| employee_knowledge | 0 | — | nothing bound |
| ops_knowledge reachable | supplier_success 416 (Coverage-Gap Management topic) + bizdev + supply 8 + role 26 | Jul 2026 | |
| fn_agent_context | 26,459 chars | live | Layer 2 empty; no Layer 3 (S-2); Layer 1 16 items |

**Senior-staff standard — coverage & liquidity analyst, two-sided UAE B2B marketplace**

| # | Domain | Depth |
|---|---|---|
| 1 | Liquidity metrics with definitions and thresholds (fill rate, depth ≥3 per category×emirate, time-to-first-quote, dispatch concentration, starved suppliers, run-rate vs period total) | expert |
| 2 | Coverage-failure taxonomy and remedies | expert |
| 3 | Demand signals (SEO demand per category, inquiry mix, seasonality: Ramadan, Q4, summer) | working |
| 4 | Supply-floor rule (3 before marketing) and cold-start sequencing | expert |
| 5 | UAE supplier geography per category (industrial clusters; emirate coverage; delivered vs installed radius) | expert |
| 6 | The taxonomy: 86 categories, 470 subcategories, aliases, `lead_category` scoring, regulated flag | expert |
| 7 | Lead-pool analytics (19,725 pool; primary category; directory promotion; Apify paused) | working |
| 8 | Acquisition-target output contract (category + emirate + approvals → named campaign to bd) | expert |
| 9 | Regulatory readiness per category | working |
| 10 | Measurement hygiene (group per class; zero ≠ dead guard; fixtures excluded) | working |
| 11 | Weekly coverage board format for bd/onboarding | working |
| 12 | Fairness/concentration awareness | aware |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 budget fix | 1 SQL | **P1** |
| 1 Liquidity metrics & thresholds | expert | **partial** — marketplace_expert KPI records ("Liquidity by category", "Fill rate", "Reading a supply-count metric", "Group metrics per class") are dept_key=marketplace → unreachable; the one row has no numbers | re-scope those 6 KPI records to `supply` (alias or duplicate) + a policy record with the thresholds (depth 3, `matching_strike_limit` 3, floor 35) | 0 new + 1k | **P1** |
| Live pool visibility | expert | **missing** — no `health_fn` for supply (S-2); KPI actual NULL | `org_departments.supply.health_fn` = a `fn_ws_supply()` returning pool, verified, approved, per-category depth, demand-with-no-supply | 1 SQL fn | **P1** |
| 4 Supply floor / cold start | expert | **missing for this agent** — "Building a supply floor of three", "Cold-start a new category", "Choosing which category to fix first" are marketplace-scoped | re-scope to supply | 0 | P2 |
| 5 UAE supplier geography | expert | **partial** — one sentence (Dubai ≠ Sharjah) | `kb_chunks` category records per catalog category: cluster/emirate distribution computed from `leads` (`emirate`, `service_emirates`) + narrative | 86 × 0.5k | P2 |
| 6 Taxonomy | expert | **partial** — exists as data (catalog, 470 subcats, 1,839 keywords, 12 aliases); no knowledge record explains it | reference record: taxonomy design, alias policy, regulated flag, how a lead is scored into a category | 2k | P2 |
| 7 Lead-pool analytics | working | **partial** — no live view; `supplier_discovery` promotes 300/run | covered by the health_fn above | — | P2 |
| 8 Output contract | expert | **partial** — procurement's "Supply-demand balancing playbook" (825 chars) names it; not in coverage's rows | copy that row to supplier_coverage at priority ≥6 | 0.8k | P2 |
| 3 Demand signals | working | **partial** — "Seasonality and demand rhythm" reference is marketplace-scoped | re-scope | 0 | P3 |
| 9 Regulatory readiness | working | **partial** (catalog `regulated` flag; 20 activity rules) | see onboarding row 2 | — | P3 |
| 10 Measurement hygiene | working | **partial** (marketplace KPI records) | re-scope | 0 | P3 |
| 11 Coverage board format | working | **missing** | SOP/template record | 1k | P3 |
| 2 Failure taxonomy | expert | **present** (row) | — | — | — |

**Reasoning gap.** The row states the right frame (probability, three failure modes) but no thresholds and no numbers; with no Layer 3 and a NULL KPI actual the agent cannot compute coverage at all. 86 retrievals/30d show it is asked to; nothing bound in `employee_knowledge`. **P1 = 3.**

---

## 5. `supplier_retention` — Supplier Retention Specialist

**What it does today.** Specialist, reports `bd`, on_demand_specialist, execute_low (`analysis` supervised). Runs/7d: **3** (`ok`, lane determinations). Exam: **38% (6/16; 7 wrong)**, latest 4/5. Retrievals/30d: **0**. KPIs: supplier response rate target 60% — actual 100.00 (population = 1 approved supplier); suppliers gone quiet target 0 — actual 1. employee_knowledge: **0/12**. Packaged role: supplier-success operations specialist (26); readiness **blocked**.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (583 chars, priority 4) | 2026-08-11 | suppliers churn quietly (response rate falls first); four reasons in order (out-of-capability inquiries, too small, losing with no feedback, re-asked for documents) — three are the platform's fault; retention = matching quality + feedback |
| agent_knowledge experience | 8 | 2026-09-05 | exam gap-fills: 3 org_task lane determinations, decision-authority tiers, category pack files, "Developer Partnerships" — off-role |
| employee_knowledge | 0 | — | nothing bound |
| ops_knowledge reachable | supplier_success 416 (Supplier Coaching/Performance/Scoring/Support, SLA Management, Complaints topics; SOP 09 Supplier Complaint Handling) + bizdev + supply 8 + role 26 | Jul 2026 | |
| fn_agent_context | 26,425 chars | live | Layer 2 empty; no Layer 3 |

**Senior-staff standard — supplier retention / success manager**

| # | Domain | Depth |
|---|---|---|
| 1 | Churn leading indicators and the strike rule (3 consecutive unanswered RFQs → stops receiving; `matching_strike_limit`) | expert |
| 2 | Win/loss feedback loop (why a supplier lost; the 70/100 quote-quality rubric; reveal choice) | expert |
| 3 | Supplier SLA & responsiveness policy (response window; non-response 3% charge; due process before any charge) | expert |
| 4 | Reactivation / win-back playbook (distinct light track) | expert |
| 5 | Supplier standing composite (dispatch share, strikes, quality) and how it gates flow | working |
| 6 | Communication rules (brand voice; Arabic/English; WhatsApp template constraints; 21:00–07:00) | working |
| 7 | Licence-expiry pauses and recovery | working |
| 8 | Matching-quality diagnostics (derived vs confirmed capability; taxonomy mismatch) | expert |
| 9 | Retention economics (CAC vs LTV; cost of losing a verified supplier) | working |
| 10 | Cohort/stage reporting | working |
| 11 | Boundaries (no commercial-term changes; no confirming) | expert |
| 12 | Complaint handling SOP | working |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) | Layer 2 budget fix | 1 SQL | **P1** |
| 1 Churn indicators & strike rule | expert | **partial** — reasons listed; `matching_strike_limit` = 3 not in any knowledge row or context | policy record (dept supply): strike rule, response window, what "gone quiet" means (the KPI's SQL definition) | 1k | **P1** |
| 3 SLA & non-response charge & due process | expert | **partial** — "Supplier SLA and responsiveness" policy is marketplace-scoped; due-process row belongs to onboarding | re-scope the policy; copy onboarding's due-process row to supplier_retention | 0 + 1.1k | **P1** |
| 4 Reactivation playbook | expert | **missing for this agent** — "Supplier reactivation: winning back a churned or dormant supplier" is marketplace-scoped | re-scope to supply | 0 | P2 |
| 2 Win/loss feedback | expert | **partial** — "Quote quality scoring" rubric is marketplace-scoped; no template for the feedback message | re-scope + a communication template record (what a losing supplier is told, what is never disclosed) | 0 + 1.5k | P2 |
| 5 Supplier standing | working | **partial** — marketplace decision_playbook; legacy "Supplier Scoring" topic | re-scope | 0 | P2 |
| 8 Matching-quality diagnostics | expert | **missing** — nothing explains derived (15,306) vs confirmed (1) capability or how a mismatch is traced | decision_playbook: diagnosis tree from a supplier's "wrong inquiries" complaint to the taxonomy/capability fix | 2k | P2 |
| 6 Communication rules | working | **partial** — Layer 1 brand rows; "Supplier communication tone" policy marketplace-scoped | re-scope | 0 | P3 |
| 9 Retention economics | working | **partial** — marketplace KPI record | re-scope | 0 | P3 |
| 10 Cohort reporting | working | **missing** | template record | 1k | P3 |
| 7, 11, 12 | — | **present / legacy present** | — | — | — |

**Reasoning gap.** The row gives a correct causal ordering but no thresholds, no message templates and no worked case; the agent's own KPI ("gone quiet") is measured by SQL it cannot see. Readiness is `blocked`. **P1 = 3.**

---

## 6. `supplier_verification` — Supplier Verification Reviewer

**What it does today.** Specialist, reports `bd`, `independent_reviewer`, `stop_authority`; personal authority: `review_block` autonomous ("may block unsafe work, may never approve work it authored"), `supplier_verify` autonomous (threshold 0), `qualify_inquiry`/`compare_quotes` autonomous, the rest advisory. Runs: **0 in 30 days** (`agent_runs`); `decision_log action_gate` 138 rows, last 2026-08-16; review_chain as reviewer: 10 (`approve`, latest 2026-09-06); kb retrievals/30d: **57**. Exam: **25% (4/16)**, latest 3/5. KPI "primary objective" actual NULL. employee_knowledge 14 (procurement, supplier_mgmt, uae_authorities expert). Packaged role: **marketplace-operations-reviewer-auditor** (not a supplier-success role) — 26 records; readiness **blocked**.

The machinery it is accountable for: `license_extract` (model extraction), `fn_supplier_licence_gate`, `fn_check_licence_expiry`, `fn_check_licence_activity` (20/86 categories), `fn_supplier_autoapprove_clean`, `doc_expiry_scan`. Live data: 1 lead with licence fields, 0 with activity, 1 verified.

**Knowledge inventory**

| Source | Rows | Freshness | Domains covered |
|---|---|---|---|
| agent_knowledge profession | **1** (866 chars, priority 74) | 2026-08-06 | licence at the centre (activity covers the category; unexpired; issuer named; establishment card/owner match); general trading ≠ regulated activity; TRN; IBAN + bank letter with name match ("the single most common fraud signal"); insurance where required; manufacturer authorisations/ISO with expiry; verify with the issuing authority, never from the PDF alone; callback before accepting bank details |
| agent_knowledge experience | 8 | 2026-09-05 | exam gap-fills: 3 lane determinations, a category question policy, "Monthly operating and financial review — handoff 4", a field bank — 6 of 8 off-role |
| ops_knowledge reachable | supplier_success 416 (Trade Licences, Certifications, Document Fraud, Duplicate Accounts, Identity Verification, Sanctions And Restrictions, Licence And Document Expiry topics; SOP 02 Supplier Document Fraud Check, SOP 03 Licence Extraction And Verification, SOP 06 Automated Approval Gate) + role 26 | Jul 2026 | generic pack |
| NOT reachable | marketplace_expert "UAE trade license verification: the decision rule and what to verify", "Supplier approval decision: the five-gate onboarding funnel", "Category capability verification beyond the license", failure modes "The fake supplier", "Duplicate and linked supplier accounts", "The ghost supplier"; `trust_safety` 134 | 2026-09-02 | dept_key=marketplace / trust_safety — outside `fn_dept_scope('supply')` (derived) |
| fn_agent_context | 26,618 chars | live | Layer 2 empty; Layer 1 16 items 10,150 chars; Layer 4 3 off-role items |

**Senior-staff standard — senior supplier verification / KYC reviewer, UAE**

| # | Domain | Depth |
|---|---|---|
| 1 | Licence authenticity per issuing authority: verification services (DET verify, ADDED/TAMM, SEDD, Ajman, RAK, Fujairah, UAQ, ≈40 free zones), MoE National Economic Register, licence-number formats, QR/e-licence features | expert |
| 2 | Licence anatomy: legal form, licence type (commercial/professional/industrial), activity list and codes, manager/partners, issue/expiry, establishment card | expert |
| 3 | Activity-to-category coverage rules for all 86 categories incl. regulated add-ons | expert |
| 4 | Regulated permits and how to verify each (DCD approval/CoC, SIRA licence, DM permits, DEWA/ADDC contractor grade, RTA, MOCCAE, MOIAT/ECAS, DHA/DoH, Legal Affairs, RERA broker card, FTA tax agent) | expert |
| 5 | Certification verification (ISO 9001/14001/45001 via EIAC/IAS/UKAS-accredited bodies; certificate registries; manufacturer authorisation letters; insurance schedules CAR/PL/WC) | expert |
| 6 | Fraud & forgery detection (metadata, font/kerning, QR mismatch, duplicate licence numbers across accounts, shared phones/devices, disposable domains, IBAN name mismatch, callback) | expert |
| 7 | Sanctions/restricted-party stance (UAE EOCN local list, UN list) consistent with "not AML-regulated" | working |
| 8 | Identity linkage (licence = bank = signatory; MoA/POA) | expert |
| 9 | TRN validation (15-digit; FTA lookup) | working |
| 10 | Decision contract: approve / refuse / suspend with recorded reason; stop authority; never approve own work | expert |
| 11 | The deterministic gates it owns (auto-approve predicate; expiry > +30d; activity rule coverage; licence gate reasons) | expert |
| 12 | Expiry monitoring & suspension (reminder at 7 days; suspension; grace reconcile) | working |
| 13 | Capability confirmation scoring (derived vs confirmed; SOP 05) | expert |
| 14 | PDPL handling of Emirates ID/passport (redaction, retention) | working |
| 15 | Appeals & due process | working |
| 16 | Worked examples: 8–10 real licence layouts and 10 approve/refuse cases with reasons | expert |

**Gap table**

| Domain | Required | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Own profession layer in the prompt | — | **missing** (S-1) — the best verification row in the estate reaches nobody | Layer 2 budget fix | 1 SQL | **P1** |
| 1 Authenticity per authority | expert | **missing** — "verify with the issuing authority" with no method, portal, number format or QR feature | UAE trade licence handbook (shared with onboarding row 1) + `agent_knowledge` profession row per major authority | 20k | **P1** |
| 3 Activity coverage for 86 categories | expert | **partial** — 20/86 regexes; 0 leads with activity captured → the gate refuses everything else | extend `category_licence_activity` to 86; wire extraction → `leads.license_activity` | 66 rows | **P1** |
| 11 Its own deterministic gates | expert | **missing** — no row states the predicate; the agent cannot explain an auto-approval or a refusal | policy record generated from the function bodies (shared with onboarding) | 1.5k | **P1** |
| 4 Regulated permits & verification | expert | **partial** — category chunks name authorities (SIRA 323, DCD 622 mentions); no verify method or permit anatomy | reference per regulator (shared with onboarding row 5) | 12k | **P1** |
| 6 Fraud & forgery | expert | **partial** — IBAN mismatch + callback in the row; the marketplace failure modes "fake supplier / duplicate accounts / ghost supplier" and "UAE trade license verification: the decision rule" are unreachable (dept scope) | re-scope those 5 marketplace_expert records to supply; add a forgery-tell checklist record (document forensics: metadata, fonts, seal, QR) | 0 + 2k | P2 |
| 5 Certification verification | expert | **partial** — expiry extraction exists; no accreditation/registry check knowledge | reference: ISO certificate validation (accreditation body lookup, certificate registries, scope statement), insurance schedule reading | 2.5k | P2 |
| 7 Sanctions stance | working | **partial and contradictory** — legacy "Sanctions And Restrictions" topic vs onboarding's "do NOT perform sanctions/PEP screening" | one policy record settling the stance (founder/GC input on whether a list check is done) | 0.5k | P2 |
| 13 Capability confirmation | expert | **partial** (legacy SOP; 1 of 15,306 confirmed) | see onboarding row 13 | — | P2 |
| 16 Worked examples | expert | **missing** | 10 anonymised approve/refuse cases with the evidence and the rule that decided each (from real reviews once they exist; seed with ZZ DEMO fixtures) | 8k | P2 |
| 9 TRN | working | **partial** | 0.4k appended | 0.4k | P3 |
| 12 Expiry & suspension | working | **partial** — policy in onboarding's row; `doc_expiry_scan` runs with 0 actions | copy row; state the 7-day/expired/grace rules as a policy record | 0.8k | P3 |
| 14 PDPL handling | working | **partial** (onboarding row; "Data minimisation" gap-fill) | copy | 0 | P3 |
| 15 Appeals | working | **partial** (onboarding's due-process row; SOP 08 legacy) | copy | 0 | P3 |
| 2, 8, 10 | expert | **present** (row + role contract) | — | — | — |

**Reasoning gap.** The row is a genuine senior checklist and even names the top fraud signal — but it is 866 characters, reaches no prompt, and carries no per-authority method, no scored rubric and no example. The agent has not run in 30 days; the deterministic gate refuses on activity for 66 of 86 categories and on "not captured" for every lead because the extraction never writes `license_activity`. Its packaged role is a marketplace reviewer, so the fraud/verification playbooks written for it sit in a scope it cannot reach. **P1 = 5.**

---

## Department summary — Supply

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| bd | 4 | 7 | 1 |
| onboarding | 5 | 7 | 1 |
| partnerships_mgr | 2 | 8 | 1 |
| supplier_coverage | 3 | 5 | 4 |
| supplier_retention | 3 | 4 | 3 |
| supplier_verification | 5 | 5 | 4 |
| **Total** | **22** | **36** | **14** |

Six of the 22 P1s are the same platform defect (S-1, one SQL change in `fn_agent_context`). Net of that: 16 P1 ingest items.

**Top 5 ingest items (department)**

1. **Fix the Layer 2 budget in `fn_agent_context`** so the profession rows (17 rows, 12.5k chars across the six agents) reach the prompt — today 0 of them do. Then give Supply a `health_fn` (`fn_ws_supply`) so Layer 3 exists.
2. **UAE trade-licence handbook** (per issuing authority: layout, fields, number format, legal forms, verification service/QR) — `ops_knowledge` reference, dept `supply`, plus one profession row each for onboarding and supplier_verification. ≈20k chars. Sources: DET, ADDED/TAMM, SEDD, MoE NER, free-zone portals (*verify* each).
3. **Activity-to-category coverage for all 86 categories** — extend `category_licence_activity` from 20 to 86 rows and write `license_extract.activities` into `leads.license_activity` (0 of 21,665 today), plus a regulated-permit verification guide (DCD, SIRA, DM, DEWA/ADDC, MOIAT/ECAS, RTA, MOCCAE, DHA/DoH, Legal Affairs, RERA, FTA) as reference records.
4. **The department's own decision rules as records**: the auto-approve predicate and licence-gate reasons (generated from the function bodies, deterministic=true), and the thresholds Supply acts on (`matching_strike_limit` 3, response window, non-response 3%, "gone quiet" definition) — today in `decision_policy`/SQL only, in no context.
5. **Re-scope 15 marketplace_expert records to Supply** (trade-licence decision rule, five-gate approval funnel, fake/duplicate/ghost supplier failure modes, supply floor of three, cold-start, liquidity KPIs, supplier standing, reactivation, SLA policy, communication tone) via `org_department_alias` or duplicate rows — 0 new text — and add for bd a "what BD may promise" row + a 15-objection library from the published T&C.

**What could not be measured.** kb_chunks by `source_kind` over the whole table (statement timeout; `kb_category_stats` used instead: ≈2.68M chunks); the semantic reach of `fn_ops_knowledge_match` (needs an embedding = model call; not run); the 3-arg/`_capped` context path (VOLATILE — writes a retrieval row; not executed); `dept_library` contents; `agent_evals` (no per-agent column); verification decision quality (0 real applications reviewed; 1 approved supplier); capability-confirmation scoring accuracy (0 confirmations); real routing/matching outcomes (0 inquiries, 0 quotes); whether `phase_b_sla` rows are wired to these agents (not queried). Clause numbers in the published T&C/Supplier Agreement were not opened (*verify* before quoting them in records).
