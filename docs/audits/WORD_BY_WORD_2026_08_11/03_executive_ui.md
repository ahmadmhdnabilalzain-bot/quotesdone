# SPEC #3 — `OS 2.txt`, the executive UI (1,147 lines)

Audited 2026-08-11 14:45–15:15 UTC. **This is the file the 152-check scorer measures.** The scorer
was **not** run for this ledger and no MET was accepted as evidence — that instrument reporting
126/152 while the codebase got worse is the reason this session exists.

| PRESENT | PARTIAL | ABSENT | CONTRADICTED | total |
|---|---|---|---|---|
| 63 | 71 | 39 | 3 | **176** |

The file is in three blocks: **17 "ideal layout" screens** (L1–L431), **11 architecture layers**
(L433–L822), and **40 numbered capabilities** (L823–L1147, numbered 21–40 continuing the first
block's numbering).

---

## Block 1 — the 17 screens (L1–L431)

| # | screen | verdict | evidence |
|---|---|---|---|
| 1 | Executive Home — health %, revenue today/monthly, goal %, customers active, suppliers active, employees working, bottlenecks, mood | **CONTRADICTED** | every slot exists in `fn_ws_exec_home` and renders. **Revenue Today and Monthly Revenue are AED 0, Customers Active is 0**, and the screen presents them beside a Company Health percentage computed from goals of which **55 of 63 have no measure**. The spec's example screen shows AED 3,450 / 241 customers / 96% health; production shows 0 / 0 / a high percentage. A health score that stays high while revenue and customers are zero is the `least(100,NULL)` failure rendered as a headline |
| 2 | AI Conversation — 6 example questions | PRESENT | `Console()` + `fn_os_command`; the six are free-text executive questions and the console routes them |
| 3 | Live Company — work moving between departments | PARTIAL | `fn_ws_live_company` exists and `review_chain` (1,557 rows, 7 stages) is a real flow across 14 departments. Nothing animates; the screen is a list |
| 4 | Organization — CEO→CoS→Director→Specialist, click anyone | PRESENT | `org_agents` with `manager_key` on 93 of 94, all resolving; `AgentsApp` + `AgentDrawer` open an employee |
| 5 | Employee View — 9 things visible (thoughts, tasks, decisions, performance, confidence, knowledge, workload, plans, learning) | PARTIAL | `AgentDrawer` shows tasks, decisions, performance, knowledge, workload and improvement plan. **"Current thoughts" has no store**; learning progress is `knowledge_exam_results` and is not surfaced per employee |
| 6 | Company Timeline — timestamped, "nothing hidden" | PARTIAL | `os_audit_log` 9,293 rows and `company_event` 1,114. The spec's five example entries are customer/supplier/RFQ/refund events — **four of the five cannot occur** |
| 7 | Mission Control — 10 OS nodes, connections animate on information flow | PARTIAL | all 10 OSes exist with health scores; `event_delivery` 1,601 rows is the flow. **No animation, no live node graph** |
| 8 | Digital Twin — "SimCity", department health, employee workload, live KPIs | PARTIAL | 12 KPI-snapshot tables (34 rows each), `department_budget` 25, `org_agents.max_open_tasks`. It is a table of numbers, not a spatial model |
| 9 | Approval Center — decision inbox, 5 named approval types, "everything else automatic" | PRESENT | `agent_actions` pending queue + `fn_approval_decide` + `fn_approval_list`; `<OperationsApp>` and `<AssistantApp>` render it. 4 of the 5 named types have a real path (budget, supplier suspension, new category, new policy); **"Approve New AI Skill" has none** |
| 10 | Executive Reports — never PDFs, drill down, see contributors, approve suggested actions | PRESENT | `fn_report_generate`, `fn_report_drilldown`, `fn_report_recommendation_approve`, `ReportViewer` component. **Drill-down is genuinely generic** — `FK_ENTITY` maps any foreign key to its entity |
| 11 | Intelligence Center — 9 items | PARTIAL | risks/opportunities/forecast/supplier health/AI spending PRESENT (`fn_strategy_risk`, `fn_opportunity_scan`, `fn_finance_forecast`, `supply_health_snapshots` 50, `fn_check_spend`). **Competitors → `market_intel` 0 rows; customer behaviour → 0 customers; growth probability → no producer** |
| 12 | Company Memory — search anything, 4 example questions | PRESENT | `fn_memory_search`, `org_memory` 624, `institutional_memory` 362, `decision_log` 1,479. Three of the four example questions are answerable; "Why did we reject Supplier X?" has no rejections to cite |
| 13 | Command Palette — CTRL+K, 11 example commands | PARTIAL | the palette exists (`CommandItem`, `setPaletteOpen`). It navigates **modules only** — of the 11 examples, "Open Finance"/"Show Customers"/"Marketing"/"Health" resolve to modules; "Find Supplier", "Approve", "Restart AI", "Cash Flow", "Forecast" do not |
| 14 | Notifications — grouped Critical/Important/Suggested/Completed, "AI already handled 95%" | PARTIAL | `NotificationsBell` + `fn_ws_notifications` + `fn_notifications_digest`. Grouping by those four bands is not implemented, and the 95%-handled figure has no producer |
| 15 | Interactive Company Map — departments, processes, employees, customers, suppliers, knowledge | PARTIAL | `graph_nodes` **829** across 9 classes: knowledge 368, employee 93, category 86, supplier_pool 86, responsibility 84, goal 63, department 25, workflow 14, operating_system 10. **Customers absent** (0 rows); processes present as `workflow` |
| 16 | "What if?" — the Meta Ads example returning revenue +12%, leads +18%, profit +7%, confidence 84% | PARTIAL | `fn_what_if` + `simulations` (**6 rows**). The triple and a confidence were added 11 Aug; five historical rows from 6–28 July lack them. As already recorded, the two universals over this table have **no time window**, so they cannot pass while those five exist |
| 17 | Voice — "Good morning" spoken briefing | PARTIAL | `IntakeAudio()` handles audio intake; `fn_founder_brief` and `fn_company_brief` produce the briefing text. **No speech output**, and the example briefing's figures (187 RFQs, 12 suppliers, AED 4,820) are all zero |
| — | L415–427 **"Give the AI permission to disagree with you"** | **PRESENT** | `fn_challenge`; `review_chain` records 4 `reject` and 8 `request_revision`; `decision_log.alternatives` (added 11 Aug) carries the verdict the gate rejected. The spec's own example — the Chief of Staff recommending *against* a founder instruction with three lower-risk alternatives — is the exact shape now implemented |
| — | L431 design principle: "walking into the headquarters of a company that has been working all night" | PARTIAL | literally true of the internal company: `company_reflect_nightly` runs at 21:30 UTC daily, 166 cron jobs run through the night. The business half is asleep because it has no customers |

---

## Block 2 — the 11 layers (L433–L822)

| layer | verdict | evidence |
|---|---|---|
| 1 — Executive Lobby: live status, departments glowing when busy, notifications flowing, live revenue/customers/suppliers | PARTIAL | live suppliers PRESENT (20,470). **Live revenue 0, live customers 0.** No glow, no motion |
| 2 — Company Digital Twin: 13 named object classes all existing and updating in real time | PARTIAL | 9 of 13 exist as populated stores (suppliers, employees, knowledge, AI, workflows, infrastructure, risks, costs, strategy). **Customers, RFQs, Payments, Revenue are empty.** "Real time" is cron-driven, not streamed |
| 3 — Executive Intelligence: prose insight instead of charts, with a causal claim and a recommendation | PARTIAL | `fn_company_situation`, `fn_founder_brief`, `fn_officer_recs` produce exactly this prose form. The example's causal chain (revenue miss ← supplier response time ← MEP) needs data that does not exist |
| 4 — Living Organization: 10 fields per employee | PARTIAL | same as screen #5 — 8 of 10; "Current Thoughts" and per-employee "Learning Progress" are not stored |
| 5 — Executive Meeting Room: Monday CEO meeting, 10 named participants, 6 sections each, debate, recorded, replayable | PRESENT | `exec_meeting_weekly` cron at **`0 5 * * 1` (Mondays 05:00 UTC)**, `fn_exec_meeting`, participants are the 10 OSes. Meeting #42 carries 12 objects with `rank`/`owner`/`title`/`priority`/`why`. **Replay is PARTIAL** — the record exists, no replay UI |
| 6 — Company Brain: one page, the whole graph, 9-hop chain Customer→RFQ→Supplier→Quote→Revenue→Marketing→Knowledge→Lessons→Strategy | PARTIAL | `company_os` module renders `graph_nodes` 829 / `graph_edges` 644. **Of the 9 classes in the chain, 4 exist** (supplier via `supplier_pool`, knowledge, and — as adjacent classes — goal/strategy). Customer, RFQ, Quote, Revenue, Marketing are absent because the rows are |
| 7 — Time Machine: slide back a week, a month, six months; 6 dimensions | PARTIAL | `company_snapshot` holds **14 days**. A month is not reachable and six months is not reachable. `fn_company_snapshot` writes all 6 dimensions correctly since 9 Aug; the 11 older snapshots predate the fix and **must not be back-filled** — writing a customer count into a day nobody measured it would be reconstructing a measurement never taken |
| 8 — Future Simulator: 4 example questions | PARTIAL | `fn_what_if`, `fn_simulate`, `fn_simulate_growth` (the one dead routine), `scenario_library`. Of the four examples, "What if OpenRouter prices double?" is genuinely answerable today; the other three need demand data |
| 9 — Company Genome: 11 stored attributes, "every AI employee inherits these automatically" | **PRESENT** | `company_constitution` **20**, `company_vision` **1**, `culture_principle` **8**, `company_economics` **10**, and `fn_agent_context` emits them as LAYER 1 to every employee. The inheritance clause is implemented, not just the storage |
| 10 — Company Consciousness: nightly self-questioning, 9 questions, "no human starts this" | **PRESENT** | `company_reflect_nightly` cron at **`30 21 * * *`**, `fn_company_reflect`, `company_reflection` **14 rows**; plus `agent_reflect_weekly` at `0 2 * * 0`. It runs unprompted every night. This is one of the most faithfully implemented sections in the eight files |
| 11 — Executive AI Companion | PARTIAL | `fn_ea_assistant`, `fn_ea_agenda`, `ws.ea` module. `ea_meetings`, `ea_events`, `ea_reminders` are all **0 rows** |

---

## Block 3 — capabilities 21–40 (L823–L1147)

| # | capability | verdict | evidence |
|---|---|---|---|
| 21 | Enterprise Event Nervous System — 9 named events | **PARTIAL — and this is the sharpest measurable gap in the file** | `company_event` carries 17 live types. Mapping the spec's nine: `rfq.created` PRESENT (type exists), `payment.received` PRESENT, `knowledge.updated` PRESENT, `os.health_changed` ≈ "Infrastructure warning" PRESENT. **Five have an emitter that has never fired**: `fn_emit_customer_registered`, `fn_emit_supplier_approved`, `fn_emit_campaign_launched`, `fn_emit_competitor_pricing_changed`, and "AI confidence dropped" which has **no emitter at all**. Four of those five are among the 30 trigger functions with no table reference — built, bound, never triggered |
| 22 | Organizational Graph Engine — 7 named node classes | PARTIAL | 9 classes exist, **4 of the 7 named are absent** (Customer, Quote, Revenue, Marketing Campaign). Category, Knowledge, Employee PRESENT |
| 23 | Autonomous Resource Allocation | PARTIAL | `allocation_change` **12 rows, all `resource='ai_budget_aed'`**. `fn_reallocate` moves AI budget only. Marketing spend is AED 0 on paused campaigns; supplier onboarding capacity (`invite_daily_cap` 10 against a sendable pool of 16,238) is a genuinely movable resource and is not moved |
| 24 | AI Board of Directors — 7 named advisors | **PRESENT** | `board_advisor` **7 rows** with `lens` and `asks` columns; `board_opinion` **98**; `fn_board_review`, `fn_board_report`. `decision_record` 11 rows, of which 10 reviewed — #42 is `executed` and deliberately unreviewed |
| 25 | Multi-Model Intelligence — 7 capabilities | PARTIAL | `model_catalog` 14 models with `tier_role` and `best_for`; `model_policy` 61; `fn_select_model`, `fn_ai_route`, `fn_ai_route_tier_rank`. Fast routing, deep reasoning, translation, coding, summarisation PRESENT. **Vision and OCR ABSENT** — no vision model is registered and no OCR routine exists anywhere |
| 26 | Autonomous Procurement | PARTIAL | `fn_procurement_analysis`, `po_orders`/`po_lines`/`po_vendors` all **0 rows** |
| 27 | Knowledge Confidence Layer — confidence, source, last validation | **PRESENT** | `agent_knowledge` carries `confidence`, `source_ref`, `validation_status`, `review_due`, `valid_until`, `supersedes_id`, `supporting_evidence`; `fn_knowledge_provenance_stamp`, `fn_require_grounding`, `fn_kb_validate`. All three named fields exist as columns |
| 28 | Strategic Memory | PRESENT | `institutional_memory` 362, `org_memory` 624, `fn_promote_memory`, `memory_promotions` 60 |
| 29 | Autonomous Opportunity Detection | PARTIAL | `fn_opportunity_scan` runs on cron. The named missing class is **rising keywords** — there is no search-term stream (`inquiries` 0; `category_keyword` is a static dictionary, not a time series), so a "rising" keyword would be invented |
| 30 | Marketplace Health Index | PARTIAL | `supply_health_snapshots` **50 rows**, `fn_supply_health`, `fn_supply_gap_scan`, `v_supply_gap`. Measures the supply side honestly; the demand side of a marketplace index is absent |
| 31 | Organizational Energy | PARTIAL | `org_tasks` depth, `max_open_tasks`, `fn_ops_metrics`. **No single "energy" measure exists** |
| 32 | AI Reputation System | PRESENT | `agent_reputation` **66 rows**, `fn_reputation_recompute` (one of the 36 duplicated definitions) |
| 33 | Executive Replay | PARTIAL | `company_snapshot` 14 days, `os_audit_log` 9,293, `decision_trace` **4 rows**. The record exists; **no replay surface** |
| 34 | Organizational Stress Testing | PARTIAL | `scenario_library` **19 scenarios, all with `last_run`**, `fn_scenario_run`, `fn_scenario_run_all`, `fn_scenario_verdict`. **The runner checks that the named departments exist, are active, are staffed and are managed — it does not inject the failure**, and its own recorded verdict text says so. See spec #7 §11: 13 of the 16 named exception scenarios have no scenario at all |
| 35 | Autonomous Hiring & Restructuring | PARTIAL | `fn_org_exec_invite`, `ensure_category_agent`, `org_onboarding` 16, `org_designer` employee. Creating a department is hiring, and the guard `fn_org_authority_guard` correctly demands `app.change_reason`. **No routine proposes a restructure** |
| 36 | Explainable AI Workspace — 7 fields per recommendation | PARTIAL | `agent_actions` carries `evidence`, `risk`, `confidence` — **3 of 7**. `assumptions`, `alternatives`, `expected_impact`, `cost` are not columns. `alternatives` now exists on `decision_log` but not on `agent_actions`, which is what the field test reads |
| 37 | Continuous Benchmarking | PRESENT | `prompt_benchmarks` **21 rows**, `fn_model_benchmark`, `fn_eval_run`, `fn_eval_snapshot`, `fn_llm_drift_watch`, `fn_model_catalog_drift` |
| 38 | Digital Operating Manual — every policy, decision rule, department, always current | PRESENT | `os_runbooks` **106**, `decision_policy` 28, `company_constitution` 20, `ops_knowledge` 3,959, `fn_sop_update`, `fn_doc_control`. **PARTIAL on "always current"** — 21 duplicate runbook titles and 1,197 duplicate `ops_knowledge` rows mean two answers can disagree |
| 39 | Autonomous Governance — 6 monitored conditions, can pause automation | **PRESENT** | policy violations → `fn_policy_consistency_check`; excessive autonomy → `fn_autonomy_audit` + `fn_autonomy_control_guard`; missing approvals → `fn_approval_trace_audit`; conflicting decisions → `fn_decision_conflict_scan`; regulatory changes → `fn_regulation_watch` + `fn_regulation_propagate`; security exceptions → `fn_security_audit`. **And it can actually pause**: `fn_org_task_autonomy_brake`, `fn_phase1_disarm`, `fn_autonomy_dispose`. All six plus the pause |
| 40 | Company Maturity Index — 10 dimensions | **ABSENT** | `fn_org_scorecard` and `fn_health_index` exist and `company_index` holds 45 rows, but **no maturity index over the 10 named dimensions exists**. The closest instrument is the 152-check score, which measures spec conformance, not business maturity |

---

## The three CONTRADICTED verdicts in spec #3

1. **Executive Home (screen #1)** presents a high Company Health beside AED 0 revenue and 0
   customers. The health number is computed over 63 goals of which 55 have no measure.
2. **The 152-check scorer itself.** `verify_os2_blueprint.mjs` is the instrument for this file and
   it reported **126/152 rising** in a session that added five redundant function definitions and
   left 96 unresolvable identity rows in place. It measures 152 of the **176 claims counted here**,
   and none of the 24 it does not measure are minor: they include the Company Maturity Index,
   vision/OCR, the five never-fired events, and the Executive Home contradiction above. A scorer is
   not wrong for being incomplete — it is wrong when its number is read as the file's verdict.
3. **"Nothing hidden" (screen #6).** The timeline is honest about what it has; the claim is
   contradicted by the fact that four of the five example entries are event classes whose emitters
   exist, are bound to triggers, and have never fired — so the timeline looks complete while being
   structurally incapable of showing the company's core business.

## What spec #3 gets right and should not be lost in the failures

Layer 9 (Company Genome), Layer 10 (Company Consciousness), §24 (AI Board), §27 (Knowledge
Confidence), §37 (Continuous Benchmarking) and §39 (Autonomous Governance) are all **fully
implemented, running on cron, and populated** — including the parts almost nobody builds: a company
that asks itself nine questions every night at 21:30 UTC without a human starting it, and a
governance engine that can actually pause its own automation.
