# Knowledge audit — Finance department (5 AI employees)

Measured 6 Sep 2026 02:00–03:30 UTC against production `htdblwldjkcgjvmqkbeh`, read-only. Every number below was
read from a table or a function in the same session; where a number could not be measured it says so.
Scope: `org_agents.active = true and department = 'finance'` → `cfo`, `bookkeeper` (title: Financial
Controller), `collections`, `billing_specialist`, `payments_manager`.

## 0. Findings that apply to all five (read this first)

**F1. The professional-expertise layer never reaches any finance employee.** `fn_agent_context()` emits
`# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` at exactly **38 characters (the heading only) for all 5 finance
agents** (and for all 12 agents in exec/finance/legal) — on both overloads, including the production path
`fn_agent_context_capped(key, 24000, query)` that `agent_brain` calls. Cause, read in
`scripts/sql/fn_agent_context_workload_names_the_holding_role.sql` line 384: a profession row is admitted only
while `length(out)+length(piece) <= own_cap + 2200` (own_cap = 6,000), but `out` already holds the genome block
(2,651 chars), the live risk register (3,039) and the employee record (up to 6,200) — ~12,000 chars — before the
loop starts, so no piece can ever pass. The CFO's 17 profession topics (UAE VAT, corporate tax, TP, IFRS 15 …)
exist in `agent_knowledge` and are never shown to it. The `v_pad` compensation at line 280 only pays for the
OS-owner line, not for the two blocks inserted above the layers.

**F2. The production prompt is cut at 19,500 chars of standing context + 4,500 of retrieval.** Probed with an
aborted `DO` block (nothing committed) for all 5: `fn_agent_context_capped` returns 24,155 chars; the head is
"trimmed to the first 19,500 characters of 30,084–32,122"; what is cut is everything after LAYER 1: **LAYER 3
live operational state, LAYER 4 learned lessons, the OS objectives, the target-operating-model digest, and — in
the tail — LAYER 2d role knowledge (never reached for finance), LAYER 2f deterministic rules (never reached for
any agent) and LAYER 2g facts-to-fetch (never reached).** The 4,500-char tail holds 1–2 department-library
snippets plus ~1,300 chars of LAYER 2c (two 700-char `fn_ops_knowledge_search` hits). So a finance employee
answers with: identity + constitution + risk register + KPIs + workload + ~6.5K of company canon (brand,
AI constitution, response structure, pricing LIVE, FAQ header, 5 explainability stubs) + ~4.5K of retrieval.
No live finance numbers (fn_ws_finance is cut), no rules layer.

**F3. The exam does not measure finance competence.** `knowledge_exam` grounds the examinee on
`kb_search(category = agent_key)`; kb_chunks with category `cfo` = 21 chunks, `bookkeeper` = 4,
`collections` = 4, `billing_specialist` = 1, `payments_manager` = 1 (the 53,718 `finance` chunks are not
used). Of the 11 questions per agent, 5 are "What does the company's operating knowledge say about:
<pack file name>" (recall of YAML/JSON file names, several from unrelated trade routes such as
`rfq_quality_gate.yaml` for Corporate Service Providers); `payments_manager` has 10/10 such questions and 0
domain questions. Score = correct/all; partial counts as a gap. Company-wide 30-day score measured 26.3% (the
Governance page shows 26.2%).

**F4. The senior-expert rows carry no company numbers and no statute numbers.** 94 `ops_knowledge` rows for
finance have `source_authority = 'senior_expert_uae'` (2 Sep 2026; 23 decision playbooks, 14 failure modes,
15 KPI definitions, 13 policies, 12 references, 7 remediations, 10 authority statements; avg 1,874 chars).
Across all 94: mentions of "3%" = 0, "375,000" = 0, "47/2022" = 0, "Stripe" = 2; `escalation_rule` = `{}` on
all 94; 9 of 131 decision-bearing finance rows contain an AED figure, 5 contain a worked example. They are
good frameworks ("13-week cash flow", "recognise reveal fee at the point the service is delivered") written
without QuotesDone's thresholds or the law's numbers.

**F5. Retrieval for functional staff is unscoped.** `agent_brain.retrieve()` calls `kb_search` with no category
for non-`cat:` agents (k = 8 over 2,686,026 chunks in 356 categories); the finance corpus is 2% of the pool.
Keyword retrieval over ops_knowledge (`fn_ops_knowledge_search('finance', …)`) returned, for "refund reveal fee
supplier did not respond": FAQ — Customer, FAQ — Company Policies, FAQ — Financial, 00_DEPARTMENT_MASTER.md,
01_ADVANCED_PROFESSIONAL_CURRICULUM.md — not the "Refund reason taxonomy" policy or the "Refund case file"
playbook that exist in the same table. (Semantic `fn_ops_knowledge_match` was not exercised: it needs an
embedding call.)

Department-level inventory (shared by all five through `fn_dept_scope('finance') = {finance, payments}`):

| Source | Rows | Freshness | What it covers |
|---|---|---|---|
| ops_knowledge dept_key=finance | 517 (412 V2 delivery pack 31 Jul 2026, 94 senior_expert_uae 2 Sep 2026, 11 other) | newest 4 Sep 2026 | 20 SOPs (Reveal Checkout, Payment Confirmation, Invoice Generation, Payment Reconciliation, Reveal-Fee Recognition, Webhook Processing, Failed-Payment Recovery, Refund Accounting, Monthly Close, Refund Request, Payment Dispute, VAT Review, CT Evidence Retention, Subscription Billing, Cash Forecast, Daily Reconciliation, Provider Incident, Spend Optimization …); 27 decision playbooks; 20 generic decision rules ×2 copies; 20 generic exception playbooks ×2; 13 policies; 12 references; 15 KPI definitions; 40 "knowledge_domain" + 38 "operational_application" + 38 "control_requirements" pack rows. implementation_status: 50 active, 40 target_state, 10 implemented, 10 partial. |
| ops_knowledge dept_key=payments | 140 (all V2 pack yaml/md/json) | 31 Jul 2026 | role packs for 4 payments-and-revenue-operations roles (27 files each), 2 escalation rules |
| ops_knowledge role_key finance-* | 4 roles × 27 rows | 31 Jul 2026 | role_charter, senior_judgment, decision_playbooks.yaml, escalation_matrix.yaml, 8 failure modes each |
| kb_chunks category=finance | 53,718 chunks, 388 sources, 17,140 distinct titles | 10 Jul–29 Aug 2026 | FTA CT guides (fta:ct-* ~12 guides incl. returns, SBR, free-zone, TP, tax groups), CT Law 47/2022 + explanatory guide, VAT Decree-Law 8/2017, VAT Executive Regulation, FTA VAT guides (e-commerce, financial services, input-tax apportionment, designated zones, real estate, returns user guide), IFRS for SMEs 2015, IAASB 2022 handbook, IESBA code, IMA framework, OpenStax/LibreTexts accounting & finance textbooks, BIS/World Bank reports, IPSAS handbooks (public-sector, not relevant) |
| kb_chunks other finance-adjacent | accounting-finance-and-corporate-services 66,306; banking-and-financial-products 25,320; insurance 59,274; tax-consultants 15 | 29–31 Aug 2026 | supplier-category corpora (for RFQ routing), not for the finance function |
| decision_policy | 38 keys | live | financial_review_aed 10000; auto_action_max_aed 0; refund_reveal_fee_pct 3; refund_admin_fee_aed 250; refund_late_fee_annual_pct 9; refund_notify/call/claim working days 1/3/3; refund_executor_role_id payments_and_billing_manager; refund_reconciler_role_id financial_controller; founder_review_gates [refund_decision, refund_outside_policy]; confidence_min 0.6 |
| governance_rule / governance_policy | 11 / 16 | live | "money movement above AED 10,000 → founder"; finance owns policies "Spend thresholds" and "VAT" (enforcement=database) |
| phase_b_business_rule | 54 (BR-020 payment before reveal, BR-021 3% reveal, BR-022 no supplier commission, BR-023 founding-supplier exemption, BR-031 execution/reconciliation separation, BR-032 provider-event idempotency, BR-033 unknown monetary state visible, BR-052 one payment source of truth) | frozen 15 Aug 2026 | hard rules, no thresholds |
| company_economics | 10 rows, all every_employee_must_know | live | reveal 3%, supplier AED 1,000/yr (first 1,000 free), PSP ~2.9% + AED 1, break-even "AED 7,700/month declared", refund window 3 working days |
| company_constitution art. 10 "Financial principles" | 1 of 20 | 26 Jul 2026 | in the genome block of every prompt |
| phase_b_sla_policy | 34 rows; 0 match refund/invoice/billing/dispute/finance by name | — | no finance SLA measured by name (scope column may use W-codes; not resolved) |
| employee_authority | see per agent | 14 Aug 2026 | tiers per action class |

---

## 1. `cfo` — Chief Financial Officer (org_role `cfo`, director, reports to ceo)

**What it does today.** agent_runs 7d: 2 (1 ok, 1 skipped). Context assemblies 30d: 266 (`agent_context_retrieval`,
63 knowledge ids each; kb_usage_log 254, categories only `_global/agent_context/context_assembly` — these are
assembly logs, not domain retrievals). review_chain as author: 87 rows (57 approve, 0 reject); as reviewer: 54.
artifact_review: 0. Exam: 26 results since 13 Aug, **6 correct / 1 partial / 8 wrong / 10 not_covered =
23.1%** (30d 23.1%); domain questions only: 3/16 = 18.8%; 5 gaps auto-filled. Wrong on: "primary KPI
pre-launch", "fee structure for suppliers registering before 31 Jul 2027" (its own founding-supplier rule),
Dubai Customs/DET registration, `finance-director.fm01` (confusing cash with revenue).

**Persona.** owned_decisions: budget allocation and caps; spend approval within founder limits; financial
policy; runway/forecast. forbidden: refund without founder; approving own reconciliation; changing revenue
recognition to meet a target. authority_level execute_medium, budget_limit AED 10,000; employee_authority:
collections_chase / expense_log / forecast / invoice_review / money_verify all **gated at AED 10,000**.
tools: ap_duplicate_scan, collections_chase, dispute_open, expense_log, forecast, invoice_review,
money_verify, spend_check. evaluation_suite eval_financial_control (no rows in `v_eval_latest`/`agent_evals`
name it). agent_action_kind_policy: authority for `finance_alert:notify`.

**Knowledge inventory (agent-specific).**

| Source | Rows / size | Freshness | Covers |
|---|---|---|---|
| agent_knowledge profession | 17 topics, avg 801 chars, all `unvalidated` | last updated **24 Jul 2026** | uae_vat_marketplace (names FDL 8/2017; says "verify current AED threshold with the FTA" — threshold not stated), uae_corporate_tax, Verified UAE references (CT 0/9%, SBR AED 3M MD 73/2023, FTA Decision 3/2024, MD 114/2023 — correct), esr_and_pillar_two_status, related_party_transfer_pricing, revenue_recognition_reveal_fees, aml_kyc_compliance, audit_controls_readiness, cash_treasury_and_collections, fpna_unit_economics, islamic_finance_awareness, accounting_standards_and_close, Treasury & payment controls policy, Professional standard (CFA/CPA/CMA), Role & expertise, Deepened playbook. **None of it reaches the prompt (F1).** |
| agent_knowledge experience | 9 rows | 5 Sep 2026 | 5 exam auto-fills that are trade-route YAML (rfq_quality_gate.yaml, 02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml …) — noise; 4 real lessons (cash burn, revenue_30d $0) |
| employee_knowledge | 12 domains | — | finance@expert, uae_tax@expert, company/goals/constitution/priority/universal@expert, legal_uae/procurement/sales_crm@awareness, quotesdone_os@working, communication@working. `v_employee_knowledge_compliance`: 5 of 12 layers bound → INCOMPLETE |
| ops_knowledge scope agent | 0 | — | (the 96 agent-scoped rows belong to packaged role ids, none to `cfo`) |
| exam question bank | 11 (5 pack-recall, 6 domain) | 5 Sep 2026 | topics authority/compliance/domain/pricing |
| fn_agent_context('cfo', 22000) | 30,084 chars, 22 sections; production head 19,500 | live | LAYER 1 = 8,590 chars: Brand wording, Document branding, AI Constitution, Standard AI Response Structure, AI governance gate, Retrieve before answering, RFQ completeness rule, Pricing & fees (LIVE), Company FAQ header, 5 × [AI Explainability] stubs, canon:core. LAYER 2 = empty. LAYER 3 (fn_ws_finance, 2,728 chars) present on the 2-arg call, **cut in production**. LAYER 4 = 3 exam-fill YAML fragments. Production tail: "VAT control checklist", "Tax Risk Register", "Emiratization (Nafis) Impact", "Fraud Risk Scenarios" (dept library) + playbook "Monthly financial close" + 156 chars of the Finance pack master. |

**Senior-staff standard — CFO of a UAE B2B marketplace (what a top CFO carries in their head).**

| # | Domain | Depth |
|---|---|---|
| 1 | UAE VAT: Federal Decree-Law 8/2017, Executive Regulation (Cabinet Decision 52/2017 as amended — verify latest amendment), 5% rate, AED 375,000 mandatory / AED 187,500 voluntary registration, tax-invoice content, simplified invoices, return by the 28th, place of supply for electronically supplied services, zero-rated export of services, reverse charge, input-tax recovery/blocked items, EmaraTax | expert |
| 2 | UAE Corporate Tax: FDL 47/2022 (+60/2023), 0%/9% at AED 375,000, Small Business Relief (MD 73/2023, revenue ≤ AED 3M, to periods ending ≤ 31 Dec 2026), registration deadlines (FTA Decision 3/2024) and AED 10,000 late penalty, return + payment 9 months after period end, MD 114/2023 accounting standards (IFRS; IFRS for SMEs ≤ AED 50M revenue; cash basis ≤ AED 3M), audit requirement thresholds (verify current MD), interest cap, loss carry-forward | expert |
| 3 | Transfer pricing & related parties: arm's-length (CT Law Arts 34–36), founder remuneration, disclosure form thresholds (verify MD 97/2023 figures), connected-person payments | working |
| 4 | Tax procedures: Federal Decree-Law 28/2022 Tax Procedures Law, 5-year record retention (longer for real estate), voluntary disclosure, penalty regime (Cabinet Decision 49/2021 — verify), FTA audits, clarifications, tax agent relationship | expert |
| 5 | UAE e-invoicing (Peppol PINT-AE, Accredited Service Providers, MoF phased mandate from 2026 — verify phase dates) and what it means for reveal-fee invoices issued by an automated platform | working |
| 6 | IFRS revenue recognition for the model: IFRS 15 five-step; reveal fee = point-in-time on reveal; supplier subscription = over 12 months (deferred revenue); agent vs principal (QD is not party to the supply contract); refund liabilities/variable consideration; IFRS 9 ECL on receivables; IAS 37 chargeback provisions; IFRS for SMEs option | expert |
| 7 | Marketplace unit economics: 3% take rate on quote value, PSP 2.9% + AED 1, AI cost per reveal, contribution margin, CAC/LTV/payback, GMV vs net revenue, the AED 1M back-solve, break-even (AED 7,700/month declared) | expert |
| 8 | Cash, treasury, runway: 13-week cash flow, encumbered vs free cash, three cash pools (operating/tax-held/customer-held), AED–USD peg 3.6725 and FX on card charges, bank/deposit choices, no fund-holding (CBUAE Stored Value Facilities / Retail Payment Services regs would apply if QD ever held buyer funds) | expert |
| 9 | Stripe economics and controls: payout timing/reserves, dispute fees and evidence deadlines, refunds vs reversals, Radar, webhook idempotency, Stripe test vs live mode | working |
| 10 | Refund & reveal-fee policy as a control: 3% reveal, 3-working-day window, notify/call/claim 1/3/3 days, AED 250 admin fee, 9% p.a. late fee, supplier non-response 3% rule, founder approves every refund, executor = payments_and_billing_manager, reconciler = financial_controller | expert |
| 11 | Company financial governance: founder gates (refunds; spend above budget; subscription price/start date; reveal % are founder-reserved), AED 10,000 money-movement rule, department budgets, segregation of duties in an autonomous finance function | expert |
| 12 | Month-end close and controls: three-way match, Stripe↔ledger↔invoice reconciliation, deferred-revenue proof, bank reconciliation, chart of accounts for a reveal-fee marketplace, audit-ready folder | expert |
| 13 | Statutory & corporate: CCL FDL 32/2021 audited accounts for an LLC, UBO register (Cabinet Decision 109/2023 — verify), licence renewal costs (DET / free zone), ESR abolished (Cabinet Decision 98/2024 — verify) | working |
| 14 | AML/CFT scope: FDL 20/2018 (+26/2021) and executive regulation, DNFBP list (a fee-collecting RFQ marketplace is normally outside it — document the determination), goAML, sanctions screening via EOCN/UN lists as best practice | working |
| 15 | Budgeting, variance and driver-based forecasting; zero-based review of fixed cost; the LLM/API bill as the variable cost (tier mix, cache) | expert |
| 16 | Board/founder reporting: exception-first one-pager, runway, cohort and liquidity metrics; decision records with options/risks/reversibility | expert |
| 17 | Payroll/labour cost awareness (WPS, end-of-service under FDL 33/2021) for when the first human hire happens | aware |
| 18 | Procurement finance for QD's own vendors: PO/invoice/tax-invoice gate before payment, duplicate-invoice scan | working |
| 19 | Fraud & revenue assurance: card testing, refund-abuse rings, fixtures counted as revenue, "a 30-day total is not a run rate" | working |
| 20 | Live-data discipline: which numbers must be fetched (`fn_ws_finance`, ai_cost_log, Stripe) and never remembered | expert |

**Gap table.**

| Domain | Depth | Today (evidence) | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 VAT | expert | **partial** — kb_chunks finance has VAT law, exec reg, FTA guides (returns user guide, e-commerce, input tax); agent_knowledge `uae_vat_marketplace` (664 chars, threshold left as "verify"); senior rows "UAE VAT on reveal fees", "Input VAT recovery", "Tax invoice content", "Filing the VAT return"; exam: bookkeeper wrong on retention & invoice fields. Nothing of it is in the prompt (F1), and the corpus is unscoped (F5). | ops_knowledge finance `reference` "UAE VAT facts for the reveal-fee model": rate, both thresholds, invoice fields (Art. 59 Exec Reg — verify), 28th-day return, place-of-supply rule for the reveal fee to a non-UAE buyer, 20-business-day voluntary disclosure (verify), penalty table; with `structured_data` thresholds and an `escalation_rule`. Plus a `decision_policy` key `vat_registration_threshold_aed = 375000` and `vat_rate_pct = 5`. | 6–8 pages / 15 chunks | **P1** |
| 2 Corporate Tax | expert | **partial** — agent_knowledge "Verified UAE references" is correct on 0/9%, SBR, MD 114/2023 (not delivered); kb has CT law + 12 FTA guides; senior rows "UAE Corporate Tax: the 9% question", "Corporate Tax reliefs to check", "CT cash provisioning". No QD-specific application (SBR election yes/no, registration deadline for QD's licence month, first period). | ops_knowledge finance `policy` "QuotesDone CT position": registration status/deadline, SBR election decision rule (revenue ≤ AED 3M → elect until 2026; what changes in 2027), accounting basis chosen, return due date, evidence retention; `decision_policy` `ct_small_business_relief_elected`, `ct_first_period_end`. Facts only the founder holds (TRN, licence date) marked as fetch-not-remember. | 4 pages / 8 chunks | **P1** |
| 3 Transfer pricing | working | partial — agent_knowledge `related_party_transfer_pricing`; senior playbook "Founder remuneration: salary vs dividend, TP and CT angles"; kb has fta:ct-guide-transfer-pricing | one ops_knowledge `reference` with the disclosure thresholds (verify MD 97/2023) and the founder-payment rule | 2 pages / 4 chunks | P2 |
| 4 Tax procedures | expert | **missing** in structured form — kb has no `law:uae-tax-procedures-28-2022` source id in the 462 UAE-ish ids listed (list truncated; verify); retention "5 years" appears only as an exam grader fact; bookkeeper answered it wrong twice | kb_chunks category finance: Tax Procedures Law FDL 28/2022 + Cabinet Decision 74/2023 exec reg + Cabinet Decision 49/2021 penalties (verify current); ops_knowledge `reference` "Tax procedures calendar and retention" | 60 pages / 150 chunks + 2 pages | **P1** |
| 5 E-invoicing | working | partial — senior `reference` "UAE e-invoicing readiness for an automated marketplace" (no dates, no ASP) | ops_knowledge `reference` with MoF phase dates and ASP obligation (verify), plus the invoice-numbering/PINT-AE fields QD's invoice generator must emit | 3 pages / 6 chunks | P2 |
| 6 IFRS revenue recognition | expert | partial — senior playbook "Revenue recognition for reveal fees: recognise at the point the service is delivered", failure mode "Deferred revenue and prepaid reveal credits", remediation "Deferred-revenue reconciliation"; agent_knowledge `revenue_recognition_reveal_fees`; kb has IFRS for SMEs 2015 (the 2025 third edition not present — verify). No principal/agent analysis, no supplier-subscription schedule, no ECL policy. | ops_knowledge finance `policy` "Revenue recognition policy (IFRS 15/9/IAS 37) for QuotesDone": reveal, subscription, refunds, chargebacks, receivables ECL, with journal templates; kb_chunks: IFRS 15 and IFRS 9 standard text (IFRS Foundation licence — verify) or the FTA-referenced IFRS for SMEs 2025 edition | 8 pages / 20 chunks + standards 200 chunks | **P1** |
| 7 Unit economics | expert | **partial** — company_economics 10 rows (in genome? no: company_economics is not in the prompt sections measured; company_faq is); senior KPI rows (CAC/LTV, contribution margin per reveal, the AED 1M back-solve) contain no numbers; exam: CFO wrong on pre-launch KPI and supplier fee structure | ops_knowledge finance `reference` "QuotesDone economics — the numbers" generated from company_economics + decision_policy (3%, 2.9%+AED 1, AED 1,000/yr, first-1,000 free until 31 Jul 2027, break-even 7,700/month, target AED 1M by 31 Aug 2027) marked LIVE-fetch; ensure company_economics is emitted in the prompt | 2 pages / 3 chunks | **P1** |
| 8 Cash/treasury/runway | expert | partial — senior playbook "13-week cash flow", policies "Separate the three cash pools", "Where to hold cash", "Reserve discipline"; fn_ws_finance live state exists but is cut from production (F2) | fix F2 (deliver LAYER 3); add ops_knowledge `standard_operating_procedure` "Weekly runway and 13-week cash update" bound to `forecast` tool with the encumbered-cash formula | 2 pages / 4 chunks | **P1** (delivery) |
| 9 Stripe | working | partial — senior reference "Payment-processor economics", playbooks "Chargebacks and disputes", "Dispute-response SLA", "Billing descriptors"; only 2 of 94 senior rows mention Stripe; no Stripe UAE facts (settlement currency, payout schedule, dispute fee, evidence window) | ops_knowledge finance `reference` "Stripe UAE facts for QuotesDone" (fees on file, payout schedule, dispute fee AED — verify from the Stripe dashboard, evidence deadlines by network, refund vs reversal, test-mode rule); kb_chunks: Stripe docs on disputes/refunds/payouts (Stripe MCP is attached — the docs can be pulled without a paid call) | 10 pages / 25 chunks | P2 |
| 10 Refund & reveal-fee policy | expert | **present as numbers, absent as reasoning** — decision_policy has all 8 refund keys; senior policy "Refund reason taxonomy", playbook "Refund case file"; but keyword retrieval for a refund question returns the FAQ files, and the numbers sit in decision_policy which is not in the prompt (only "Pricing & fees LIVE" 966 chars is) | ops_knowledge finance `decision_playbook` "Refund decision tree for the CFO" that cites the decision_policy keys by name, the founder gate, executor/reconciler roles, and 3 worked examples (supplier no-response; buyer remorse inside/outside 3 working days; chargeback) with the ledger entries | 4 pages / 8 chunks | **P1** |
| 11 Financial governance | expert | present — constitution art. 10, governance_rule 3 (AED 10,000 → founder), founder_reserved_decision 11 rows, employee_authority tiers, authority rows "Every refund reaches the founder", "Expense approval authority" (in prompt: constitution yes; authority yes; founder_reserved rows not measured in prompt) | none beyond delivery (LAYER 2f is cut — F2) | — | P2 (delivery) |
| 12 Month-end close & controls | expert | present in ops_knowledge — SOPs Monthly Close, Daily Reconciliation, Payment Reconciliation; senior playbook "Monthly financial close" (reached the CFO's tail in the probe); reference "Chart of accounts" | add worked close checklist with QD's actual ledger tables (`transactions`, Stripe event tables) as `structured_data` | 2 pages | P2 |
| 13 Statutory & corporate | working | partial — senior reference "Registration triggers: VAT, CT, UBO, compliance calendar"; kb has CCL 32/2021 and ADGM BO regs; no QD licence facts | ops_knowledge `reference` "QuotesDone corporate calendar" (licence authority & renewal month, auditor, UBO filing, CT/VAT dates) — facts from the founder marked verify | 1 page | P2 |
| 14 AML scope | working | partial — agent_knowledge `aml_kyc_compliance`; senior authority "Determining AML/DNFBP scope: verify, do not assume", playbook "AML transaction monitoring"; kb has law:uae-aml-20-2018 + exec reg | ops_knowledge `policy` "AML scope determination for QuotesDone" (not a DNFBP/FI; what would change that: holding funds, precious metals category; screening practice) | 2 pages | P2 |
| 15 Budget/forecast | expert | partial — senior playbooks "Driver-based forecasting", "Expense control", KPI "annual budget as a contract"; `forecast` tool gated at AED 10,000; department_budget table exists (AED 7,700/month declared) | ops_knowledge `standard_operating_procedure` "Monthly budget variance review" with the variance thresholds that trigger an initiative (e.g. >15% or > AED 1,000 — to be set) | 2 pages | P2 |
| 16 Founder reporting | expert | present — senior playbook "Founder financial reporting: the exception-first one-pager"; output_contract `financial_report` | worked example of one report | 1 page | P3 |
| 17 Payroll/labour | aware | partial — dept library snippet "Emiratization (Nafis) Impact" reached the tail (irrelevant at 0 employees); kb has labour law 33/2021 | nothing now; mark aware | — | P3 |
| 18 Procurement finance | working | present — senior playbook "Procurement finance: three-way match and the tax-invoice gate"; tool ap_duplicate_scan | — | — | — |
| 19 Fraud & revenue assurance | working | present — 14 senior failure modes incl. "Card-testing", "Refund-abuse rings", "fixtures counted as real revenue", "a 30-day total is not a run rate" | — | — | — |
| 20 Live-data discipline | expert | **missing in delivery** — LAYER 2g "FACTS YOU MUST FETCH" is never reached (F2); LAYER 3 cut | fix F2 | — | **P1** (delivery) |

**Reasoning gap.** Thresholds exist as numbers (decision_policy: 10,000 / 250 / 3 / 9 / 1-3-3 / 0.6) and rules
exist as prose (94 senior rows), but nothing joins them: the playbooks carry `escalation_rule = {}`, no
finance playbook cites a decision_policy key, 9 of 131 decision-bearing rows carry an AED figure, 5 carry an
example. The "WHEN TO ESCALATE" block every finance agent sees is 306 characters and generic (hold_and_escalate
/ open_incident_and_escalate / create_owned_escalation / hold_and_review). What a senior CFO needs and does not
have in front of it: (a) a refund decision tree with the company's numbers and three worked cases; (b) a
spend-approval ladder (≤ AED 10,000 gated to CFO, > AED 10,000 founder, "spend above budget" founder-reserved)
written as one rule with examples; (c) VAT/CT decision rules with the statutory numbers; (d) the live state
(fn_ws_finance) it is told to quote from — currently cut. Its exam answers show the consequence: it got its own
supplier fee exemption wrong.

**P1 count: 8** (VAT, CT, tax procedures, IFRS revenue policy, unit-economics numbers, cash/runway delivery,
refund decision tree, live-data delivery).

---

## 2. `bookkeeper` — Financial Controller (org_role `financial_controller`, specialist, reports to cfo)

**What it does today.** agent_runs 7d: 2 ok. Context assemblies 30d: 0 in agent_context_retrieval (kb_usage_log:
none). review_chain author: 35 (21 approve); reviewer: 0. Exam: 26 results since 27 Jul, **15 correct / 3
partial / 4 wrong / 4 not_covered = 57.7%** (30d 50.0%); domain-only 12/16 = 75.0% — the best in scope. Wrong
twice on "how many years must records be retained under UAE VAT" and once on mandatory tax-invoice fields.

**Persona.** The richest owned_decisions list in finance (9): control exceptions; invoice tax compliance;
ledger classification; operational tax reconciliation; reconciliation verdicts; revenue-recognition
application; tax filing calendar; tax supporting evidence; UAE VAT and CT coordination. forbidden: a disputed
or material filing position; current UAE tax law interpretation; paying anything; approving own
reconciliation. escalation_targets include "external UAE tax professional or firm". employee_authority:
forecast / invoice_review / money_verify autonomous at AED 0; collections_chase / expense_log advisory. It is
`refund_reconciler_role_id`.

**Inventory.** agent_knowledge: 8 (4 profession: "Professional standard (ACCA/CPA bookkeeping)", "Verified
UAE references & key citations", "Role & expertise", "Deepened professional playbook"; avg 965 chars; last
updated 24 Jul 2026; not delivered — F1) + 4 exam fills (all YAML/route noise). employee_knowledge: 12 domains
(finance@expert, uae_tax@expert …); 5/12 layers bound. Exam bank 11 (5 pack-recall). Context: same shape as
the CFO (LAYER 1 8,970; LAYER 2 empty; production tail = dept-library VAT checklist + LAYER 2c ~1,300).

**Senior-staff standard — Financial Controller / senior accountant, UAE SME with an automated ledger.**

| # | Domain | Depth |
|---|---|---|
| 1 | Double-entry bookkeeping to IFRS for SMEs; chart of accounts for a reveal-fee marketplace | expert |
| 2 | UAE tax-invoice content (Exec Reg Art. 59 — verify), simplified invoice, credit notes, TRN display rule, inclusive/exclusive trap | expert |
| 3 | VAT return preparation: boxes, reconciling to GL, 28th-day deadline, EmaraTax filing steps, voluntary disclosure | expert |
| 4 | Record retention: 5 years (15 for real estate) under the Tax Procedures Law and its exec reg — verify current | expert |
| 5 | Corporate-tax evidence: what to keep, audited-accounts trigger, SBR paperwork, CT return schedules | working |
| 6 | Stripe → ledger mapping: payment_intent/charge/refund/dispute/payout objects, fees, FX, timing differences, idempotent webhook posting | expert |
| 7 | Daily/monthly reconciliation and the three-way match; unknown monetary state must be visible (BR-033) | expert |
| 8 | Revenue-recognition application: reveal at point in time, subscriptions straight-line, refund liability, receivables ECL | working |
| 9 | Expense email → ledger capture (the founder forwards every receipt; that mailbox is the source of truth), duplicate detection, VAT input recovery on genuine costs | expert |
| 10 | Refund reconciliation (its own reconciler role): matching the founder's approval, the executor's Stripe refund and the ledger reversal | expert |
| 11 | Month-end close checklist and cut-off; accruals for usage-based cloud/LLM cost | expert |
| 12 | Control exceptions: what is an exception, how to raise it, when to hand to an external tax professional | expert |
| 13 | Bank reconciliation and cash pools (operating / tax-held / customer-held) | working |
| 14 | Audit-readiness folder and evidence provenance | working |
| 15 | Live-data discipline (`fn_ws_finance`, transactions table) | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Bookkeeping/CoA | expert | present — profession row "ACCA/CPA standard" (undelivered), senior reference "Chart of accounts for a reveal-fee marketplace", kb OpenStax/LibreTexts accounting texts | deliver F1 | — | P2 (delivery) |
| 2 Tax-invoice content | expert | partial — senior policy "Tax invoice content and the inclusive/exclusive trap"; exam answered fields wrong/partial | ops_knowledge finance `reference` "UAE tax invoice: mandatory fields" as a structured checklist (`structured_data`), + an SOP step in Invoice Generation that validates against it | 1 page / 2 chunks | **P1** |
| 3 VAT return | expert | partial — remediation "Filing the VAT return: reconcile before you file", SOP "Vat Review"; no box-by-box mapping, no EmaraTax steps | ops_knowledge `standard_operating_procedure` "VAT return preparation (boxes ↔ GL)" + kb FTA VAT returns user guide (present in kb) scoped so it is retrievable | 4 pages / 8 chunks | **P1** |
| 4 Retention | expert | **missing** — answered wrong twice; no structured fact | one ops_knowledge `reference` row + kb ingest of the Tax Procedures Law (see CFO #4) | 1 page | **P1** |
| 5 CT evidence | working | present — SOP "Corporate-Tax Evidence Retention", senior "Corporate Tax cash provisioning" | — | — | — |
| 6 Stripe→ledger | expert | partial — SOPs Webhook Processing, Payment Confirmation; agent_knowledge (payments_manager) describes the objects; no mapping table | ops_knowledge `reference` "Stripe object → ledger account mapping" with `structured_data` (event type → debit/credit/VAT treatment) | 2 pages / 4 chunks | **P1** |
| 7 Reconciliation | expert | present — SOPs Daily/Payment Reconciliation, senior remediation "Payment-processor reconciliation: gross, fees, refunds, reserves, payout timing" | — | — | — |
| 8 Revenue recognition application | working | partial (see CFO #6) | shared policy | — | P2 |
| 9 Expense capture | expert | present — SOP "Expense Email To Ledger"; tool expense_log (advisory — it may prepare, CFO executes) | — | — | — |
| 10 Refund reconciliation | expert | partial — decision_policy names it reconciler; SOP "Refund Accounting"; no worked example | worked example inside the CFO refund decision tree | (shared) | **P1** |
| 11 Close checklist | expert | present — SOP Monthly Close, senior playbook, "Accruing usage-based cloud and LLM cost at month-end" | — | — | — |
| 12 Control exceptions | expert | partial — output_contract control_exception; no threshold for "material" | decision_policy key `finance_material_exception_aed` + one rule row | 0.5 page | P2 |
| 13 Bank rec / cash pools | working | present — senior policy "Separate the three cash pools" | — | — | — |
| 14 Audit folder | working | present — senior policy "Audit readiness and record-keeping" | — | — | — |
| 15 Live data | expert | missing in delivery (F2) | fix F2 | — | **P1** (delivery) |

**Reasoning gap.** The controller has procedures but no numbers: no materiality threshold for a control
exception, no mapping of Stripe events to ledger accounts, no invoice-field checklist it can validate against.
Its exam pattern (75% on domain questions, wrong on the two statutory numbers) says the frameworks are in and the
statute facts are not.

**P1 count: 6** (invoice fields, VAT return SOP, retention fact, Stripe→ledger map, refund reconciliation example,
live-data delivery).

---

## 3. `collections` — Collections & Revenue Assurance Specialist (org_role `collections_and_revenue_assurance`)

**What it does today.** agent_runs 7d: 2 ok. Context assemblies 30d: 1 (14 Aug). review_chain author: 15 (9
approve); reviewer 6 (last 9 Aug). Exam: 26 results since 14 Aug, **3 correct / 4 partial / 11 wrong / 8
not_covered = 11.5%**; domain-only **0/16 = 0.0%** — the lowest in scope. 3 gaps auto-filled, all YAML noise
("06_RESEARCH_AND_ESCALATION_POLICY.yaml", "07_CATEGORY_V3_MANIFEST.json").

**Persona.** owned: collections sequence within policy; identifying unbilled/unrecognised revenue. forbidden:
waiving a due; legal escalation without the General Counsel; banning an account. employee_authority:
collections_chase advisory (CFO executes), forecast/invoice_review/money_verify autonomous at AED 0.
knowledge_scopes = the CFO's 14.

**Inventory.** agent_knowledge 7 (4 profession: "Professional standard (CICM credit management)", "Verified
UAE references", "Role & expertise", "Deepened playbook"; avg 1,218 chars; 24 Jul 2026; undelivered) + 3 exam
fills. employee_knowledge 12 domains; 5/12 layers. Exam bank 11 (5 pack-recall). Context shape identical to the
CFO's.

**Senior-staff standard — senior credit-control / revenue-assurance specialist for a pay-before-reveal model.**

| # | Domain | Depth |
|---|---|---|
| 1 | The model's receivable reality: reveal is pay-before-reveal (BR-020), so the only dues are failed/late card charges, supplier subscriptions after 31 Jul 2027, refund claw-backs and chargeback losses | expert |
| 2 | Dunning sequence design: timing, tone, channels (email/WhatsApp), the company's notify/call/claim 1/3/3 working-day cadence, admin fee AED 250, late fee 9% p.a., what may never be promised or threatened | expert |
| 3 | UAE legal recovery path: demand letter, Civil Procedure Law payment-order procedure for undisputed debts (FDL 42/2022 — verify article), Dubai Courts vs DIFC Courts, DIAC arbitration, limitation periods (Commercial Transactions Law FDL 50/2022 — verify), costs; and that all of it needs the General Counsel | working |
| 4 | Commercial interest on late payment in the UAE (permitted on commercial debts; rate limits — verify) and how the 9% p.a. late fee is justified in the T&Cs | working |
| 5 | Revenue assurance: unbilled reveals, reveal without invoice, invoice without charge, duplicate webhook double-posting, subscription lines without payment | expert |
| 6 | Bad-debt provisioning (IFRS 9 simplified ECL) and the write-off rule (write-off is a human act) | working |
| 7 | Chargebacks as collections events: representment evidence, "defend the reveal, never auto-concede", network deadlines | working |
| 8 | Failed-payment recovery: Stripe retry schedules, card updater, dunning emails, subscription lapse rules | expert |
| 9 | Consumer-protection and PDPL limits on dunning communications (Federal Law 15/2020; marketing-consent rules; no harassment; data minimisation in reminders) | working |
| 10 | KYB of paying buyers: TRN validation, licence check before extending any credit-like treatment | working |
| 11 | Escalation matrix: when a due goes to the CFO (AED threshold), when to the GC (legal action), when to Trust & Safety (suspected fraud) | expert |
| 12 | Live data: ageing from `transactions`/invoices, not from memory | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Model reality | expert | partial — senior playbook "Collections for a reveal-fee model: prefer pay-before-reveal, dun only real receivables" (good); not delivered | deliver; add a one-page "what can actually be owed to QuotesDone" reference with the four cases | 1 page | **P1** |
| 2 Dunning sequence | expert | **partial** — numbers exist in decision_policy (1/3/3, 250, 9%) but no playbook uses them; senior failure mode "Dunning message discipline"; tool collections_chase is advisory | ops_knowledge finance `decision_playbook` "Dunning sequence" citing the decision_policy keys, with 3 message templates (EN/AR) and the stop conditions | 3 pages / 6 chunks | **P1** |
| 3 UAE recovery path | working | **missing** — no row names the payment-order procedure, courts or limitation; exam domain score 0% | ops_knowledge `reference` "Debt recovery in the UAE for small B2B dues" (verify articles) + kb_chunks: Civil Procedure Law FDL 42/2022, Commercial Transactions Law FDL 50/2022 (kb already has 50/2022) | 4 pages / 8 chunks (+ law text 100 chunks) | P2 |
| 4 Commercial interest | working | missing | one paragraph in #3 (verify rate cap) | — | P2 |
| 5 Revenue assurance | expert | present — SOPs Payment Reconciliation/Reveal-Fee Recognition; agent_knowledge (billing) "three-way match"; output_contract assurance_finding | worked example with the actual queries (which tables) | 1 page | P2 |
| 6 Provisioning | working | present — senior policy "Bad-debt provisioning and write-offs" | — | — | — |
| 7 Chargebacks | working | present — senior playbooks "Chargebacks and disputes", "Dispute-response SLA" | — | — | — |
| 8 Failed-payment recovery | expert | partial — SOP "Failed-Payment Recovery"; no Stripe retry facts | shared Stripe reference (CFO #9) | — | P2 |
| 9 Comms limits | working | partial — legal dept policy "Marketing communications: consent, identification, unsubscribe" exists in legal scope, not finance scope | copy/alias the rule into finance scope or cross-scope it | 0.5 page | P2 |
| 10 KYB of buyers | working | present — senior policy "KYC/KYB at onboarding" | — | — | — |
| 11 Escalation matrix | expert | **missing** — generic 306-char escalation block; forbidden list says "legal escalation without the GC" but no AED/age threshold | decision_policy keys `collections_escalate_to_cfo_aed`, `collections_legal_after_days`; one decision_rule row | 0.5 page | **P1** |
| 12 Live data | expert | missing in delivery (F2) | fix F2 | — | **P1** (delivery) |

**Reasoning gap.** 0/16 on domain questions and a single context assembly in 30 days: this employee is
effectively idle and, when asked, guesses. It has the right doctrine ("dun only real receivables") but no
sequence with dates, no thresholds, no recovery path and no templates.

**P1 count: 4** (model-reality reference, dunning playbook, escalation thresholds, live-data delivery).

---

## 4. `billing_specialist` — Billing & Reconciliation Specialist (org_role `billing_operations`)

**What it does today.** agent_runs 7d: 2 ok. Context assemblies 30d: 0. review_chain author: 25 (15 approve).
Exam: 26 since 12 Aug, **5 correct / 11 partial / 8 wrong / 2 not_covered = 19.2%**; domain-only 2/16 = 12.5%.
Its domain questions were written for an "AI QA Specialist" (the examiner mis-read the remit) — so even the
domain score measures the wrong subject.

**Persona.** owned: invoice construction and billing reconciliation. forbidden: issuing refunds; changing
amounts without the controller. employee_authority: one row, `analysis` supervised (seeded 14 Aug from
execute_low). knowledge_scopes: finance, payments only. **employee_knowledge: 0 rows (0/12 layers bound).**
escalation_targets: payments_and_billing_manager, chief_of_staff.

**Inventory.** agent_knowledge 4: **one** profession row "Reconciliation and collections mechanics" (595 chars,
11 Aug 2026, undelivered) + 3 exam fills (decision_playbooks.yaml, company_objective.yaml, a Communications
exception). Exam bank 11 (5 pack-recall). Context: LAYER 1 9,547; LAYER 2 empty; tail 2c 1,320.

**Senior-staff standard — senior billing/reconciliation analyst on Stripe.**

| # | Domain | Depth |
|---|---|---|
| 1 | Stripe object model and event ordering: payment_intent, charge, invoice, refund, dispute, payout, balance transaction; webhooks out of order and duplicated; idempotency on event id (BR-032) | expert |
| 2 | Three-way match (provider event ↔ ledger ↔ invoice) and the break taxonomy | expert |
| 3 | UAE tax-invoice construction for a reveal fee: fields, TRN, sequential numbering, AED, VAT line, credit notes for refunds | expert |
| 4 | Reveal invoice lifecycle: quote value → 3% → invoice → payment → reveal (BR-020, BR-052 one payment source of truth) | expert |
| 5 | Supplier subscription billing (AED 1,000/yr; founding-1,000 exemption to 31 Jul 2027; start date founder-reserved) | expert |
| 6 | Failed charges: retry schedule, dunning hand-off to collections, subscription lapse | expert |
| 7 | Refund path mechanics (not authority): credit note, Stripe refund vs reversal, ledger reversal, who executes (payments manager) and who reconciles (controller) | working |
| 8 | Payout reconciliation: gross, fees, refunds, reserves, FX, timing to bank | expert |
| 9 | VAT presentation on receipts/invoices; inclusive vs exclusive | working |
| 10 | Duplicate/AP invoice scanning for QD's own vendor bills (tool ap_duplicate_scan) | working |
| 11 | Exception handling: locked/conflicting records, provider outage, "unknown monetary state is visible" (BR-033) | expert |
| 12 | Live data: which tables hold invoices/transactions/Stripe events | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Stripe objects/events | expert | partial — payments_manager's profession row (656 chars) names the objects; SOP "Webhook Processing"; BR-032 | ops_knowledge finance `reference` "Stripe event → action table" (`structured_data`) + kb Stripe docs (CFO #9) | 3 pages / 6 chunks | **P1** |
| 2 Three-way match | expert | present — its own 595-char row (undelivered), SOP Payment Reconciliation, senior remediation | deliver F1 | — | P2 (delivery) |
| 3 Tax-invoice construction | expert | partial — senior policy "Tax invoice content"; exam not asked | shared invoice checklist (bookkeeper #2) | (shared) | **P1** |
| 4 Reveal invoice lifecycle | expert | present — SOPs Reveal Checkout / Invoice Generation / Reveal-Fee Recognition; BR-020/052 | worked example end-to-end with one demo reveal (ZZ DEMO convention) | 1 page | P2 |
| 5 Subscription billing | expert | partial — SOP "Subscription Billing"; the exemption facts live in company_economics/ceo row; founder_reserved_decision keys | one `reference` row "Supplier subscription facts" (LIVE-fetch marked) | 0.5 page | **P1** |
| 6 Failed charges | expert | partial — SOP Failed-Payment Recovery | Stripe retry facts (shared) | — | P2 |
| 7 Refund mechanics | working | partial — SOP Refund Accounting; roles in decision_policy | shared refund tree | — | P2 |
| 8 Payout reconciliation | expert | present — senior remediation "Payment-processor reconciliation: gross, fees, refunds, reserves, payout timing" | — | — | — |
| 9 VAT presentation | working | present — payments pack "Vat Presentation — how the department uses it" | — | — | — |
| 10 AP duplicate scan | working | present (tool + senior playbook "Procurement finance") | — | — | — |
| 11 Exceptions | expert | present — 10 exception playbooks ×2 (generic), BR-033 | — | — | — |
| 12 Live data | expert | missing in delivery (F2) | fix F2 | — | **P1** (delivery) |
| — Curriculum binding | — | **missing** — employee_knowledge 0 rows; compliance view 0/12 | bind finance@expert, payments@expert, uae_tax@working, company/constitution/priority/universal@expert, quotesdone_os@working, communication@working | — | **P1** |

**Reasoning gap.** A single 595-char profession row and no curriculum binding. The exam tested it as a QA
specialist. It cannot reason about a break it has never been shown: no event→action table, no invoice checklist.

**P1 count: 5** (Stripe event table, invoice checklist, subscription facts, live-data delivery, curriculum
binding).

---

## 5. `payments_manager` — Payments & Billing Manager (org_role `payments_and_billing_manager`)

**What it does today.** agent_runs 7d: 2 ok. Context assemblies 30d: 0. review_chain author: 20 (12 approve).
Exam: 20 since 3 Sep, **3 correct / 14 partial / 1 wrong / 2 not_covered = 15.0%**; **0 domain questions —
all 10 questions are pack-file recall** (e.g. "finance-analyst-controller.fm07", "07_CATEGORY_V3_MANIFEST.json").
Nothing measured about its payments competence.

**Persona.** owned: payment-rail configuration within policy; billing-run correctness; dispute-handling path.
forbidden: issuing a refund; changing price; approving own reconciliation. It is `refund_executor_role_id`
("prepare and route, never execute unapproved" — it executes only after the founder's approval) and the CFO's
standing deputy (`delegation_rule`). employee_authority: `analysis` supervised only — **no authority row for
dispute_open or money_verify although both are in its tools.** knowledge_scopes: finance, payments.
**employee_knowledge: 0 rows.**

**Inventory.** agent_knowledge 4: one profession row "Payments in a UAE marketplace" (656 chars, 11 Aug;
undelivered) + 3 exam fills (noise). Context: LAYER 1 9,547; LAYER 2 empty; tail 2c 1,293. Department scope
gives it the 140 `payments` pack rows (4 packaged roles × role_charter/decision_playbooks/escalation_matrix/8
failure modes) and the finance rows.

**Senior-staff standard — Head of Payments for a UAE marketplace on Stripe.**

| # | Domain | Depth |
|---|---|---|
| 1 | Stripe platform operations in the UAE: account model, AED settlement, payout schedule, fee schedule (2.9% + AED 1 on file), reserves, Radar rules, test vs live mode, API keys and webhook endpoint hygiene | expert |
| 2 | Disputes/chargebacks: reason codes by network, evidence packs, deadlines shown on the dispute object, representment strategy for a reveal ("payment for access, not outcome"), dispute-rate thresholds that endanger the account (network monitoring programmes — verify current thresholds) | expert |
| 3 | Refund execution path: founder approval → executor → Stripe refund → reconciler; partial vs full; refund vs reversal; time to card; policy numbers (3 working days, AED 250, 9%) | expert |
| 4 | Regulatory perimeter: QD is a merchant collecting its own fee — it must not hold buyer funds or run escrow without a CBUAE licence (Retail Payment Services & Card Schemes Regulation 2021; Stored Value Facilities Regulation 2020 — verify); what a "wallet credit" would trigger | expert |
| 5 | Payment-method landscape in the UAE for B2B: cards, bank transfer, and the risk/cost of each; FX on non-AED cards | working |
| 6 | PCI-DSS scope with Stripe Elements/Checkout (SAQ A), never touching PAN | working |
| 7 | Fraud signals at payment: card testing, velocity, mismatched BIN country, refund abuse; throttles; coordination with Trust & Safety | working |
| 8 | Billing-run correctness: subscription cycles, proration, founding exemption, VAT on invoices, idempotent runs | expert |
| 9 | Incident handling: provider outage, delayed webhooks, duplicate events, reconciliation after recovery (SOP Provider Incident) | expert |
| 10 | Financial reporting hand-offs: what the controller needs from payments each day/month | working |
| 11 | Deputy-CFO awareness: when it stands in, what it still may not do (refunds, price) | working |
| 12 | Live data: Stripe dashboard/API is the source, never memory | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Stripe operations | expert | **partial** — 656-char row (undelivered); senior reference "Payment-processor economics: fees, reserves, payout timing, choosing the rail"; no UAE-specific Stripe facts | ops_knowledge finance `reference` "Stripe UAE for QuotesDone" + kb Stripe docs (fetchable via the attached Stripe MCP docs search — no paid model call) | 10 pages / 25 chunks | **P1** |
| 2 Disputes | expert | partial — senior playbooks "Chargebacks and disputes: defend the reveal", "Dispute-response SLA", failure mode "Card-testing"; tool dispute_open with **no authority row** | ops_knowledge `decision_playbook` "Dispute handling path" with evidence checklist per reason family and the deadline rule; employee_authority row for dispute_open | 3 pages / 6 chunks | **P1** |
| 3 Refund execution | expert | partial — decision_policy keys, SOP Refund Request/Refund Accounting; no executor checklist | shared refund tree (CFO #10) with the executor's steps | (shared) | **P1** |
| 4 Regulatory perimeter | expert | partial — legal failure mode "Holding buyer funds changes everything" (legal scope, not finance scope); senior finance policy "Wallet-credit policy: expiry, breakage" | ops_knowledge finance `policy` "Payments regulatory perimeter (CBUAE)" — verify the two regulations' current names/dates | 2 pages | P2 |
| 5 Payment methods | working | missing | one paragraph in #1 | — | P3 |
| 6 PCI scope | working | missing | one `reference` row | 0.5 page | P2 |
| 7 Fraud at payment | working | present — senior failure modes (card-testing, refund-abuse rings); decision_policy fraud_score_max 0.7 | — | — | — |
| 8 Billing-run correctness | expert | present — SOP Subscription Billing; BR-016/032 idempotency | worked example | 1 page | P2 |
| 9 Incidents | expert | present — SOP Provider Incident; exception playbooks | — | — | — |
| 10 Hand-offs | working | present — pack handoffs ("payments_revenue hands the case to finance only after…") | — | — | — |
| 11 Deputy awareness | working | present — delegation_rule; forbidden list | — | — | — |
| 12 Live data | expert | missing in delivery (F2) | fix F2 | — | **P1** (delivery) |
| — Curriculum binding | — | **missing** (0/12) | bind finance/payments@expert, uae_tax@working, company set@expert, quotesdone_os@working | — | **P1** |
| — Exam | — | no domain questions | fix the examiner's remit source for functional roles (F3) | — | P2 |

**Reasoning gap.** It owns the dispute path and the refund execution but has no dispute playbook with deadlines
and no executor checklist; its exam never asked it a payments question; two of its tools have no authority row,
so `fn_task_approve` will treat them as undefined.

**P1 count: 5** (Stripe reference, dispute playbook + authority row, refund executor steps, live-data delivery,
curriculum binding).

---

## Department summary — finance

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| cfo | 8 | 8 | 2 |
| bookkeeper | 6 | 3 | 0 |
| collections | 4 | 5 | 0 |
| billing_specialist | 5 | 4 | 0 |
| payments_manager | 5 | 4 | 1 |
| **total** | **28** | **24** | **3** |

Of the 28 P1 rows, 6 are the same delivery defect counted once per agent (F1/F2: LAYER 2 empty, LAYER 3/2f/2g
cut). Fixing `fn_agent_context` delivery would close those 6 without ingesting a page.

**Top 5 ingest items for finance (in order):**

1. **Deliver what already exists** — repair the LAYER 2 admission guard (line 384) and the 19,500-char head cut
   so professional expertise, live finance state (`fn_ws_finance`), deterministic rules (2f) and facts-to-fetch
   (2g) reach the prompt. Zero pages; unblocks 17 CFO topics, 4 controller topics and the whole rules layer.
2. **UAE statutory facts pack for finance** (ops_knowledge `reference` rows with `structured_data` +
   decision_policy keys): VAT rate/thresholds/invoice fields/return date/place-of-supply for reveal fees; CT
   0/9% + SBR + registration deadline + accounting basis; 5-year retention; e-invoicing phase dates (verify).
   ~15 pages / 35 chunks. Also ingest the Tax Procedures Law FDL 28/2022 + exec reg into kb_chunks (finance).
3. **Refund decision tree + dunning playbook** that cite `decision_policy` keys by name (3%, AED 250, 9% p.a.,
   1/3/3 working days, founder gate, executor/reconciler) with 3 worked cases each and EN/AR templates. ~7 pages.
4. **Stripe UAE reference + event→ledger mapping + dispute playbook** (facts from the Stripe dashboard/docs via
   the attached Stripe MCP; dispute fee and payout schedule marked verify). ~15 pages / 35 chunks. Add
   employee_authority rows for `dispute_open` and `money_verify` for payments_manager.
5. **Revenue-recognition policy (IFRS 15/9/IAS 37) for the reveal/subscription model** with journal templates,
   and a "QuotesDone economics — the numbers" reference generated from `company_economics` and marked
   LIVE-fetch. ~10 pages / 25 chunks. Bind `employee_knowledge` for billing_specialist and payments_manager
   (0 rows today).

**Not measured / boundaries.** Semantic retrieval (`fn_ops_knowledge_match`, `kb_search`) output — needs an
embedding call; the content of the 412 V2 pack rows beyond titles; whether the `payments` dept rows are
reachable through LAYER 2c (scope includes them, ranking not tested); phase_b_sla_policy scope resolution;
the actual licence type/TRN/registration status of the company (not in any table I read).
