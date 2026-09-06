# Knowledge audit — data_intel (Data & Experimentation)

Measured 6 Sep 2026 on project htdblwldjkcgjvmqkbeh, read-only, no model calls. Scripts: scratchpad `ka01`–`ka11` (`scripts/phase_c/lib/db.mjs`, 8 s statement timeout). Every number was read from the database or the repository on that date; anything not measured is marked. External sources marked **verify** must be checked for current edition/URL/portal before ingest.

Agents in scope (org_agents.active, department = data_intel): `intel_director`, `analytics` (title "Data Engineer"), `bi_analyst`, `market_analyst`, `supplier_analyst`, `knowledge_director`, `process_improvement_mgr` — 7 of 54 active AI employees.

---

## 0. Findings that apply to every agent in this department

The mechanism findings in `product_eng.md` §0 (LAYER 2 structurally empty; `dept_library` has 0 rows for `data_intel`; `field_corpus` computed but never emitted; unscoped `kb_search` k=8; exam samples off-remit sources and writes wrong verdicts as knowledge; 44 validated records corpus-wide) were measured across all 13 agents and apply here unchanged. Department-specific measurements:

| # | Finding | Evidence |
|---|---|---|
| 1 | **This department got the 3 Sep deep-expert build and it is good — but it reaches agents only as 700-char snippets or 8 cosine hits.** 101 `ops-data_intel-deep-*` records (module `data_intel_expert`; 2 Sep; 100% embedded; 0 validated), ~2.0–2.6k chars each, written for this marketplace: "Marketplace liquidity is the master metric, not GMV", "A 30-day total is not a run rate", "Statistical power and MDE for low-traffic decisions", "Network interference: why marketplace A/B tests violate no-spillover", "Switchback and interleaving designs", "Building the AED 1M forecast bottom-up from reveal drivers", "Do not fabricate data to turn a gate green". Probe "define time-to-first-quote and match rate…; A/B test sample size" → LAYER 2c returned 2,460 chars (3–4 truncated records). | `deep_titles_data_intel`, `di_deep_content`, `ctxq_analytics`, `search_di`. |
| 2 | **The reachable pool is 926 records; the `knowledge` department's 413 records are outside it.** `fn_dept_scope('data_intel')` = [analytics, data_intel, intelligence, knowledge_eng]. Reachable: company 200, external 21, knowledge_eng 164, intelligence 136, data_intel 110, analytics 28 (department-scoped) + 267 role-scoped. `dept_key='knowledge'` (413 rows: 309 unscoped + 104 role-keyed `administration-and-operations-*`) is **not** in scope — only `process_improvement_mgr` holds an administration-and-operations role. The `analytics` pack's 108 role-keyed rows are split across 4 packaged roles; `data-analytics-and-intelligence-reviewer-auditor` (27 rows) is held by nobody in scope. | `ka10_pool.mjs`, `knowledge_dept_role_keys`, `role_identity`. |
| 3 | **Market/UAE-statistics knowledge is absent.** Keyword census over the data-department `ops_knowledge` rows: Dubai Statistics 0, Department of Economic Development 0, RERA 0, FCSC 0, Dubai Municipality 0, Six Sigma 0, "power analysis" 0, "take rate" 4, "time-to-quote" 0, liquidity 15, A/B 13. `kb_chunks` full-text: rera 82 chunks across 19 categories (supplier-category packs, not market data — **verify**), six sigma 548 chunks / 28 categories (generic). The `market_analyst` probe "UAE construction market trend and new tender signals this month; Dubai statistics sources" returned LAYER 2c = **65 chars** (`PHASE2_CROSSWALK.md`). | `ops_knowledge_keywords_data_depts`, `kb_fts_*`, `ctxq_market_analyst`. |
| 4 | **The V2 `intelligence`/`analytics` pack rows are template prose.** 40 `intelligence` professional_knowledge rows ("Cohort Analysis — operating knowledge", "Forecasting — operating knowledge", ~2.3k chars) follow the same "the department should first establish the entity and workflow state…" template as the IT pack; `01_ROLE_EXPERTISE_V2.md` (10,486 chars) and `02_DECISION_PLAYBOOKS.yaml` (38,797 chars) in the `analytics` pack are the substantive V2 items and are role-keyed. `kb_chunks` `analytics` (52,649): statistics/ML textbooks (Bayesian Data Analysis 1,693, ESL 1,638, Bishop 1,492, ISLR 1,276, DAMA-DMBOK 1,371, Bandit Algorithms 1,312) plus NIST Big Data framework reference-list chunks ("1817 https://www.federalregister.gov/…", 201 chars). No marketplace-analytics or experimentation-practice text (Kohavi et al.) was found by citation sample. | `ops_intelligence_prof_sample`, `ops_analytics_prof_sample`, `kb_sample_analytics`, `kb_docs_analytics_sources`. |
| 5 | **Metric estate**: `metric_definition` 14 rows, all active with `measure_sql`; latest `metric_snapshot` for all 14 is fresh (6 Sep), 0 errors, 11 valued, 3 null without error (`quotes_per_inquiry`, `refund_rate`, `rfq_ready_pct`). **None of the 14 is owned by `data_intel`** (owners: finance, it, knowledge, supplier_success, exec, customer_success, marketing). `company_goals`: 63 active, **31 measured** (49%) — data_intel 4/4, product_eng 5/10, growth 0/5, legal 0/4, finance 4/12. The brief's "22 of 61" is stale: measured today 31 of 63. `employee_kpi` for the 7 agents: 14 rows, 14 with SQL, 14 measured. | `metric_def`, `metric_latest`, `company_goals*`, `employee_kpi_sql`. |
| 6 | **Exam-fill pollution is heaviest here.** Wrong verdicts filled into `agent_knowledge`: intel_director 7/8, supplier_analyst 7/8, process_improvement_mgr 6/7, knowledge_director 6/6, market_analyst 5/5, bi_analyst 3/15, analytics 3/6 (37 of 55 wrong answers written back as "experience"). 12 of the department's 71 exam questions come from supplier-category packs (e.g. `086_lifts-and-escalator-suppliers/retrieval_policy.yaml` for `analytics`; `047_security-companies/qualification_playbook.md` for `process_improvement_mgr`). | `exam_wrong_filled`, `exam_question_sources_by_agent`, `exam_gaps`. |
| 7 | **What the agents do today is deterministic lane work.** Latest runs for analytics, bi_analyst, intel_director, knowledge_director, supplier_analyst, process_improvement_mgr, market_analyst: "org_task … determined from N fact(s) and playbook kpi.missed in data_intel … used_llm:false … fn_recommend_deterministic". All 70 runs in 7 days are `ok`; none used a model. `kb_usage_log` in 30 days: intel_director 16, analytics 6, market_analyst 4, knowledge_director 1, others 0 (company-wide leaders: cfo 254, brief 177). | `runs_notes_sample`, `agent_runs_7d`, `kb_usage_30d`. |

**Not measured:** reader of `os_runbooks`; `artifact_review` (0 rows for these agents); whether `fn_ops_department_context` (Layer "HOW YOUR DEPARTMENT IS DEFINED", 975 chars) reaches the data_intel packs' SOPs beyond the 2-rule digest; `metric_lifecycle`/`knowledge_lifecycle` workflow run counts. `knowledge_exam`, `agent_train` and `fn_knowledge_exam_sit` were not invoked (paid).

---

## 1. `intel_director` — Data & Intelligence Director

**What it does today.** Runs/7d: 9 ok (17 since 9 Aug; deterministic `kpi.missed` lane). Exam: 6/20 (30%), confidence 0.45, 14 gaps, 8 filled (7 from wrong verdicts). Retrievals/30d: 16 (last 4 Sep, "run agent action objective step"). Reviewer: 76 approve / 72 owned / 0 revisions; author 69 approve / 11 owned / 23 undecided. KPIs (6, all measured): "Categories with all eight knowledge modules" **2% vs 100**; "Category list matches the specification" 2 vs 0; "Exam coverage" **1.85% vs 80**; "Forecasts produced" 2 vs 4; "Goal periods tracked" 32.91% vs 80; "KPI instrumentation" 88.24% vs 100 — five of six missed. Authority `execute_medium`, budget 0; owns metric definitions and their SQL, forecast methodology, what intelligence reaches the executive, knowledge governance priority; forbidden: changing a department's reported actual, approving its own analysis, setting a target. Holds 4 packaged roles (data-analytics-and-intelligence-director/operations-specialist, supplier-knowledge-director/operations-specialist). Workflows: knowledge_lifecycle, metric_lifecycle, strategic_review (step actor).

**Knowledge inventory.**

| Source | Holds | Reaches prompt? |
|---|---|---|
| `agent_knowledge` profession | 1 row "Instrumenting a company so nobody has to guess", 728 chars, 6 Aug, unvalidated | No (LAYER 2 empty) |
| `agent_knowledge` experience | 11: 8 exam-filled data_intel deep summaries (bottom-up AED 1M forecast, price-experiment hazards, match precision/recall, dashboards vs decisions, "fill rate looks fine but revenue is flat", live P&L, "Proposal Management — evidence…" [bizdev pack, off-remit], `retrieval_policy.yaml` [category pack, off-remit]) + 3 org lessons (~200 chars) | Yes, LAYER 4 (3,500 cap) |
| `employee_knowledge` | 15 domains: company/goals/constitution/priority/universal expert L2; engineering, finance, hr, legal_uae, marketing, operations, procurement, sales_crm awareness L4; quotesdone_os working L5; communication L8 — **no L1 domain expert layer** (no `data_analytics` binding) | declarative |
| `ops_knowledge` reachable | 926 (see §0.2); the 101 deep records + 4 `metric_lifecycle` + 5 `org_task_lane` records are the estate-specific core | keyword/cosine only |
| `metric_definition` / `company_goals` / `employee_kpi` | 14 metrics (none owned by data_intel), 63 goals (31 measured), 14 employee KPIs for this dept | LAYER 3 live / "YOUR KPIs" 494 chars |
| `kb_chunks` in scope (`analytics`, `intelligence`, `data_intel`, `knowledge_eng`) | analytics 52,649 (statistics/ML textbooks, DAMA-DMBOK, NIST Big Data); no `intelligence`/`data_intel`/`knowledge_eng` categories measured | not scoped (0.3) |
| `skills_matrix` | no rows | — |
| `fn_agent_context('intel_director',22000)` | 31,269 chars; LAYER 2 = 1; LAYER 1 = 8,879; LAYER 4 = 3,502 | — |

**Senior-staff standard — head of data & intelligence for a two-sided B2B RFQ marketplace (UAE).**

| Domain | Depth |
|---|---|
| Marketplace metric system: liquidity/fill rate by category×emirate, match rate, time-to-first-quote, quotes per RFQ, reveal rate, take rate (3% reveal fee), supplier response rate, repeat-buyer rate, GMV vs revenue | expert |
| North-star + guardrail metric design; leading indicators for reveal revenue; Goodhart controls | expert |
| Instrumentation engineering on this estate: `metric_definition`/`metric_snapshot`, `company_goals`/`goal_period`, `employee_kpi.measure_sql`, fixture exclusion (ZZ DEMO / example.invalid), "instrument events not status columns" | expert |
| Forecasting: bottom-up from reveal drivers, run-rate vs 30-day totals, ranges with assumptions, the AED 1M by Aug 2027 target, forecast accuracy tracking (KPI 2 of 4 produced) | expert |
| Experimentation governance: when to A/B, when to switchback/interleave, MDE/power under thin traffic, price-experiment hazards, holdouts/incrementality | expert |
| Data quality & lineage: completeness/validity/uniqueness/timeliness/consistency, definition drift, denominator traps, idempotent importers (parser version in checksum) | expert |
| Executive reporting: weekly metrics review that yields decisions, variance with root cause, "never state what you have not measured" | expert |
| Knowledge governance (shared with knowledge_director): validation pipeline, exam coverage KPI (1.85%), 86 categories × 14 modules standard | working |
| Market & competitive intelligence oversight: UAE sources (see market_analyst), competitor pricing, signal capture KPI | working |
| Supplier/customer intelligence oversight: scoring model weights (`decision_policy score_w_*`), CLV/churn, coverage KPI (0.01%) | working |
| Statistics foundations: Bayesian vs frequentist inference, regression, survival/cohort methods, anomaly detection | working |
| Postgres/SQL for analytics: window functions, `date_trunc`, CTE hygiene, `least()` null trap, sampling limits under 8 s | expert |
| Privacy in analytics: PDPL minimisation, aggregation thresholds, no PII in reports to WhatsApp | working |
| AI-cost analytics: `ai_cost_30d`, `avoidable_ai_pct` (39.8 vs 10), cache hit measurement (`prompt_tokens_details`) | working |
| Team leadership: what each of the 6 reports owns; escalation to CEO/chief_of_staff | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Marketplace metric system | expert | **present** (deep records: liquidity master metric, fill rate, GMV vs revenue, leading indicators, attribution, segmentation) — but 0 `metric_definition` rows owned by data_intel and `time-to-quote` 0 mentions | Author `metric_definition` rows owned by data_intel for: fill_rate_by_cat_emirate, match_rate, time_to_first_quote_median, quotes_per_rfq (fix the null), reveal_rate, take_rate, supplier_response_rate (exists), repeat_buyer_30d; one `ops_knowledge` kpi record each with the SQL and denominator rule | 8 metrics + 8 records | **P1** |
| North-star + guardrails | expert | **present** ("A north-star metric for QuotesDone and the guardrails", "Guardrail metrics") | Validate the records (`validation_status`) | — | P3 |
| Instrumentation engineering | expert | **partial** — "Instrument events, not status columns", "Instrumenting the reveal payment", "Fixtures excluded by default" present; the estate mechanics (`goal_period` refresh, `metric_snapshot` cron, `no_measure_reason` convention, `employee_kpi` classes) are not a record | Reference record "how measurement runs on this estate" (tables, crons, who refreshes, the 32 unmeasured goals and their `no_measure_reason`) → `ops_knowledge` data_intel reference | 3 records | **P1** |
| Forecasting | expert | **present** (bottom-up AED 1M, run-rate rule, uncertainty ranges) — KPI 2/4 forecasts | Add a forecast template record (inputs, assumptions table, range, review date) + `forecast` output contract example | 2 records | P2 |
| Experimentation governance | expert | **present** (sizing, power/MDE, switchback, network interference, price hazards, inconclusive remediation) | Ingest Kohavi/Tang/Xu *Trustworthy Online Controlled Experiments* (**verify** licence — likely summary/notes only) or equivalent open material (e.g. Georgiev's experiment-design guides **verify**) → `kb_chunks` `analytics` source_kind textbook/guide | ~150 pages | P3 |
| Data quality & lineage | expert | **present** (dimensions, lineage, definition drift, denominator, idempotency) + DAMA-DMBOK 1,371 chunks | none beyond validation | — | P3 |
| Executive reporting | expert | **present** ("Weekly metrics review… decisions not status", "Dashboards vs decisions", "Reading a metric move") | Worked example: one real weekly review from `os_review`/`finance_kpis` with variance→root cause | 2 records | P2 |
| Knowledge governance | working | **partial** — KPI exam coverage 1.85%; the exam mechanism and its defects are not a record | Reference: exam loop (question source, grader, fill), its pollution, and the validation pipeline; from this audit §0 | 2 records | **P1** |
| Market intelligence oversight | working | **missing** (see market_analyst) | shared | shared | P2 |
| Supplier/customer intelligence oversight | working | **partial** — `decision_policy` weights exist; coverage 0.01% | Reference: the scoring model (weights, inputs, `use_capability_matching`) as a kpi/policy record | 2 records | P2 |
| Statistics foundations | working | **present** in kb_chunks `analytics` (Gelman, ESL, ISLR, Navarro) — unscoped retrieval | none (fix scoping) | — | P3 |
| SQL for analytics on this estate | expert | **partial** — "least() ignores nulls", "= any(subquery)" in memory only | 6 failure_mode records from memory lessons (least nulls, pct(got,0)=100 "absent input scores as satisfied", group per class, a score that fell because the clock moved, 30-day total) | 6 records | **P1** |
| Privacy in analytics | working | **missing** — PDPL 0 mentions in data-dept ops_knowledge | 1 policy record (aggregation threshold, PII redaction in reports/alerts; cite PDPL articles **verify**) | 1 record | P2 |
| AI-cost analytics | working | **partial** — metrics exist; the "tier is the bill", cache measurement lessons in memory | 2 kpi records | 2 records | P3 |
| Curriculum binding | — | no L1 `data_analytics` expert binding | Add `employee_knowledge` rows (data_analytics expert L1) | 1 row | P3 |
| Off-remit pollution | — | `retrieval_policy.yaml`, bizdev "Proposal Management" in LAYER 4 | Quarantine | — | P2 |

**Reasoning gap.** Decision playbooks: strong (45 `decision_playbook` records in data_intel). Thresholds: present in prose ("liquidity below ~40%… is a supply problem") but not as `decision_policy` keys or metric targets owned by the department. Decision trees: "Anomaly detection: real break vs noise vs broken meter" is a decision tree in prose. Worked examples: the memory lessons (denominator, clock moved, harness fixtures) exist outside tables. Runbook for a missed KPI: the `kpi.missed` lane playbook (deterministic). **P1 count: 4.**

---

## 2. `analytics` — Data Engineer (role: data_engineer)

**What it does today.** Runs/7d: 10 ok (deterministic). Exam: 7/29 (24%), confidence 0.61 (highest in dept), 22 gaps, 6 filled (3 from wrong). Retrievals/30d: 6 (last 16 Aug). Author 33 approve / 11 owned / 11 undecided. KPI: primary objective 100% (target 99.5). Authority advisory (`health_report`, `recommend`, `security_review`, `uptime_verify` autonomous; `code_selfheal`/`incident_fix` advisory); owns measurement SQL & pipeline design, data-quality rules; forbidden: changing a metric definition, reporting a number it also defined, writing to production business tables. Tools: `agent.train`. Outputs: measurement_path, data_quality_report.

**Knowledge inventory.** Profession 8 rows (avg 650 chars, 24 Jul, unvalidated, unreachable): Canonical metric dictionary (1,180), Experimentation standard (796), Forecasting & cohort methods (767), Insight communication standard (773), Data quality & definition governance (749), Role (690), 2 exam stubs (110/135). Experience 4: "The data pipeline can lie quietly: monitor the meters" (2,023), "Remediation: experiment inconclusive" (1,943), monthly review handoff (189), `retrieval_policy.yaml` (943, lifts-and-escalators pack — off-remit). `employee_knowledge`: 13 domains incl. data_analytics/engineering/ai_engineering/cybersecurity expert L1. `skills_matrix` avg 3.5 (Data & Analytics 4, OS & Tooling 3, PDPL 2). Role identity: data-analytics-and-intelligence-analyst-controller (27 role-keyed `analytics` rows incl. `01_ROLE_EXPERTISE_V2.md` 10,486 chars). Exam topics: 3 di_deep, 3 domain, 2 compliance, 1 each authority/catpack/ops/pricing/scope/standards. Sample gap facts: "Median hours from RFQ dispatch to the first quote that passes the 70/100 quality gate" (partial — the time-to-quote definition), "UAE Data Office… primary federal regulator" (partial, asked twice).

**Senior-staff standard — senior data engineer on a Postgres/Supabase estate.**

| Domain | Depth |
|---|---|
| Measurement SQL authoring: `measure_sql` contract (single numeric, fixture-excluded, period-bounded, null-safe), `metric_snapshot` cron, statement_timeout=8 s | expert |
| Event instrumentation: events over status columns, `decision_trace`/`action_execution`/`workflow_step_run` as the fact tables, xmin/xid attribution limits | expert |
| Data quality engineering: dimension checks as SQL, meters-vs-metrics monitoring, anomaly rules, freshness SLAs (`Data freshness commitments`) | expert |
| Pipeline idempotency: importer versioning, checksums with parser version, re-run safety, undo (`knowledge_ingestion_undo`) | expert |
| Postgres for analytics: window functions, materialised views, partial indexes, `EXPLAIN`, GIN/tsvector, pgvector/HNSW, `date_trunc`, timezone (UTC vs Asia/Dubai) | expert |
| Fixture/demo exclusion on this estate (ZZ DEMO, example.invalid, `demo_rehearsal_active`, rehearsal_window) | expert |
| Metric dictionary maintenance: `metric_definition` fields, direction/target, owner_dept, `no_measure_reason` discipline | expert |
| Experiment plumbing: assignment logging, exposure tables, switchback scheduling, guardrail computation | working |
| Supabase specifics: RLS effect on analytics reads (service role vs definer views), pg_cron scheduling, `pg_net` for exports, storage for reports/PDF | working |
| Cohort/retention & funnel SQL patterns for RFQ→match→quote→reveal | expert |
| Cost/usage telemetry: `ai_cost_log`-type tables (the exam marked a *wrong* claim about "ai_cost_log module" — the real table must be named), OpenRouter `prompt_tokens_details` | working |
| Data modelling: star vs wide tables for KPI snapshots (`*_kpi_snapshots` tables exist for 10 domains) | working |
| Privacy engineering: PDPL minimisation, pseudonymisation, retention in snapshots | working |
| Observability of pipelines: heartbeat/liveness for cron jobs (lesson org#255/256 already in knowledge_director's LAYER 4) | working |
| Reporting delivery: reports-as-PDF path, WhatsApp digest constraints | aware |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Measurement SQL contract | expert | **partial** — "Canonical metric dictionary" 1,180 chars unreachable; 14 live `measure_sql` bodies are the real exemplars but not knowledge | Reference record: the `measure_sql` contract + 5 annotated exemplars from `metric_definition` (fixture filter, period, null handling) → `ops_knowledge` data_intel reference (role analyst-controller) | 6 records | **P1** |
| Event instrumentation | expert | **present** ("Instrument events, not status columns", "Instrumenting the reveal payment") | Add estate fact-table map (`decision_trace`, `action_execution`, `workflow_step_run`, `agent_runs.counts`) | 1 record | P2 |
| Data quality engineering | expert | **present** (dimensions, "pipeline can lie quietly", anomaly detection) | Add 5 SQL check templates as a `remediation` record | 1 record | P2 |
| Pipeline idempotency | expert | **present** ("Idempotency and importer versioning") + memory "parser version belongs in the checksum" | Convert the memory lesson | 1 record | P3 |
| Postgres for analytics | expert | **present** generically (PostgreSQL 16 docs 5,908 chunks in `engineering` — *not in data_intel scope*; `analytics` category has textbooks not SQL) | Ingest PostgreSQL 16 chapters "Queries", "Window Functions", "Performance Tips", "Date/Time" into `kb_chunks` category `analytics` (or add `engineering` to `fn_dept_scope('data_intel')`) | ~120 pages | **P1** |
| Fixture/demo exclusion | expert | **present** ("Fixtures and demo data must be excluded by default") | none | — | P3 |
| Metric dictionary maintenance | expert | **partial** — no record describes `metric_definition` fields/targets/direction | 1 reference record | 1 record | P2 |
| Experiment plumbing | working | **present** in method (sizing, switchback); **missing** in plumbing (no assignment/exposure table documented — not measured whether one exists) | Reference: where assignments/exposures live (build if absent) | 1 record | P2 |
| Supabase specifics | working | **missing** — Supabase 98 chunks, not in data_intel scope categories | Supabase docs: pg_cron, RLS & service role, storage → `kb_chunks` `analytics` (**verify**) | ~40 pages | P2 |
| Cohort/funnel SQL | expert | **present** in method ("cohort triangle", "cohort retention for B2B RFQ") — no SQL | 2 worked SQL examples (fill-rate matrix, reveal funnel) | 2 records | **P1** |
| Cost/usage telemetry | working | **partial** — exam recorded a *wrong* table name as a gap fact | Reference naming the real cost tables and the `prompt_tokens_details` rule; quarantine the wrong fact | 1 record | P2 |
| Data modelling (snapshots) | working | **partial** — 10 `*_kpi_snapshots` tables exist, undocumented | 1 reference record | 1 record | P3 |
| Privacy engineering | working | **missing** | shared policy with intel_director | shared | P2 |
| Pipeline observability | working | **partial** — lessons in knowledge_director's LAYER 4, not this agent's | Copy as department-scoped record | 1 record | P3 |
| Off-remit pollution | — | `retrieval_policy.yaml` (lifts) in LAYER 4 | Quarantine | — | P2 |

**Reasoning gap.** Runbooks: "Remediation: an experiment came back inconclusive", "Remediation: fill rate looks fine but revenue flat", "KPI diverges between two dashboards" exist (good). Thresholds: freshness SLA record exists; no numeric alert thresholds for data quality. Decision trees: anomaly triage present. Worked examples: no SQL worked examples at all — the biggest gap for an engineer whose output contract is `measurement_path`. **P1 count: 3.**

---

## 3. `bi_analyst` — Business Intelligence Analyst

**What it does today.** Runs/7d: 10 ok (deterministic). Exam: **3/26 (12%)**, 15 wrong (3 filled), 8 partial, 0 not_covered — it answered rather than declining, and was wrong 58% of the time; confidence 0.53. Retrievals/30d: 0. Author 33/11/11. KPI: "Variance explained with a root cause" **71.13% vs 90**. Authority advisory (seeded 14 Aug "an active role with no authority record is undefined"); owns report construction and interpretation of a measured trend; forbidden: changing the measurement, stating a number it has not measured. `employee_knowledge`: **0 rows**; `v_employee_knowledge_compliance`: layers_bound 0/12, workflows 0. Role identity: data-analytics-and-intelligence-analyst-controller. Output contract: bi_report.

**Knowledge inventory.** Profession: 1 row "Reporting that survives being acted on" (560 chars, 11 Aug, unreachable). Experience 3: "Remediation: experiment inconclusive" (1,943), "Building a cohort triangle correctly" (2,316), "Customer registration… failed handoff" (179). Reachable ops_knowledge: department pool (926) incl. the 101 deep records. Exam topics: 3 compliance, 3 di_deep, 2 ops, 1 each authority/domain/pricing — the compliance/pricing questions (UAE regulator, fee ladder) are outside a BI analyst's remit and account for wrong answers.

**Senior-staff standard — senior BI analyst reporting to a founder-run marketplace.**

| Domain | Depth |
|---|---|
| Variance analysis: target vs actual decomposition (volume/mix/rate), root-cause narrative, the "disciplined interrogation before the narrative" | expert |
| Report design for decisions: one question per view, thresholds/targets on every number, citations to `metric_key`, "not yet measured" honesty | expert |
| Marketplace KPI literacy: fill rate, match rate, time-to-first-quote, reveal rate, take rate, supplier response, CLV, churn, cohort triangles | expert |
| Reading the estate's live state: `finance_kpis`, `ops_kpis`, `supplier_kpis`, `customer_kpis`, `marketing_kpis`, `knowledge_kpis`, `security_kpis`, `governance_kpis`, `strategy_kpis`, `report_kpis` views and the `*_kpi_snapshots` history | expert |
| SQL for reporting (read-only): window functions, period comparisons, WoW/MoM with small-number caution | working |
| Statistics for reporting: base rates, seasonality (Ramadan/Eid, summer, fiscal year), significance vs noise, real vs nominal (AED inflation) | working |
| Visualisation & narrative standards: dataviz conventions, tables over charts for ≤5 numbers, RTL/Arabic readiness | working |
| Founder-brief format: WhatsApp-length summaries, overnight brief, "Business pulse" cadence; brand wording ("smart engine") | expert |
| Fixture exclusion & data provenance: label demo data, lineage of each number | expert |
| Forecast reading: ranges, assumptions, run-rate vs totals | working |
| Compliance boundaries of reporting: no PII, no numbers it did not measure, no target-setting | working |
| Tooling: reports-as-PDF path (`docs/…reports-pdf` worktree), dashboard tables in the OS | aware |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Variance analysis | expert | **present** in method ("Reading a metric move", "Ratio of ratios", "Remediation: KPI diverges…") — KPI at 71% suggests the method is not applied | Worked example set: 5 real variance explanations from `employee_kpi`/`company_goals` misses (deterministic band root causes already recorded in `improvement_plan`) → `ops_knowledge` data_intel reference | 5 records | **P1** |
| Report design | expert | **partial** — profession row 560 chars unreachable; "Dashboards vs decisions" present | Promote to policy record with a report template (`bi_report` contract) | 1 record | P2 |
| Marketplace KPI literacy | expert | **present** (deep records) | none | — | P3 |
| Live-state views map | expert | **missing** — the 10 `*_kpis` views and snapshot tables are not described anywhere in knowledge | Reference record: view → columns → meaning → snapshot cadence (generate from `information_schema`) | 1 record ~4k | **P1** |
| SQL for reporting | working | **missing** in scope (see analytics row) | shared PostgreSQL chapters in `kb_chunks` `analytics` | shared | P2 |
| Statistics & seasonality | working | **partial** — "Currency and inflation… real vs nominal" present; UAE seasonality absent | Reference: UAE business calendar (Ramadan/Eid dates 2026–27 **verify**, summer slowdown, fiscal/VAT quarters) | 1 record | P2 |
| Visualisation standards | working | **missing** — 0 measured | Ingest the repo `dataviz` skill conventions (`.claude/skills/...` **verify** path) as a policy record | 1 record | P3 |
| Founder-brief format | expert | **present** in LAYER 1 (brand wording, document branding, response structure) | none | — | P3 |
| Fixture exclusion & provenance | expert | **present** | none | — | P3 |
| Forecast reading | working | **present** | none | — | P3 |
| Compliance boundaries | working | **present** (forbidden decisions) | none | — | P3 |
| Curriculum binding | — | `employee_knowledge` 0 rows; authority record seeded as placeholder | Bind data_analytics expert L1 + standard L2/L5/L8; define authority properly | 6 rows | P2 |
| Exam remit | — | compliance/pricing questions drive the 58% wrong rate | Scope the examiner remit to `bi_report` topics (mechanism fix) | — | **P1** |

**Reasoning gap.** Runbooks: none for producing a report (no `bi_report` template). Thresholds: the KPI target (90%). Decision tree: "is the variance volume, mix or rate?" not written. Worked examples: 0 real reports in knowledge. **P1 count: 3.**

---

## 4. `market_analyst` — Market Intelligence Analyst

**What it does today.** Runs/7d: 11 ok (deterministic). Exam: 5/20 (25%), 5 wrong (all 5 filled), 4 not_covered; confidence 0.39. Retrievals/30d: 4 (last 15 Aug). Author 36/12/12. KPI: "Market signals captured" **0 vs 20**. Authority advisory; `knowledge_acquire` autonomous ("owns market signal capture"); owns market/competitive assessment with sources; forbidden: acting on the intelligence, stating a competitor fact without a source. Workflow: knowledge_lifecycle (step actor). Output: market_brief.

**Knowledge inventory.** Profession: 1 row "UAE B2B market intelligence for construction and MEP supply" (728 chars, unreachable). Experience 7: 5 data_intel deep summaries (attribution, liquidity master metric, data quality dimensions, guardrails, inconclusive experiment) + `specialist_manifest.yaml` (2,913, plumbing category) + `06_CATEGORY_REMEDIATION…V3.yaml` (791) — off-remit. Probe on UAE construction market → LAYER 2c 65 chars. Keyword census: Dubai Statistics 0, DED/DET 0, RERA 0, FCSC 0, Dubai Municipality 0 in data-dept ops_knowledge; `intelligence` pack has "Competitive Intelligence — operating knowledge" (2,372 chars, template prose) and `live_data` module (12 rows, not inspected). `kb_chunks`: 356 categories are supplier trades — market *statistics* sources not found by citation sample (**not exhaustively measured**).

**Senior-staff standard — UAE market intelligence analyst for construction/MEP/services procurement.**

| Domain | Depth |
|---|---|
| UAE official statistics: Federal Competitiveness and Statistics Centre (FCSC) releases, Dubai Statistics Centre (DSC) construction/GDP series, Abu Dhabi Statistics Centre (SCAD) (**verify** portals/APIs) | expert |
| Dubai/UAE licensing & permits: Dubai DET (formerly DED) licence issuance stats, Dubai Municipality building permits, Trakhees/DDA free-zone permits, Abu Dhabi DMT (**verify** availability of open data) | expert |
| Real-estate & construction pipeline: RERA/Dubai Land Department project registrations and escrow, Dubai REST app data, developer launches, ProTenders/BNC project databases (**verify** licensing) | expert |
| Public tenders: UAE federal procurement portal, Dubai Government e-procurement (eSupply/Tejari **verify**), ADNOC/ADQ, Expo/Etihad Rail programmes | expert |
| Trade & industry data: UAE customs import statistics for materials (steel, cement, HVAC), Dubai Chamber/DCCI reports, Emirates Steel/Arkan price lists (**verify**) | working |
| Macro & policy: UAE PMI (S&P Global), central-bank rates, corporate tax 9% (2023), VAT 5%, ESR/ICV programmes (ICV certification affects supplier eligibility) | working |
| Competitor landscape: UAE B2B sourcing/RFQ platforms and directories (Tradeling, Alibaba UAE, Yellow Pages UAE, ProcureLogic-type players **verify** current set), their fee models vs the 3% reveal fee | expert |
| Signal capture method: source registry, cadence, structured `market_intel` rows, dedupe, confidence, citation rule (no fact without source) | expert |
| Supplier-market structure per category: the 86 categories, concentration, typical lead times, price drivers (from category packs) | working |
| Demand sensing from platform data: RFQ volume by category×emirate, TAM sizing bottom-up ("Category TAM sizing in the UAE" record) | expert |
| Regulatory watch: Dubai Municipality codes, Civil Defence, ESMA/MOIAT conformity marks, PDPL — as market events affecting suppliers | working |
| Seasonality & calendar: Ramadan/Eid, summer, Cityscape/Big 5/WETEX event calendar (**verify** dates) | working |
| Analysis craft: base rates, "extrapolation beyond the measured range is invention", real vs nominal AED | expert |
| Ethics/legal of collection: scraping limits (Apify paused), robots/ToS, PDPL on personal data of sole traders | working |
| Brief format: market_brief contract with sources, confidence, "so what" for supply acquisition | expert |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| UAE official statistics | expert | **missing** (0 mentions; probe returned nothing) | Source registry record (FCSC, DSC, SCAD: series names, cadence, URL, licence — **verify** each) as `ops_knowledge` data_intel `source_reference`; ingest the latest DSC construction/GDP bulletin PDFs as `kb_chunks` category `intelligence` source_kind reference with citation | 1 registry + ~60 pages | **P1** |
| Licensing & permits | expert | **missing** — Dubai Municipality 0 (data depts) | Registry entries + Dubai Municipality open-data permit series (**verify** availability) | 1 record + ~20 pages | **P1** |
| Real-estate/construction pipeline | expert | **missing** — RERA 0 in ops_knowledge; 82 kb_chunks mention RERA inside supplier packs | Registry entries (DLD/RERA open data, project-registry sources, licensed DBs if subscribed — **verify**) | 1 record | **P1** |
| Public tenders | expert | **missing** | Registry entries for federal/Dubai/Abu Dhabi tender portals with monitoring cadence (**verify** portal names) | 1 record | **P1** |
| Trade & industry data | working | **missing** | Registry entries (customs, Dubai Chamber) | 1 record | P2 |
| Macro & policy | working | **missing** (corporate tax/VAT appear in finance scope, not here) | 1 reference record (rates, dates, ICV) (**verify**) | 1 record | P2 |
| Competitor landscape | expert | **missing** — "Competitive and reference pricing intelligence without scraping" (method) present; no competitor set | Competitor register (name, model, fee, category coverage, source, date) as `ops_knowledge` reference, refreshed monthly (**verify** each) | 1 record | **P1** |
| Signal capture method | expert | **partial** — KPI 0/20; `market_intel` target table exists per role description (not inspected); "Handing an insight to another department" present | SOP record: what a signal row is, required fields, cadence, dedupe | 1 record | **P1** |
| Supplier-market structure | working | **present** in category packs (1,204 category-scoped ops_knowledge rows; 356 kb categories) — reachable only via unscoped kb_search | none beyond scoping fix | — | P3 |
| Demand sensing from platform | expert | **present** ("Category TAM sizing… from RFQ demand", liquidity matrix) | Worked SQL example (RFQ volume by category×emirate) | 1 record | P2 |
| Regulatory watch | working | **partial** — UAE authorities appear in category packs; no watch list | 1 record (authorities + what to watch) (**verify**) | 1 record | P3 |
| Seasonality & events | working | **missing** | 1 reference record (calendar **verify**) | 1 record | P2 |
| Analysis craft | expert | **present** (extrapolation, base rates, correlation records) | none | — | P3 |
| Ethics/legal of collection | working | **partial** — "without scraping" record; Apify pause in memory | 1 policy record | 1 record | P3 |
| Brief format | expert | **missing** — no `market_brief` template | 1 template record | 1 record | P2 |
| Off-remit pollution | — | 2 category-pack yaml rows in LAYER 4 | Quarantine | — | P2 |

**Reasoning gap.** No source registry, so every market claim would today come from the model's memory — exactly what the forbidden-decision "stating a competitor fact without a source" prohibits. Runbooks: none. Thresholds: signal KPI 20/month only. Decision tree: none. Worked examples: none. **P1 count: 6.**

---

## 5. `supplier_analyst` — Supplier Intelligence Analyst

**What it does today.** Runs/7d: 10 ok (deterministic). Exam: 6/20 (30%), 8 wrong (7 filled), 6 not_covered, 0 partial; confidence 0.38. Retrievals/30d: 0. Author 33/11/11. KPI: "Supplier scoring coverage" **0.01% vs 95**. Workflows: **none** (0 `employee_workflow` rows). Authority advisory; owns supplier reliability/risk/price/response scoring, CLV/churn, manufacturer/brand intelligence; forbidden: confirming or suspending a supplier, setting price, acting on its own score. Role identities: data-analytics-and-intelligence-analyst-controller + supplier-knowledge-analyst-controller. Outputs: supplier_intelligence, customer_intelligence.

**Knowledge inventory.** Profession: 1 row "Reading supplier quality from platform behaviour" (805 chars, unreachable). Experience 10: 6 deep summaries (statistical power/MDE, extrapolation, segmentation, experiment roadmap, reading a metric move, competitive pricing without scraping) + "How the Marketplace Works, End to End" (1,504, company) + 3 category-pack items (`01_SPECIALIST_EXPERTISE_V2.md` tender consultants, `02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml`, `specialist_manifest.yaml`). Scoring model constants exist in `decision_policy` (`score_w_brand`, `score_w_product`, `score_w_project_type`, `score_w_size_fit`, `score_w_track_record`, `match_relevance_floor`, `matching_strike_limit`, `use_capability_matching`) — not described in any knowledge record (not measured whether a record cites them). Platform reality: 15,306 capability rows, 1 confirmed supplier, 81 invited / 0 registered (memory), `verified_suppliers` metric = 1 vs 2,000, `supplier_response_rate` 1.0 vs 60.

**Senior-staff standard — supplier & customer intelligence analyst for a UAE RFQ marketplace.**

| Domain | Depth |
|---|---|
| Supplier scoring model: reliability (response time, quote completeness, 70/100 gate pass rate), risk (licence validity, ICV, insurance), price position, quality (post-reveal outcomes, ratings timing rule) — weights in `decision_policy`, inputs, cold-start handling | expert |
| Supplier verification data: UAE trade licence (DET/free-zone), VAT TRN, ICV certificate, ISO certs, Civil Defence approvals, DEWA/SEWA/FEWA approved-contractor lists (**verify** lookup routes) | expert |
| Supplier funnel analytics: invited→registered→confirmed→responding; non-response 3% rule; strike limit | expert |
| Customer intelligence: CLV for buyers posting in bursts, churn risk, repeat-RFQ propensity, segmentation (B2B RFQ segments record) | expert |
| Matching quality measurement: precision/recall on match samples, revealed outcomes as labels, confidence calibration ("you cannot cascade what you barely score") | expert |
| Manufacturer/brand intelligence per category: brand tiers, authorised distributors in UAE, counterfeit risk | working |
| Pricing intelligence: reference prices without scraping, price-ladder reasoning, dynamic-pricing risks | working |
| Statistics: small-sample scoring (Bayesian shrinkage/priors for new suppliers), MDE/power for supplier experiments | working |
| Data sources: platform tables (`supplier_kpis`, capability rows, quotes, reveals, ratings), external registries (**verify**) | expert |
| PDPL for supplier personal data (sole traders' phone/email), retention | working |
| Anti-circumvention & fraud signals (AED 15k / 3× rule, duplicate identities, phone-may-confirm-never-select) | working |
| Reporting contracts: supplier_intelligence / customer_intelligence outputs, handoff to supplier_success (confirm/suspend is theirs) | expert |
| Category taxonomy: 86 categories, aliases, subcategory review (`mep_subcategory_review`) | working |
| Experiment design for supply-side interventions (invite copy, onboarding) under thin traffic | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Supplier scoring model | expert | **partial** — weights in `decision_policy`; method record 805 chars unreachable; coverage 0.01% | Reference record: the model (inputs, weights, cold-start prior, refresh cadence, where scores are written) + worked example on the 1 confirmed supplier → `ops_knowledge` data_intel kpi/decision_playbook (role supplier-knowledge-analyst-controller) | 3 records | **P1** |
| Supplier verification data | expert | **partial** — category packs mention authorities; no verification-source registry | Registry record: licence/TRN/ICV/Civil Defence/utility-approval lookup routes (**verify**) | 1 record | **P1** |
| Supplier funnel analytics | expert | **partial** — "Supplier funnel: 81 invited, 0 registered" and confirmation-screen lesson in memory only | Convert memory lessons + a funnel SQL worked example | 2 records | **P1** |
| Customer intelligence | expert | **present** (segmentation, cohort retention for buyers posting in bursts) | Add CLV formula record with the reveal-fee economics | 1 record | P2 |
| Matching quality measurement | expert | **present** ("Auditing a match sample by hand", "Closing the matching feedback loop", "Confidence on matches") | none | — | P3 |
| Brand/manufacturer intelligence | working | **present** in category packs (14-module standard includes "Brands & Manufacturers") — unscoped | none beyond scoping fix | — | P3 |
| Pricing intelligence | working | **present** | none | — | P3 |
| Small-sample statistics | working | **partial** — power/MDE present; shrinkage/priors absent (Gelman BDA in kb_chunks `analytics`, unscoped) | 1 reference record (empirical-Bayes shrinkage for supplier scores with n<5) | 1 record | P2 |
| Data sources map | expert | **missing** — no record maps supplier tables/views | Reference: `supplier_kpis` view, capability rows, quotes/reveals/ratings tables | 1 record | **P1** |
| PDPL for supplier data | working | **missing** | shared policy | shared | P2 |
| Anti-circumvention/fraud | working | **partial** — T&C rules in memory/LAYER 1 pricing; no detection queries | 1 record | 1 record | P3 |
| Reporting contracts & handoff | expert | **missing** — 0 workflows bound; outputs undefined as templates | Bind `employee_workflow` (supplier onboarding/verification workflow as participant); 2 template records | 2 records + rows | P2 |
| Category taxonomy | working | **present** (knowledge pack "Supplier Taxonomy — operating knowledge", `kb_category_aliases`) | none | — | P3 |
| Supply-side experiments | working | **present** (thin-traffic roadmap) | none | — | P3 |
| Off-remit pollution | — | 3 category-pack rows (tender consultants) in LAYER 4 | Quarantine | — | P2 |

**Reasoning gap.** The scoring model is the role's core decision and exists only as 5 numeric weights; no runbook for scoring a new supplier, no threshold table (what score blocks a match), no worked example. **P1 count: 4.**

---

## 6. `knowledge_director` — Knowledge Director

**What it does today.** Runs/7d: 11 ok (deterministic). Exam: 6/20 (30%), 6 wrong (all 6 filled), 6 not_covered; confidence 0.38. Retrievals/30d: 1. Reviewer: 39 approve / 22 owned / 2 request_revision; author 156 approve / 54 owned / 2 revision / 54 undecided (the most review activity in the department). KPIs: "Knowledge validated" **29.8% vs 80**; "Knowledge quarantined" 0% (max 5); "Retrieval corpus freshness" 99.89% vs 60. Authority `execute_low`; `knowledge_acquire`/`knowledge_fill` autonomous; owns corpus structure/scope, what counts as validated, freshness policy; forbidden: validating a lesson it proposed, changing the taxonomy, deleting without provenance. Role identities: knowledge-engineering-and-corporate-learning-director/operations-specialist/analyst-controller (81 role-keyed `knowledge_eng` rows). Workflows: improvement_lifecycle, incident_response, knowledge_lifecycle (step actor). Responsibilities text: "coverage across all 86 categories, the 14 required modules per expert, source citation, validation status, confidence decay and quarantine."

**Knowledge inventory.** Profession: 1 row "Owning the knowledge lifecycle" (708 chars, unreachable). Experience 16: 6 deep summaries (instrument events, price ladder, ratio of ratios, network interference, denominator, Goodhart), `02_FIELD_AND_QUESTION_BANK_V2.yaml` (2,561), MEP `qualification_playbook.md` (2,601), `specialist_manifest.yaml` (4,000) — category-pack items (arguably in remit as *corpus samples*, but they are not knowledge-management knowledge), and 7 org lessons incl. the useful "Instrument knowledge pipeline jobs with heartbeat/liveness" and "kb_embed stalls". The estate's own KM tables (`knowledge_domain` 86+ rows, `knowledge_module_standard` 14 modules, `employee_knowledge_standard` 12 layers, `kb_category_stats`, `kb_revisions`, `knowledge_ingestion_run/undo`, `v_kb_coverage`, `v_kb_review_due`, `v_kb_confidence`, `v_kb_risk`, `v_knowledge_compliance`) exist; no knowledge record describes them. `docs/expertise/*.md` (7 files) and `docs/knowledge/V3_*` reports document the pipeline in the repo only.

**Senior-staff standard — head of knowledge management for an AI-employee company.**

| Domain | Depth |
|---|---|
| The retrieval architecture end to end: `fn_agent_context` layers and budgets (LAYER 2 empty; 2b–2g), `fn_agent_context_v3`, `fn_ops_knowledge_match` scoping (`fn_dept_scope`, packaged roles), `kb_search` hybrid, `kb_embed` (gte-small, edge-only, 5–8 rows/batch), `agent_context_retrieval` log | expert |
| Corpus model: `kb_chunks` (category/source_kind/citation/effective_date), `ops_knowledge` (scope_type/dept_key/role_key/layer/module/record_type/authority_tier/validation_status/source_freshness/review_after/supersession), `agent_knowledge` (profession/experience/_global priority), `dept_library`, `company_faq` | expert |
| Ingest routes and tooling: `scripts/kb/ingest_extracted.mjs`, book-to-skill extraction, `knowledge_ingestion_run`/`undo`, checksum/parser-version idempotency, MANIFEST for SQL-borne knowledge | expert |
| Validation pipeline: author_verified→reviewed→source_verified→validated, quarantine rules, the exam loop (question sourcing, grading, fill) and its failure modes | expert |
| Taxonomy governance: 86 categories × 14 modules (`knowledge_module_standard` min_chars/priority), `kb_category_aliases`, `kb_operational_route*`, category coverage KPIs | expert |
| Freshness & decay: `review_after`, `source_freshness`, `valid_until`, confidence decay, `v_kb_review_due`; UAE regulation change cadence | expert |
| Chunking & citation quality: chunk size (~1,200 chars), boilerplate stripping (NIST click-steps, reference lists), dedupe (6× repeated chunk observed), citation completeness, `NULL source_id` rule | expert |
| Retrieval quality measurement: recall@k on held-out questions, exam coverage (1.85%), on-remit sampling, `kb_usage_log` analysis | expert |
| Knowledge-management practice standards: ISO 30401:2018 KMS (**verify**), DAMA-DMBOK data governance chapters (present), Wikipedia-style provenance norms | working |
| Copyright & licensing of ingested material (textbooks, standards bodies, arXiv CC licences), PDPL for personal data inside documents | working |
| Embedding/semantic search fundamentals: gte-small limits, cosine vs full-text, HNSW `ef_search`, hybrid RRF | working |
| Curriculum design: `employee_knowledge_standard` 12 layers, per-role certification map (`ROLE_CERTIFICATION_MAP.csv`), `skills_matrix` evidence rules | expert |
| Learning loop: `agent_train`, lessons-learned capture (`os_runbooks lesson-N`, `agent_memory`), promotion of a lesson to policy | expert |
| Cost of knowledge: zero-cost embedding path, paid exam cost, "10,000 pages per agent" target arithmetic | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Retrieval architecture | expert | **missing** in tables — the director of knowledge has no record of how knowledge reaches an agent; this audit's §0 defects are unknown to it | Ingest `docs/expertise/AGENT_KNOWLEDGE_PATH.md`, `CORPUS_INGESTION.md`, `SEMANTIC_RETRIEVAL_STATE.md`, `docs/knowledge/V3_RUNTIME_CONNECTION_REPORT.md` + audit §0 as `ops_knowledge` data_intel reference (role knowledge-engineering director) | 8 records | **P1** |
| Corpus model | expert | **missing** — table/column semantics undocumented as knowledge | Reference record per table (generate from `information_schema` + this audit) | 5 records | **P1** |
| Ingest routes | expert | **partial** — `CORPUS_INGESTION.md` in repo; `knowledge_ingestion_run` exists | SOP record with the loader command, category rule (must be in `fn_dept_scope`), citation rule | 1 record | **P1** |
| Validation pipeline & exam loop | expert | **missing** — KPI 29.8% validated; the loop's pollution (53 wrong facts filled company-wide in scope) is not known | Policy record: validation states, who may validate, quarantine triggers (off-remit source, wrong-verdict fill), exam remit scoping | 2 records | **P1** |
| Taxonomy governance | expert | **present** — 86 categories, 14-module standard, aliases, route maps in tables; `intel_director` KPI "categories with all eight modules 2%" | Reference tying `knowledge_module_standard` to `v_kb_coverage` with the current coverage numbers | 1 record | P2 |
| Freshness & decay | expert | **partial** — "Knowledge Decay — how the department uses it" (template prose); `review_after` on 779/1,852 in-scope rows; freshness KPI 99.89% measures corpus age, not truth | Policy: review cadence per source_type (regulation 90 d, platform docs 180 d, textbooks none), decay rule, `valid_until` use | 1 record | P2 |
| Chunking & citation quality | expert | **missing** — observed defects (211-char click-steps, 6× duplicate chunk, reference-list chunks) have no rule | Chunk QA policy + a `remediation` for re-chunking; dedupe SQL (md5 with `source_id` not null rule) | 2 records | **P1** |
| Retrieval quality measurement | expert | **partial** — `v_kb_confidence`, `v_kb_citation_check` views exist; no recall@k method record | Method record: held-out question set per role, recall@k, on-remit sampling | 1 record | P2 |
| KM practice standards | working | **partial** — DAMA-DMBOK present in kb_chunks `analytics` (unscoped) | ISO 30401 summary (**verify** licence — standard text is paid; ingest a public overview) → `kb_chunks` `knowledge_eng` | ~10 pages | P3 |
| Copyright & licensing | working | **missing** | Policy record: what may be ingested (open licences, purchased standards, arXiv CC-BY) and citation format | 1 record | P2 |
| Embedding/semantic fundamentals | working | **partial** — `SEMANTIC_RETRIEVAL_STATE.md` in repo; "embedding" 44 mentions in data-dept ops_knowledge | Reference (gte-small dims/limits, hybrid RRF, HNSW params) | 1 record | P3 |
| Curriculum design | expert | **present** in tables (`employee_knowledge_standard`, `ROLE_CERTIFICATION_MAP.csv` in repo) — 13/13 in-scope agents `INCOMPLETE` (0–5 of 12 layers bound) | Reference record + the compliance numbers | 1 record | P2 |
| Learning loop | expert | **partial** — `agent_train`, lesson-N runbooks, `agent_memory` exist; no promotion rule | SOP: lesson → reviewed → policy promotion, with the "validating a lesson it proposed" prohibition | 1 record | P2 |
| Cost of knowledge | working | **partial** — zero-cost path documented in repo | 1 record | 1 record | P3 |
| Off-remit pollution | — | 3 category-pack rows (MEP playbook, question bank, manifest 4,000 chars) in LAYER 4 | Quarantine or re-tag as *corpus samples* with a note | — | P2 |

**Reasoning gap.** Runbooks: "kb_embed stalls" lesson exists; no runbook for "corpus quality incident" or "validation backlog". Thresholds: KPI targets only (validated 80%, quarantined ≤5%). Decision tree: "validate / quarantine / supersede" not written. Worked examples: none of a validation decision. **P1 count: 5.**

---

## 7. `process_improvement_mgr` — Process Improvement Manager

**What it does today.** Runs/7d: 9 ok (deterministic). Exam: 6/20 (30%), 7 wrong (6 filled), 5 not_covered; confidence 0.41. Retrievals/30d: 0. Author 30/10/10. KPI: primary objective 100% (target 95). Authority `execute_low`, budget AED 1,000; `capability_exam`/`qa_gate` autonomous; `knowledge_acquire/fill/fill_gap` advisory; owns process-defect diagnosis and improvement proposals with a named metric; forbidden: grading its own improvement, changing another department's method without its head. Tools: capability_exam, capability_review, idea_submit, knowledge_acquire, knowledge_fill, knowledge_fill_gap, qa_gate, role_define, self_review. Workflows: employee_task (owner), rfq_handling (participant). Role identity: administration-and-operations-analyst-controller (the only in-scope holder of an administration-and-operations role → 26 role-keyed `knowledge` rows reachable). `employee_knowledge`: operations expert L1; `skills_matrix` Operations & Quality 4, Software Engineering 2.

**Knowledge inventory.** Profession: 1 row "Improving processes that are written as workflows" (714 chars, unreachable). Experience 9: 6 deep summaries (matching drift, KPI diverges between dashboards, experiment metric choice, data quality dimensions, choosing what to measure, procurement opportunities [bizdev pack]) + `qualification_playbook.md` (security companies, 2,228), `rfq_quality_gate.yaml` (753), `source_route_manifest.json` (4,000) — off-remit. Keyword census: Six Sigma 0, Lean 45 (word match, not verified as methodology), "cycle time" not measured. The estate's process fabric it must improve: `workflow_step` (actor_role/action_class/gate), `employee_workflow`, `workflow_run`, 21 kernel boards (`fn_kernel_all_boards`), org_task lanes, `decision_trace` — none described in knowledge.

**Senior-staff standard — process improvement (Lean/Six Sigma) manager for a workflow-kernel-driven company.**

| Domain | Depth |
|---|---|
| Lean fundamentals: value-stream mapping, the 8 wastes, flow/pull, takt, WIP limits (`max_open_tasks` 50, `dispatch_max_open_per_dept`) | expert |
| Six Sigma DMAIC: define/measure/analyse/improve/control with a named metric and a control chart; MSA (is the meter trustworthy — "monitor the meters"), SPC basics, capability | expert |
| Process mining on this estate: `workflow_step_run` timestamps → cycle time per step, queue time, rework loops (`request_revision`), stalled handoffs ("Stalled handoff run #80… 431h past SLA" alert) | expert |
| The kernel's process model: workflow_key/step_no/actor_role/gate, ownership in `workflow_step`, handoff acceptance ("no open step means a handoff is unaccepted"), org_task lanes | expert |
| Cycle-time metrics for the RFQ funnel: post→match→first quote→reveal; time-to-first-quote median (the 70/100 gate) | expert |
| Root-cause tools: 5 whys, fishbone, Pareto — applied with the estate's lesson corpus (e.g. "guarded by a condition that cannot occur") | expert |
| Improvement proposal contract: `improvement_proposed` event/lane, `improvement_lifecycle` workflow, evolution proposals (48 pending), named metric + baseline + target + control | expert |
| Experiment design for process changes (switchback under thin traffic; the data_intel records) | working |
| Change management: who owns a method (department head), `role_define` tool limits, the phase-baseline discipline | working |
| Standard work / SOP authoring: `ops_knowledge` sop records, templates module, checklists | expert |
| Service-level design: SLAs per step (`due_at`, escalation), error budgets shared with SRE | working |
| Cost of quality: rework counts, failed runs, avoidable AI spend (39.8%) | working |
| Theory of constraints: the one-confirmed-supplier bottleneck as the current constraint | expert |
| Lean Six Sigma body of knowledge reference (ASQ CSSBB BoK **verify**) | working |
| Capability exams/QA gates it may run: what `capability_exam` and `qa_gate` do (not measured) | working |

**Gap table.**

| Domain | Depth | Today | What to ingest (route) | Size | Priority |
|---|---|---|---|---|---|
| Lean fundamentals | expert | **missing** (0 methodology records; "Lean" 45 word hits unverified) | Open Lean primer (e.g. Lean Enterprise Institute basics **verify** licence) or authored summary → `kb_chunks` `data_intel`/`intelligence` + 1 policy record mapping wastes to estate queues | ~40 pages + 1 record | P2 |
| DMAIC / SPC / MSA | expert | **missing** (Six Sigma 0) | ASQ CSSBB BoK outline (**verify**) + authored DMAIC template record with a control-chart SQL | ~30 pages + 2 records | **P1** |
| Process mining on the estate | expert | **missing** — no record of `workflow_step_run` cycle-time queries; the stalled-handoff alert has no owner playbook | Reference: cycle-time/queue-time SQL per workflow step; stalled-handoff remediation | 3 records | **P1** |
| Kernel process model | expert | **partial** — "ownership lives in workflow_step", "no open step means unaccepted", "a merge that collapses a handoff" in memory only | Convert 6 kernel-process lessons → `ops_knowledge` data_intel reference/failure_mode | 6 records | **P1** |
| RFQ funnel cycle-time metrics | expert | **partial** — deep records define liquidity/fill rate; time-to-first-quote definition appears only as an exam gap fact | shared with intel_director metric rows | shared | P2 |
| Root-cause tools | expert | **partial** — `improvement_plan` text carries "Root cause (deterministic band)" for KPI misses; no method record | 1 method record + 3 worked examples from real KPI misses | 4 records | P2 |
| Improvement proposal contract | expert | **present** — `improvement.proposed` lane playbook (2,376 chars) | Add template with baseline/target/control fields | 1 record | P2 |
| Process experiments | working | **present** (switchback, thin-traffic roadmap) | none | — | P3 |
| Change management | working | **present** in forbidden decisions; phase baseline lessons in memory | 1 record | 1 record | P3 |
| SOP authoring | expert | **present** — `sop` module rows (intelligence 10, knowledge 20, it 32) as exemplars | none | — | P3 |
| SLA design | working | **partial** — `due_at`/escalation fields; SLA values not a record | 1 record | 1 record | P2 |
| Cost of quality | working | **partial** — metrics exist (`avoidable_ai_pct`, `failed_runs_24h`) | 1 kpi record | 1 record | P3 |
| Theory of constraints | expert | **partial** — "one confirmed supplier gates every RFQ" in memory | 1 record | 1 record | P2 |
| Capability exams / qa_gate tools | working | **not measured** what these tools do | Reference record once measured | 1 record | P3 |
| Off-remit pollution | — | 3 category-pack rows (4,000-char manifest) in LAYER 4 | Quarantine | — | P2 |

**Reasoning gap.** Runbooks: none for a process diagnosis. Thresholds: none (no cycle-time targets). Decision tree: none. Worked examples: none — despite the estate having the richest process-defect corpus in the company (the ~200 session lessons). **P1 count: 3.**

---

## Department summary — data_intel

| Agent | Exam (correct/n) | Runs/7d ok | Retrievals/30d | KPI status | P1 | P2 | P3 |
|---|---|---|---|---|---|---|---|
| intel_director | 6/20 (30%) | 9 | 16 | 5 of 6 missed | 4 | 6 | 6 |
| analytics | 7/29 (24%) | 10 | 6 | met | 3 | 8 | 4 |
| bi_analyst | 3/26 (12%) | 10 | 0 | 71% vs 90 | 3 | 4 | 6 |
| market_analyst | 5/20 (25%) | 11 | 4 | 0 vs 20 signals | 6 | 6 | 4 |
| supplier_analyst | 6/20 (30%) | 10 | 0 | 0.01% vs 95 | 4 | 5 | 6 |
| knowledge_director | 6/20 (30%) | 11 | 1 | 29.8% vs 80 validated | 5 | 7 | 3 |
| process_improvement_mgr | 6/20 (30%) | 9 | 0 | met | 3 | 7 | 5 |
| **Total** | 39/155 (25%) | 70 | 27 | | **28** | **43** | **34** |

**Top 5 ingest items (prerequisite: the §0 delivery fixes — LAYER 2 budget, `dept_library` seeding for data_intel, `field_corpus` emission or scoped `kb_search`, exam remit scoping and no fill on `wrong`):**

1. **UAE market source registry** (market_analyst P1 ×5): FCSC, Dubai Statistics Centre, SCAD, Dubai DET licence stats, Dubai Municipality permits, DLD/RERA, federal/Dubai/Abu Dhabi tender portals, competitor register — one `ops_knowledge` `source_reference` record per source with cadence/licence (**verify** every portal), plus the latest DSC/FCSC construction bulletins as `kb_chunks` category `intelligence`. Nothing of this exists today (0 mentions; probe returned 65 chars).
2. **Department-owned metric definitions with worked SQL** (intel_director, analytics, bi_analyst): 8 `metric_definition` rows owned by data_intel (fill rate by category×emirate, match rate, time-to-first-quote, quotes/RFQ, reveal rate, take rate, repeat-buyer) + annotated `measure_sql` exemplars, the fixture filter, and a map of the 10 `*_kpis` views/snapshot tables. The 101 deep records explain *why*; nothing shows *how* on this schema.
3. **Estate self-knowledge for the knowledge director**: the retrieval architecture (`docs/expertise/*.md`, V3 runtime report, this audit's §0), corpus tables, ingest SOP, validation/quarantine policy incl. exam-loop rules, chunk-QA policy — ~15 records. Today the role that owns "what counts as validated" has 44 validated records in a 926-record reachable pool and does not know LAYER 2 is empty.
4. **Supplier scoring model + verification registry** (supplier_analyst): the `decision_policy score_w_*` model written up with inputs, cold-start prior, thresholds and a worked example; UAE licence/TRN/ICV/Civil Defence lookup routes (**verify**); funnel SQL. Coverage KPI is 0.01%.
5. **Process-mining and DMAIC pack** (process_improvement_mgr, shared with intel_director): cycle-time/queue-time SQL over `workflow_step_run`, stalled-handoff remediation, the 6 kernel-process lessons from memory, a DMAIC/control-chart template — plus quarantine of the 12 off-remit category-pack rows currently in these seven agents' LAYER 4.

External-standard ingests (Kohavi et al. experimentation, Lean/Six Sigma BoK, ISO 30401, PostgreSQL analytics chapters, Supabase docs) are P2/P3 and must go to `kb_chunks` categories inside `fn_dept_scope('data_intel')` (`analytics`, `intelligence`, `data_intel`, `knowledge_eng`) with real citations — or `engineering` must be added to the department scope — otherwise they join the 2.69M chunks that only surface through the unscoped 8-hit `kb_search`.
