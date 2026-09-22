# Knowledge audit — Executive department (3 AI employees)

Measured 6 Sep 2026 02:00–03:30 UTC against production `htdblwldjkcgjvmqkbeh`, read-only. Every number was
read from a table or a function in the session; anything not measured says so. Scope: `org_agents.active and
department = 'exec'` → `ceo` (Chief Executive (AI)), `brief` (Chief of Staff), `cpo` (Chief Performance
Officer; org_role `corporate_performance_director` active, `chief_performance_officer` retired, both mapped to
`cpo`). Runtime scope `fn_dept_scope('exec') = {evolution, exec}`.

## 0. Findings that apply to all three

**E1. No professional expertise reaches any executive.** `# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` = 38 chars
(heading only) for brief, ceo and cpo on both `fn_agent_context` overloads and on the production path
`fn_agent_context_capped(key, 24000, query)`. Cause: the admission guard (line 384 of
`scripts/sql/fn_agent_context_workload_names_the_holding_role.sql`, `own_cap + 2200` = 8,200) is tested after
~12,000 chars of genome, risk register and employee record are already in `out`. The Chief of Staff's 12
profession topics (crisis coordination, conflict arbitration, weekly business review cadence …) are never shown
to it.

**E2. The production prompt is cut at 19,500 chars of standing context + 4,500 of retrieval** (aborted-DO probe;
nothing committed): head "trimmed to the first 19,500 characters of 31,238–33,273"; LAYER 3 live state
(`fn_ws_company`, 2,728 chars), LAYER 4 lessons, "YOUR OS OBJECTIVES, MEASURED", "KNOWLEDGE YOUR OS DOES NOT
OWN", the TOM digest, LAYER 2d role knowledge (reached at 217–305 chars, i.e. cut mid-record), LAYER 2f
deterministic rules and LAYER 2g facts-to-fetch are all outside the 24,000 budget. An executive told to "quote
operational numbers ONLY from LIVE STATE" never receives the live state.

**E3. The exam does not measure executive competence.** Exam grounding uses `kb_search(category = agent_key)`:
kb_chunks category `brief` = 16 chunks, `ceo` = 1, `cpo` = 3. The examiner read "brief" as "sourcing brief":
the Chief of Staff's 6 domain questions asked which authority issues food-import permits, product-conformity
marks (ECAS) and cosmetics registration (the grader's own reference answer names ESMA, an authority merged into
MoIAT — verify). `cpo` has 10/10 pack-file recall questions and 0 domain questions. Company-wide 30-day score
26.3% (Governance page 26.2%).

**E4. The executive department has no senior-expert layer.** `ops_knowledge dept_key='exec'`: 295 rows, of
which 271 are the V2 delivery pack (31 Jul 2026), 13 operating-model rows, 5 "office of the CEO" rows and
**0 rows with `source_authority = 'senior_expert_uae'`** (finance has 94, legal 90). Of the 46 decision-bearing
exec rows (14 playbooks, 11 rules, 11 SOPs, 10 exception playbooks): 11 of the 14 playbooks are copies of
"the org_task lane determination"; 0 contain an AED figure; 0 contain a worked example; 20 are
`target_state`, 18 active, 8 implemented. The 3 strategic-review steps ("generate options with the cost and
the risk", "test the options against the priority hierarchy", "decide and record the rationale") and "root
cause: is it the work or the target?" are the only reasoning templates.

**E5. The executive reference corpus is general management reading, not this market.** `kb_chunks
category='exec'`: 60,206 chunks, 191 sources (11–29 Aug 2026): WEF Global Competitiveness Report 2019 (2,234
chunks), OpenStax economics/business/management/OB/accounting textbooks (~11,000), David *Strategic Management*
(1,753), JPMorgan annual reports 2019–2024 (~6,000), WTO World Trade Reports, WEF Future of Jobs 2025, Isaacson
*Steve Jobs*, Kahneman, Dalio, Porter, Rumelt, *Shoe Dog*, NASA Systems Engineering Handbook, BIS Basel III
documents. No UAE/GCC market, procurement-practice or marketplace-economics source among the 25 largest (full
list not inspected). For functional staff `agent_brain.retrieve()` calls `kb_search` unscoped (k = 8 over
2,686,026 chunks in 356 categories).

Department-level inventory (shared):

| Source | Rows | Freshness | What it covers |
|---|---|---|---|
| ops_knowledge dept_key=exec | 295 (271 V2 pack; 13 operating model; 5 office-of-the-CEO; 6 unattributed) | newest 4 Sep 2026 | 11 SOPs: Founder Objective To Execution, Weekly Executive Review, Monthly Strategy Review, Company-Wide Risk Review, Board And Investor Reporting, Cross-Department Conflict Resolution, Priority Reset, Capital-Allocation Recommendation, + strategic-review steps 4–6 (decide and record; cascade and supersede objectives; open an outcome record with a baseline). 14 playbooks (11 "org_task lane determination"; "root cause: is it the work or the target?"; steps 2–3 of the strategic review). 11 decision rules (10 generic + "detect variance against target"). 10 generic exception playbooks. 20 knowledge_domain / 20 operational_application / 20 control_requirements pack rows (incl. "Board and investor reporting — controls"). 55 rows carry an escalation_rule: 48 generic, 7 specific (e.g. "when the decision departs from the step-3 ranking → review_queue, and the founder where it touches money"; "goal.at_risk emitted by fn_emit_metric_alerts Monday 03:00 UTC"; "no existing metric measures the decision effect → Data and Experimentation"). |
| ops_knowledge dept_key=evolution | 276 | 31 Jul–4 Sep 2026 | strategy-performance-and-evolution packaged roles (4 × 26–27 rows: role_charter, senior_judgment, decision_playbooks.yaml, escalation_matrix.yaml, 7 failure modes); content not inspected beyond titles |
| ops_knowledge role_key executive-office-chief-of-staff-* | 4 roles × 26 | 31 Jul 2026 | 01_ROLE_EXPERTISE_V2, 02_EXPERT_DECISION_CHECKLIST_V3, 02_ROLE_DECISION_CATALOG_V2, 05_ROLE_EVIDENCE_AND_OUTPUT_CONTRACT, 06_ROLE_SCORING_RUBRIC, 07_FAILURE_TO_REMEDIATION_MAP, 08_RECERTIFICATION_AND_DRIFT_POLICY, decision_playbooks, escalation_matrix, kpi_causal_model, learning_policy, output_contracts, role_charter, senior_judgment, tools_and_permissions, fm01–fm07 |
| ops_knowledge scope_type=company | 200 | 31 Jul 2026 | Mission, Vision, Marketplace model, Reveal fee, Decision authority tiers, 10 hard gates (money_move, ad_spend, legal_commitment, public_claim_publish, production_deploy, destructive_data, secrets_security, authentication_identity, autonomy_framework, supplier_enforcement), 5 data classifications, 4 incident priorities, 6 memory policies, 5 model routes, 8 audit requirements, operating principles (Evidence before confidence, No invented facts, Founder escalation discipline, Cost-aware AI, Measured automation …), company_goal_tree.yaml, company_objective.yaml, decision_record_contract.yaml, decision_quality_standard.md, organizational_learning_loop.md |
| company_constitution | 20 articles (Mission, Vision, Core values, Decision priority hierarchy, Decision principles, Customer/Supplier promises, Quality, Security & privacy, Financial principles, Escalation principles, AI behaviour rules, Communication standards, Learning obligations, Risk appetite, Leadership style, Brand personality, Growth strategy, Hiring philosophy, Ethics) | 26 Jul / 9 Aug 2026 | delivered as "THE COMPANY GENOME" (2,651 chars) in every prompt |
| company_goals | 63 active | live | "COMPANY GOALS YOUR WORK MUST MOVE" (259 chars in exec prompts — only the first goals fit) and "YOUR DEPARTMENT'S OBJECTIVES" (381: "Reach AED 1M annual revenue …") |
| company_economics | 10 rows, every_employee_must_know = true | live | reveal 3%; supplier AED 1,000/yr, first 1,000 free; PSP ~2.9% + AED 1; break-even "AED 7,700/month declared"; liquidity constraint; CAC/LTV "unmeasurable until reveals exist". **No prompt section named for it was measured**; only "Pricing & fees (LIVE)" (966 chars) reaches the prompt via LAYER 1. |
| company_reflection / company_snapshot / decision_record / company_index | 29 / 25 / 12 / 69 | nightly / live | "THE COMPANY'S OWN LATEST REFLECTION" (276 chars) and "DECISIONS ALREADY ON RECORD" (366) reach exec prompts |
| risk register (fn in fn_agent_context) | — | live | "WHAT THE COMPANY IS WORRIED ABOUT" 3,039 chars in every prompt |
| decision_policy | 38 keys (confidence_min 0.6; financial_review_aed 10000; auto_action_max_aed 0; founder_review_gates; legal_triggers; apex_backup ops_director; dispatch caps) | live | not in the prompt (LAYER 2f cut) |
| governance_rule | 11 (conflicts → common manager else brief; two depts disagree → both submit problem/options/risks/confidence to the CoS; CoS unavailable → CEO; approval hierarchy author → dept head → CoS → founder where required; money > AED 10,000 → founder) | live | |
| founder_reserved_decision | 11 (fundraising, ownership_and_equity, market_expansion, spend_above_budget, reveal_fee_pct, supplier_subscription_price/start_date, founding_supplier_exemption, founder_commercial_rules, material_policy_change, unapproved_legal_commitment) | live | |
| delegation_rule | ceo → brief (standing deputy) | live | |
| kb_chunks category=exec | 60,206 chunks / 191 sources | 11–29 Aug 2026 | see E5 |
| kb_chunks categories brief / ceo / cpo | 16 / 1 / 3 | — | what the exam grounds on |
| agent_action_kind_policy | 15 kinds `auto` with no authority role (strategy_rec, objective_step, improvement_question, ai_improvement, report_recommendation, ops_recommendation …); none names an exec role as authority | live | |

---

## 1. `ceo` — Chief Executive (AI) (org_role `ceo`, executive, reports to founder)

**What it does today.** agent_runs 7d: 6 (1 ok, 5 skipped). Context assemblies 30d: 18 (kb_usage_log 25).
review_chain as author: **667 rows — 0 approve, 330 escalate, 337 owned**: every CEO deliverable that reached a
review decision was escalated (improvement_plan on org_agents: "Your department has had 324 deliverable(s)
returned by review recently"); as reviewer: 1,076 (approve/owned/reject). Exam: 26 since 13 Aug, **5 correct /
7 partial / 6 wrong / 7 not_covered = 19.2%**; domain-only 3/16 = 18.8%; 2 gaps filled (both trade files:
06_ROLE_SCORING_RUBRIC, Logistics specialist expertise).

**Persona.** owned: company objectives and their priority; capital allocation between departments; accepting
or refusing a department's corrective plan; declaring a company-level risk. forbidden: spending money without
the founder; changing a go-live switch; approving its own output; overriding an independent reviewer's stop.
authority execute_high, budget AED 100,000; employee_authority coordinate / escalate_founder / exec_review
autonomous at AED 100,000. tools: agent_action_work, bi_snapshot, coordinate, escalate_founder, exec_review,
growth_simulate, metric_alerts, review_submit. knowledge_scopes 17 (all functional domains at awareness +
company set). output_contracts: company_objective_set, department_allocation, escalation_to_founder.
evaluation_suite eval_exec_direction (no rows in v_eval_latest/agent_evals). KPIs owned: 1.

**Knowledge inventory (agent-specific).**

| Source | Rows / size | Freshness | Covers |
|---|---|---|---|
| agent_knowledge profession | **1 row**, 793 chars, unvalidated | 6 Aug 2026 | "Running a marketplace that has not launched": pre-launch KPIs = supply depth per category and time-to-first-quote; 3% on reveal; suppliers pay nothing until 31 Jul 2027 and the first 1,000 never pay; growth capital goes to supply; anonymity is the product; ten Operating Systems. Correct and relevant — **never delivered (E1)**. |
| agent_knowledge experience | 2 | 3 Sep 2026 | exam fills: 06_ROLE_SCORING_RUBRIC_V2.yaml; "Logistics & Freight Forwarding Companies — Category Specialist Expertise V2" (3,456 chars of LAYER 4 in the 2-arg call — contamination) |
| employee_knowledge | 15 (company/goals/constitution/priority/universal@expert; engineering/finance/hr/legal_uae/marketing/operations/procurement/sales_crm@awareness; quotesdone_os@working; communication@working) | — | 4/12 layers bound → INCOMPLETE |
| exam bank | 11 (5 pack recall, 6 domain: authority/compliance/domain/pricing) | 5 Sep 2026 | |
| fn_agent_context('ceo', 22000) | 31,309 chars; production head 19,500 + tail 4,500 | live | genome 2,651; risk register 3,039; employee record 1,184; authority 246; escalation 306; KPIs 141; workload 428; Leadership OS 1,148; goals 259; dept objectives 381; open findings 1,066; decisions on record 366; reflection 276; LAYER 2 empty; LAYER 1 8,918; production tail = 4 department-pack md snippets (Advanced Operating…, Advanced Department Curriculum, Advanced Professional Curriculum, CoS Director role) + 2d cut at 217 chars |

**Senior-staff standard — CEO of a pre-launch UAE B2B RFQ marketplace.**

| # | Domain | Depth |
|---|---|---|
| 1 | The company's economics and constraints: 3% reveal on quote value; supplier AED 1,000/yr with the founding-1,000 exemption to 31 Jul 2027; PSP 2.9% + AED 1; AI cost per reveal; break-even AED 7,700/month declared; AED 1,000,000 revenue by 31 Aug 2027; the liquidity constraint; what destroys the economics (refunds from supplier non-response, AI spend that does not convert …) | expert |
| 2 | Two-sided marketplace strategy: cold start, supply-first sequencing, category-level liquidity, anonymity as the product, take-rate economics, disintermediation/circumvention risk, network effects, when to open a category | expert |
| 3 | Objective cascade: company goals → department objectives → KPIs; the goal tree; the six-rank priority hierarchy (art. 4); superseding objectives after a decision | expert |
| 4 | Capital allocation: department budgets, ROI framing per department, the ad-spend autopilot ceiling, model-cost policy (deterministic-first 95/5, tier mix), and the founder gates (spend above budget, fundraising, equity, market expansion) | expert |
| 5 | Risk: the live risk register, risk appetite (art. 15), criteria for declaring a company-level risk, pre-mortems on launch | expert |
| 6 | Decision quality: decision records (problem, options, risks, benefits, reversibility, expected outcome, rollback), confidence floor 0.6, "evidence before confidence", measuring the outcome afterwards | expert |
| 7 | UAE market context: Dubai/UAE B2B procurement practice (PO/LPO culture, 30–90-day payment terms, tender/prequalification norms, PRO services), buyer segments (contractors, fit-out, FM, hospitality, industrial), seasonality (Ramadan, summer), mainland vs free-zone supplier landscape, government e-procurement channels (verify names), Dubai D33 agenda (verify specifics) | working |
| 8 | Competitive landscape: global B2B marketplaces (Alibaba-type), regional B2B platforms (e.g. Tradeling — verify current status), procurement software and directories; QuotesDone's anonymous-quote positioning | working |
| 9 | Regulatory awareness at CEO level: what goes to the GC (legal_triggers), PDPL, consumer/e-commerce law, licence scope; founder-reserved keys | working |
| 10 | CEO financial literacy: P&L/cash/runway, contribution margin, cohort metrics, "activity is not outcome", "a 30-day total is not a run rate" | expert |
| 11 | Growth engine: supply acquisition (scrape → enrich → invite → verify → approve; Apify paused to 2027), buyer acquisition (Meta autopilot, SEO, WhatsApp), the funnel (inquiry → rfq_ready → dispatched → quoted → revealed → rated) and its current numbers | expert |
| 12 | Operating-model literacy: 10 departments, 54 active agents, 30 workflows / 257 steps, kernel states and handoffs, review chain and authority tiers, what "act" means, escalation reserved for founder boundaries | expert |
| 13 | Performance cadence: weekly executive review, monthly strategy review, quarterly priorities, accepting/refusing corrective plans | expert |
| 14 | Governance & ethics: constitution, AI behaviour rules, no overselling, no invented facts | expert |
| 15 | Scenario and stress testing: what breaks the path to AED 1M and the runway | working |
| 16 | Founder communication: exception-first, decisions-needed vs FYI, the WhatsApp command channel norms, never asking him technical questions | expert |
| 17 | Org design for an AI company: when to add/merge/retire a role (art. 19; Phase A rules) | working |
| 18 | Board/investor reporting (SOP exists) | working |
| 19 | Live-data discipline: fn_ws_company, company_snapshot, company_index; never quote a remembered number | expert |

**Gap table.**

| Domain | Depth | Today (evidence) | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Economics & constraints | expert | **partial** — company_economics 10 rows exist but no prompt section delivers them; its 793-char profession row has the numbers but is undelivered (E1); "Pricing & fees (LIVE)" 966 chars reaches LAYER 1; exam: wrong on the supplier fee structure and the pre-launch KPI | emit `company_economics` as a prompt section (every_employee_must_know = true on all 10 rows); ops_knowledge exec `reference` "QuotesDone economics — the numbers" marked LIVE-fetch | 2 pages | **P1** |
| 2 Marketplace strategy | expert | **missing** — no senior-expert rows for exec (E4); kb 'exec' has Porter/Rumelt but no marketplace-economics text; finance scope holds "GMV, take rate, net revenue", "The AED 1,000,000 back-solve", "Stress-testing the model" (not in exec scope) | ops_knowledge exec `decision_playbook` set (senior_expert_uae): cold-start sequencing, category liquidity thresholds (when a category is "open": ≥ N confirmed suppliers), circumvention economics, take-rate defence, anonymity trade-offs — 8–10 playbooks with worked cases; cross-scope the 3 finance rows | 12 pages / 30 chunks | **P1** |
| 3 Objective cascade | expert | present — company_goal_tree.yaml, company_objective.yaml (company scope), SOP Founder Objective To Execution, strategic-review steps; goals section is only 259 chars (first goals fit) | widen the goals section or rank by owner_dept | — | P2 |
| 4 Capital allocation | expert | partial — SOP Capital-Allocation Recommendation (target_state?), founder_reserved keys, department_budget declared AED 7,700/month; **no allocation rule with numbers, no ROI template** | `decision_playbook` "Capital allocation between departments" with the budget table, the ad-spend ceiling and model-cost policy as `structured_data`, 2 worked allocations | 3 pages | **P1** |
| 5 Risk | expert | present — risk register 3,039 chars in every prompt; art. 15; SOP Company-Wide Risk Review; **no criterion for "declare a company-level risk"** | one `decision_rule` with the declaration criteria (score band, goal impact) | 0.5 page | P2 |
| 6 Decision quality | expert | present — decision_record_contract.yaml, decision_quality_standard.md, strategic-review steps 2–6, confidence_min 0.6; **0 worked examples in the department** | 3 worked decision records (one reversible, one founder-gated, one refused) as `operational_template` rows | 3 pages | **P1** |
| 7 UAE market context | working | **missing** — no UAE/GCC procurement-practice source in the 25 largest exec sources; none in ops_knowledge exec | ops_knowledge exec `reference` "UAE B2B procurement market primer" (payment-term norms, buyer segments, seasonality, licence landscape, government e-procurement channels — verify names/figures); kb_chunks: a small curated UAE market set (Dubai D33 agenda text, MoE/DET published stats — verify sources) | 10 pages / 25 chunks | P2 |
| 8 Competitive landscape | working | missing | `reference` "Competitor and substitute map" (names marked verify) | 3 pages | P3 |
| 9 Regulatory awareness | working | present — legal_triggers, hard gates, founder_reserved rows; **LAYER 2f cut (E2)** | fix E2 | — | P2 (delivery) |
| 10 Financial literacy | expert | partial — finance failure modes ("a 30-day total is not a run rate", "fixtures counted as real revenue") are in finance scope, not exec | cross-scope 6 finance failure modes to exec | — | P2 |
| 11 Growth engine | expert | partial — company rows "Marketplace model", constitution art. 18 Growth strategy; the funnel numbers are live (fn_ws_company) and **cut (E2)**; Apify pause and ad-spend autopilot facts live in memory files, not in any prompt row | fix E2; one `reference` "Growth engine state" LIVE-fetch (supplier funnel counts, marketing_golive flag, ad ceiling) | 1 page | **P1** |
| 12 Operating-model literacy | expert | present — Leadership OS block 1,148, TOM digest (cut), "KNOWLEDGE YOUR OS DOES NOT OWN" (cut) | fix E2 | — | P2 (delivery) |
| 13 Performance cadence | expert | present — SOPs Weekly Executive Review, Monthly Strategy Review, Priority Reset | — | — | — |
| 14 Governance & ethics | expert | present — genome | — | — | — |
| 15 Stress testing | working | present in finance scope only | cross-scope | — | P2 |
| 16 Founder communication | expert | partial — art. 13, "Founder escalation discipline" principle; the founder's standing rules (only refunds; no technical questions; WhatsApp) are in `docs/` and memory, not in a knowledge row | `policy` row "How to communicate with the founder" (from the session skill and the constitution) | 1 page | P2 |
| 17 Org design | working | present — art. 19; Phase A rules | — | — | — |
| 18 Board reporting | working | present — SOP + controls row | — | — | — |
| 19 Live data | expert | **missing in delivery** — LAYER 3 cut; 2g never reached (E2) | fix E2 | — | **P1** (delivery) |
| — Contamination | — | LAYER 4 = Logistics & Freight specialist text | quarantine the exam fill | — | P2 |
| — Review outcome | — | 330 of 330 decided reviews = escalate | cause not measured here (reviewer, reason columns were null for 651 exec rows); flag for the review-chain owner | — | P2 |

**Reasoning gap.** The CEO has the constitution, the risk register and a good one-paragraph strategy row it
never sees. It has no marketplace-strategy playbooks (the department has no senior layer at all), no
allocation rule with numbers, no worked decision record, and no live numbers. Its deliverables were escalated
330 times out of 330 decided reviews; the exam scored it wrong on its own supplier-fee rule. A senior CEO in
this seat would carry the category-liquidity threshold, the funnel numbers and the allocation table in their
head and reason from them; none of the three is in front of this one.

**P1 count: 6** (economics delivery, marketplace-strategy playbooks, capital-allocation playbook, worked decision
records, growth-engine live reference, live-data delivery).

---

## 2. `brief` — Chief of Staff (org_role `chief_of_staff`, executive, reports to ceo)

**What it does today.** agent_runs 7d: 139 ok (cron-driven; the most active agent in scope). Context
assemblies 30d: 143 (63 knowledge ids each; kb_usage_log 177). review_chain as author: 1,012 (612 approve, 1
reject, 399 owned); as reviewer: 2,282 (all approve). Exam: 26 since 27 Jul, **4 correct / 1 partial / 10
wrong / 11 not_covered = 15.4%** (30d 20.0%); domain-only 2/16 = 12.5%; 9 gaps filled (5 trade-route files
incl. "source_route_manifest.json" for Luxury & Concierge). The 10 wrong answers are trade-regulator questions
asked of a Chief of Staff (E3).

**Persona.** owned: turning founder intent into assigned work; which department owns an ambiguous request;
daily and weekly company brief content; unblocking a stalled task. forbidden: deciding a department's
professional method; approving its own output; committing spend. authority execute_high, budget AED 100,000;
employee_authority coordinate / escalate_founder / exec_review autonomous at AED 100,000. tools as CEO.
output_contracts: founder_brief, task_assignment, department_escalation. escalation: ceo. It is the CEO's
standing deputy, the arbiter in governance rules 5 and 9, and the third step of the approval hierarchy (rule
11). KPIs owned: 3.

**Knowledge inventory (agent-specific).**

| Source | Rows / size | Freshness | Covers |
|---|---|---|---|
| agent_knowledge profession | 12 topics, avg 621 chars, unvalidated | last updated 27 Jul 2026 | Crisis coordination protocol; Cross-department conflict arbitration; Weekly business review cadence; Professional standard (chief of staff briefing); product:reframe_before_build; Role & expertise; Deepened professional playbook; Verified references & key standards; exam:authority / compliance / scope / standards (4 exam-derived rows). **Undelivered (E1).** |
| agent_knowledge experience | 12 | 5 Sep 2026 | 7 real lessons ("Before treating a KPI/goal miss as…", "Multiple CEO-flagged 'lacking con…'", "Silent-failure alerts on core loops…", "When CEO review flags a deliverable…") + 5 exam fills (00_DEPARTMENT_MASTER.md, SOP 01, 03_QUOTE_READINESS_AND_COMPARISON_V2, source_route_manifest.json, executive-office operations specialist fm) |
| employee_knowledge | 15 (as CEO) | — | 4/12 layers bound |
| exam bank | 11 (5 pack recall, 6 domain — mis-remitted) | 5 Sep 2026 | |
| fn_agent_context('brief', 22000) | 31,312; production head 19,500 + tail 4,500 | live | LAYER 1 9,262 (brand ×2, AI Constitution, response structure, governance gate, retrieve-before-answering, RFQ completeness, Pricing LIVE, FAQ header, 5 explainability stubs, canon:core); LAYER 2 empty; LAYER 4 (2-arg) 3,546 = "exam:745 source_route_manifest…" + lessons; production tail = FAQ "vision", FAQ "Who approves refunds", 00_DEPARTMENT_MASTER.md, curriculum, department_operating_model.md, 01_ROLE_EXPERTISE_V2 — LAYER 2c 484 + 2d cut at 305 |

**Senior-staff standard — Chief of Staff to the founder of an AI-run marketplace.**

| # | Domain | Depth |
|---|---|---|
| 1 | Founder intent → work: reading a WhatsApp/email instruction, deciding scope, owner, done-criteria and deadline, opening the task in the kernel with a complete packet (BR-008) | expert |
| 2 | Ownership map: which of the 10 departments / 54 agents owns which decision (org_role owned/forbidden lists), what is founder-reserved, what is "nobody's" and how to assign it | expert |
| 3 | Conflict arbitration: governance rules 5 and 9 (both sides submit problem/options/risks/confidence), the priority hierarchy as tie-breaker, recording the ruling | expert |
| 4 | Brief construction: daily/weekly founder brief = what changed, exceptions, decisions needed vs FYI, one page; numbers only from live state; EN, human voice (writing:human_voice) | expert |
| 5 | Prioritisation: cost of delay, RICE/ICE-style scoring, the priority hierarchy, dispatch caps (dispatch_max_open_per_dept 250) | expert |
| 6 | Unblocking: kernel states and transitions, unaccepted handoffs, review returns, timers with escalation (BR-044), "no silent exception" (BR-043), who to route to | expert |
| 7 | Review chain: author → department head → CoS → founder where required; creator/reviewer separation (BR-002); no self-certification (BR-037); what "approve" commits the company to | expert |
| 8 | Company goals and KPI literacy: the 63 goals, owners, measurement SQL, what "at risk" means | expert |
| 9 | Marketplace economics (working level): the numbers in company_economics and how a request moves them | working |
| 10 | UAE operating calendar: Sat–Sun weekend, public holidays, Ramadan working hours, summer slowdown; what is due when (VAT/CT dates from finance) | working |
| 11 | Founder boundaries and communication: only refunds need him; money > AED 10,000; never technical questions; the single completion line; WhatsApp as command channel | expert |
| 12 | Operating-model literacy: workflows/steps/handoffs, agent_runs semantics (cron log, not employee log), the OS dashboard pages | expert |
| 13 | Crisis coordination: incident priorities P0–P3, who leads, comms cadence | expert |
| 14 | Decision hygiene: decision records, superseding objectives, outcome records with baselines | expert |
| 15 | Meeting/committee mechanics: weekly executive review agenda, monthly strategy review inputs | working |
| 16 | Communication standards (art. 13), bilingual awareness | working |
| 17 | Live data: fn_ws_company, org_tasks queue, review_chain, workflow_run | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 Intent → work | expert | present — SOP "Founder Objective To Execution", playbooks "org_task lane determination" (×11), BR-008; no worked example | 2 worked examples (a one-line WhatsApp instruction → task packet) as `operational_template` | 1 page | P2 |
| 2 Ownership map | expert | **partial** — the map exists as org_role rows (owned/forbidden per role) but no prompt section or knowledge row renders it; "which department owns an ambiguous request" is its owned decision | generate one ops_knowledge exec `reference` "Who owns what" from org_role (10 depts × owned decisions, founder-reserved keys, apex backup) and refresh it on org change | 3 pages | **P1** |
| 3 Conflict arbitration | expert | present — profession row (undelivered), governance rules 5/9, SOP Cross-Department Conflict Resolution | deliver E1 | — | P2 (delivery) |
| 4 Brief construction | expert | partial — profession "Professional standard (chief of staff briefing)" and "Weekly business review cadence" (undelivered); output_contract founder_brief; finance senior "Founder financial reporting: exception-first one-pager" (finance scope); **no example brief** | `operational_template` "The founder brief" with one real past brief as the example; require live-state citations | 2 pages | **P1** |
| 5 Prioritisation | expert | partial — priority hierarchy (art. 4) present; SOP Priority Reset; no scoring rule | one `decision_rule` "priority score" with the factors and the dispatch caps cited from decision_policy | 1 page | P2 |
| 6 Unblocking | expert | partial — BR-043/044, kernel docs in `docs/`; 7 experience lessons; no row lists the stall causes and the remedy per cause | `decision_playbook` "Stalled task triage" (unaccepted handoff / review return / timer breach / missing evidence / authority exceeded → action) | 2 pages | **P1** |
| 7 Review chain | expert | present — governance rule 11, BR-002/037; as reviewer it approved 2,282 of 2,282 — no rejection criteria in any row | `decision_rule` "What a Chief-of-Staff review checks" (is_actual_work, states_its_result, grounded_in_this_business — the violated_rule vocabulary already in review_chain) | 1 page | **P1** |
| 8 Goals & KPIs | expert | present — company_goals delivered (259 chars — truncated), KPIs section, metric_alerts tool | widen goals section | — | P2 |
| 9 Economics | working | partial (see CEO #1) | shared | — | P2 |
| 10 UAE calendar | working | **missing** — `company_calendar` table exists (rows not measured); no prompt section | `reference` "UAE operating calendar" + emit upcoming company_calendar rows | 1 page | P2 |
| 11 Founder boundaries | expert | partial — founder_reserved rows, "Founder escalation discipline" principle, FAQ "Who approves refunds" reached the tail; the conduct rules live in `.claude/skills/quotesdone-session` and memory, not in a knowledge row | `policy` row "The founder's standing rules" (from the session skill §1–§3) | 1 page | **P1** |
| 12 Operating-model literacy | expert | present — Leadership OS block, TOM digest (cut), `docs/` | fix E2 | — | P2 (delivery) |
| 13 Crisis | expert | present — profession "Crisis coordination protocol" (undelivered); incident priorities | deliver E1 | — | P2 |
| 14 Decision hygiene | expert | present — decision_record_contract, strategic-review steps | worked example (shared with CEO #6) | — | P2 |
| 15 Meetings | working | present — SOPs | — | — | — |
| 16 Communication | working | present — art. 13, writing:human_voice (LAYER 1 _global) | — | — | — |
| 17 Live data | expert | LAYER 3 cut (E2) | fix E2 | — | **P1** (delivery) |
| — Exam remit | — | asked trade-regulator questions | give the examiner this standard as the remit | — | P2 |
| — Contamination | — | 5 trade-route exam fills in LAYER 4 | quarantine | — | P2 |

**Reasoning gap.** The Chief of Staff approves everything it reviews (2,282/2,282) and has no written test for
what it should return; it owns "which department owns an ambiguous request" without a rendered ownership map;
its brief template and arbitration protocol exist only in the undelivered layer. The exam measured a sourcing
clerk, not a chief of staff.

**P1 count: 6** (ownership map, brief template with example, stalled-task triage, review criteria, founder
standing rules, live-data delivery).

---

## 3. `cpo` — Chief Performance Officer / Corporate Performance Director (org_role `corporate_performance_director`)

**What it does today.** agent_runs 7d: 85 ok (cron). Context assemblies 30d: 112 (kb_usage_log 115).
review_chain as author: 602 (366 approve, 236 owned); as reviewer: 58 (owned). Exam: 20 since 3 Sep, **6
correct / 5 partial / 4 wrong / 5 not_covered = 30.0%**; **10/10 pack-file recall** (rfq_quality_gate.yaml,
quote_comparison_contract.yaml, Notification & Communications scenario …), 0 domain questions; 8 filled.

**Persona.** owned: diagnosis of a missed KPI; opening and closing improvement initiatives; promoting or
reversing a change on measured outcome; organisation design proposals. forbidden: changing the KPI definition
it is measured against; approving its own initiative outcome; raising a department's authority. authority
execute_medium, budget 0; employee_authority: coordinate autonomous, exec_review autonomous ("owns the weekly
performance review"), recommend autonomous ("may open improvement initiatives unprompted"), qa_gate gated,
escalate_founder advisory. required_inputs: change_deployment, improvement_lifecycle, metric_lifecycle,
strategic_review. output_contracts: kpi_diagnosis, improvement_initiative, outcome_grade. KPIs owned: 6.
responsibilities: "…Owns AI efficiency, automation coverage, cost per decision, process optimisation and
benchmarking. Answers one question: is this company measurably better than last week?"

**Knowledge inventory (agent-specific).**

| Source | Rows / size | Freshness | Covers |
|---|---|---|---|
| agent_knowledge profession | **1 row**, 729 chars | 6 Aug 2026 | "Product on a two-sided anonymous marketplace" — a product-design paragraph (quote-form fields, funnel measured at three points). **Not a performance-management row**, and undelivered (E1). |
| agent_knowledge experience | 10 | 5 Sep 2026 | 8 exam fills (trade-route YAML, executive-office pack files) + 2 lessons ("Watch for orchestrator-level dupl…", "When a task output is only 'I cou…'") |
| employee_knowledge | 15 (as CEO) | — | 4/12 layers bound |
| exam bank | 10 (10 pack recall) | 5 Sep 2026 | |
| fn_agent_context('cpo', 22000) | 31,238; production head 19,500 + tail | live | LAYER 1 8,587; LAYER 2 empty; KPIs block 619 (largest in exec); production tail LAYER 2c 2,881 (the "KPI missed in exec — org_task lane determination" playbooks) + "Executive Office / Chief of Staff — Operating Knowledge" 700 + 2d cut at 240 |

**Senior-staff standard — Head of Corporate Performance for an AI-run company.**

| # | Domain | Depth |
|---|---|---|
| 1 | KPI design: leading vs lagging, definition consistency (BR-040), "activity is not outcome" (BR-041), denominators and populations, null handling (`least()` ignores nulls), the "instrument measuring the wrong subject" test, freshness cut-offs | expert |
| 2 | Root-cause method for a missed KPI: is it the work or the target; one number, three causes; split populations by the fix date; deterministic band ("no throughput" ≠ under-performance) | expert |
| 3 | Improvement-initiative lifecycle: baseline → hypothesis → intervention → outcome ledger → grade → promote/reverse; what a valid baseline is | expert |
| 4 | Experiment design: A/B on a two-sided funnel, sample size and significance basics, guardrail metrics, when an A/B is impossible pre-launch | working |
| 5 | AI efficiency & cost per decision: ai_cost_log, tier mix (the large tier as the dominant cost), prompt cache hit rate (`prompt_tokens_details`), deterministic-first 95/5 policy, the gateway's ~900-token output cap, the paid-provider hold | expert |
| 6 | Automation coverage: which actions are deterministic vs model-routed, "held model = skipped, never error", the connectivity register | expert |
| 7 | Process optimisation: theory of constraints on the funnel, lean waste in the review chain (returns, rework rate), SLA compliance | expert |
| 8 | Benchmarking: marketplace benchmarks (quote turnaround, supplier response rate, reveal conversion, refund rate) and where the numbers come from | working |
| 9 | Weekly performance review: the scoreboard, the 63 goals, department KPIs, what gets an initiative opened | expert |
| 10 | Review-return analysis: the violated_rule vocabulary (is_actual_work, states_its_result, grounded_in_this_business), return rates by department (exec 324) | expert |
| 11 | Org design proposals: Phase A constraints, role merge/park rules ("a merge that collapses a handoff"), what needs a change request | working |
| 12 | Data literacy: the OS tables (company_goals.measure_sql, knowledge_kpis, agent_runs semantics, workflow boards), SQL-level verification | expert |
| 13 | Quality gates: qa_gate authority, what a failing gate looks like, the QA suite | working |
| 14 | Live data: fn_ws_company, kpi snapshots, outcome ledger | expert |

**Gap table.**

| Domain | Depth | Today | Ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| 1 KPI design | expert | **partial** — BR-040/041 (frozen rules), metric_definition rows (Automation coverage, Cost per completed case, Evidence completeness, Exception rate, Outcome quality, Rework rate, SLA compliance, Work completion rate); the measurement-validity lessons (wrong subject, null handling, denominators, freshness) are in finance failure modes and in `MEMORY.md`, not in exec scope | ops_knowledge exec `failure_mode` set (senior_expert_uae): 10 measurement-validity failure modes taken from the company's own recorded lessons, each with the detection query | 5 pages / 12 chunks | **P1** |
| 2 Root-cause method | expert | partial — playbook "root cause: is it the work or the target?", decision rule "detect variance against target", the deterministic "no throughput" band in improvement_plan text | `decision_playbook` "KPI-miss diagnosis" with the cause taxonomy and 3 worked diagnoses | 3 pages | **P1** |
| 3 Initiative lifecycle | expert | partial — required_inputs name improvement_lifecycle/metric_lifecycle; strategic-review step 6 "open an outcome record with a baseline"; **no row defines a valid baseline or the grading rule** | `standard_operating_procedure` "Improvement initiative: baseline, grade, promote/reverse" with thresholds | 2 pages | **P1** |
| 4 Experiment design | working | missing | `reference` "Experiments on a pre-launch two-sided funnel" | 2 pages | P3 |
| 5 AI efficiency & cost | expert | **missing in exec scope** — the facts (tier share, cache field name, 900-token cap, hold behaviour) live in memory/`docs/`; finance KPI "Cost-per-reveal and the LLM tier that quietly dominates the bill" is in finance scope | `reference` "AI cost model and levers" (LIVE-fetch from ai_cost_log) + cross-scope the finance KPI row | 2 pages | **P1** |
| 6 Automation coverage | expert | partial — metric_definition "Automation coverage"; connectivity register function exists | `reference` on how coverage is computed and what counts | 1 page | P2 |
| 7 Process optimisation | expert | partial — metric rows Rework rate / SLA compliance; no method row | `decision_playbook` "Find the constraint in the funnel" | 2 pages | P2 |
| 8 Benchmarking | working | missing | `reference` with marketplace benchmark ranges (marked verify/source) | 2 pages | P3 |
| 9 Weekly review | expert | present — SOP Weekly Executive Review; exec_review tool; KPIs block delivered | — | — | — |
| 10 Review-return analysis | expert | partial — data exists (review_chain.violated_rule); no row explains the vocabulary or return targets | `reference` "Review-return taxonomy and targets" | 1 page | P2 |
| 11 Org design | working | present — Phase A rules; memory "a merge that collapses a handoff" not in a row | `policy` row "Org-change rules" | 1 page | P3 |
| 12 Data literacy | expert | partial — quotesdone_os@working binding; `docs/` schema mirror | `reference` "Where each KPI's number lives" (table/function per metric) | 2 pages | P2 |
| 13 Quality gates | working | present — qa_gate authority, QA suite | — | — | — |
| 14 Live data | expert | LAYER 3 cut (E2) | fix E2 | — | **P1** (delivery) |
| — Profession row | — | the single row is a product-design row | replace with a performance-management profession set (items 1–3, 5) | — | **P1** |
| — Exam | — | 10/10 pack recall | remit = this standard | — | P2 |

**Reasoning gap.** The CPO's whole job is diagnosis, and its department holds one diagnostic question ("is it
the work or the target?") and no method. The company has learned a great deal about measurement — a dozen
recorded lessons about instruments, denominators, nulls and freshness — but those lessons sit in finance
failure modes and in the operator's memory files, not in the CPO's scope. Its only profession row is about
product design.

**P1 count: 6** (measurement failure modes, KPI-miss playbook, initiative lifecycle SOP, AI-cost reference,
live-data delivery, profession-row replacement).

---

## Department summary — exec

| Agent | P1 | P2 | P3 |
|---|---|---|---|
| ceo | 6 | 10 | 1 |
| brief | 6 | 11 | 0 |
| cpo | 6 | 5 | 3 |
| **total** | **18** | **26** | **4** |

Of the 18 P1 rows, 3 are the same delivery defect (E1/E2) counted per agent.

**Top 5 ingest items for exec (in order):**

1. **Deliver what exists** — repair the LAYER 2 admission guard and the 19,500-char head cut so the CEO's
   strategy row, the Chief of Staff's 12 topics, the live company state (`fn_ws_company`), the OS objectives
   and the deterministic rules (founder-reserved keys, legal_triggers, dispatch caps) reach the prompt; emit
   `company_economics` (10 rows, every_employee_must_know) as a section; quarantine the trade-route exam fills
   contaminating LAYER 4 for all three. Zero pages.
2. **An executive senior-expert layer** (the department has none): 8–10 marketplace-strategy playbooks
   (cold start, category-liquidity threshold, take-rate defence, circumvention economics, anonymity trade-offs,
   capital allocation with the budget table, growth-engine state), each with worked cases; cross-scope the
   finance rows "GMV, take rate, net revenue", "The AED 1,000,000 back-solve", "Stress-testing the model" and
   6 measurement failure modes into exec scope. ~15 pages / 40 chunks.
3. **Chief-of-Staff operating kit**: rendered "Who owns what" map generated from org_role; the founder brief
   template with a real example; stalled-task triage playbook; review criteria using the existing
   violated_rule vocabulary; the founder's standing rules as a policy row. ~8 pages / 20 chunks.
4. **Performance-management method for the CPO**: 10 measurement-validity failure modes from the company's own
   lessons with detection queries; KPI-miss diagnosis playbook with 3 worked diagnoses; initiative lifecycle
   SOP with baseline/grade thresholds; AI-cost model reference (LIVE-fetch). Replace its product-design
   profession row. ~12 pages / 30 chunks.
5. **UAE market primer** for the CEO/CoS (procurement norms, payment-term culture, buyer segments, seasonality,
   licence landscape, government e-procurement channels, D33 — every figure marked verify/source) and a
   competitor map. ~13 pages / 30 chunks. Then re-remit the examiner for all three roles.

**Not measured / boundaries.** The 276 `evolution` rows (in exec scope) beyond count and role names; the
content of the 271 V2 pack rows beyond titles; `company_calendar`, `department_budget`, `agent_evals` rows;
why 330/330 decided CEO reviews are escalations (reason and reviewer columns were null on 651 exec review
rows); semantic retrieval output (`fn_ops_knowledge_match`, `kb_search`); the full 191-source list for
kb category `exec` (only the 25 largest were read).
