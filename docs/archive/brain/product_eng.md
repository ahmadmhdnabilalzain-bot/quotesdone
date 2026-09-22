# Company brain — `product_eng`

**Written 7 September 2026. Every number below was read from production project `htdblwldjkcgjvmqkbeh`
between 08:02 and 08:35 UTC on that day.** Nothing here has been applied. This is a plan for the founder
to approve.

**The founder's constraint, stated twice: no position may depend on a language model at run time.**
Every resolver in this document is a table read, an arithmetic step, a threshold comparison, or a template
fill. Free in-region `gte-small` embedding (via `kb_embed`) is used only for *retrieval* — finding the
right stored row — never for generating an answer. Section 9 of each seat is the honest list of what that
buys us nothing on.

---

## The department as measured

`select agent_key, title from public.org_agents where active and department = 'product_eng'` returns
**six** rows (of fifteen; nine are parked with a recorded `unavailable_reason`):

| agent_key | title | seniority | routing_tier | manager |
|---|---|---|---|---|
| `cto` | Chief Product & Technology Officer | director | director | ceo |
| `it` | IT Operations & Site Reliability Engineer | specialist | director | cto |
| `security` | Cybersecurity Engineer | specialist | director | cto |
| `backend_engineer` | Backend Engineer | specialist | analyst_controller | cto |
| `qa_manager` | QA & Release Management Director | specialist | reviewer_auditor | cto |
| `red_view_alerter` | Red-view Alerter | specialist | operations_specialist | cto |

Parked (title kept for re-hire, accountability moved to `cto`): `ai_architect`, `eng_manager`,
`frontend_engineer`, and six others.

### The estate these six seats operate, measured 7 Sep 2026

| Thing | Count | Source |
|---|---|---|
| Base tables in `public` | 628 | `information_schema.tables` |
| Views in `public` | 214 | `information_schema.views` |
| Routines in `public` | 1387 | `pg_proc` |
| …of which `SECURITY DEFINER` | 904 | `pg_proc.prosecdef` |
| Tables with RLS **enabled** | 628 of 628 | `pg_class.relrowsecurity` |
| RLS **policies** in `public` | 17 | `pg_policies` |
| → tables RLS-on with **zero** policies | **611** | derived |
| Non-internal triggers | 416 | `pg_trigger` |
| Indexes in `public` | 1141 | `pg_indexes` |
| `cron.job` rows / active | 235 / 134 | `cron.job` |
| Edge function directories in repo | 206 | `supabase/functions/` |
| `phase_c_component` rows | 1870 | 1007 db fn · 232 cron · 204 edge · 176 trigger · 108 event sub · 100 state table · 24 route · 19 workflow |
| `kernel_routine_ownership` rows | 1216 | 617 `QUOTESDONE_APPLICATION/R4`, 335 `HISTORICAL_APPLICATION/R5`, 218 extension, 38 Supabase, 6 platform, 2 justified-untracked |
| `scripts/sql/*.sql` files | 1398 | repo |
| Files in `scripts/checks/` | 110 | repo |
| `phase_d_gate_contract` rows | 32 | `GATE-001` … |
| `action_class_gate` rows | 90 | |
| `ops_knowledge` rows | 9140, **all 9140 carry a `gte` embedding** | `embedding_status='embedded'` |
| `agent_knowledge` rows | 2556 total; `it` 35, `security` 13, `cto` 8, `qa_manager` 8, `backend_engineer` 7, `red_view_alerter` 6 |
| Server | PostgreSQL 17.6 on aarch64 | `version()` |
| Extensions | `pg_cron 1.6.4`, `pg_net 0.20.3`, `pg_stat_statements 1.11`, `pg_trgm 1.6`, `pgcrypto 1.3`, `plpgsql`, `supabase_vault 0.3.1`, `uuid-ossp 1.1`, `vector 0.8.0` | `pg_extension` |
| Largest tables | `kb_chunks` 2,681,290 · `edge_health_probe` 60,562 · `phase_c_trace` 57,612 · `phase_c_system_execution` 56,526 · `agent_runs` 40,381 | `pg_stat_user_tables` |

### The business these six seats serve, measured 7 Sep 2026

This is the fact that shapes every one-year plan in this document, so it is stated once, plainly:

| Table | Rows |
|---|---|
| `inquiries` | **0** (all time, and 0 in the last 30 days) |
| `transactions` | **0** |
| `transactions` with `revealed_at` not null | **0** |
| `quotes` / `quote_items` / `reveal_invoices` | 0 / 0 / 0 |
| `refunds` | 0 |
| `customers` | 1 |
| `supplier_catalog` | 0 |
| `leads` | 22,265, of which `verified` = **1** |
| `stripe_events` | 4 |
| Reveal revenue, all time | **AED 0** |

The revenue target (`company_goals.revenue_annual`) is **AED 1,000,000**, owned by `finance`, not by this
department. `product_eng` owns ten goals, five of which have a `measure_sql` and five of which carry
`no_measure_reason = 'NO INSTRUMENT EXISTS'` (see each seat's section 8).

### Reliability as measured, 30 days to 7 Sep 2026

| Signal | Measurement |
|---|---|
| `health_checks` kind `http` | 1064 of 1064 ok; mean latency **393 ms** against a 400 ms goal — 1.75% of headroom |
| `agent_runs` | ok 21,556 · error 681 · skipped 307 · info 17 · warn 2 → **96.98%** non-error over 30d; the 7-day KPI reads 98.23% against a 97% target |
| `edge_health_probe` | `ALIVE` 27,922 across 32 functions; `STALE` 1,833 across 23 functions |
| `qa_results` | 288 rows; latest 7 Sep 03:37 UTC, **15 of 15** passing |
| `doc_backups` (90d) | 167 `done`, 26 `error` = **86.5%** against a 100% goal; last error 15 Jul 2026 |
| Failed cron runs (7d) | `action_invoke_rpc_5min` 4 · `red_view_alert_15min` 3 · `agent_action_work_sweep_hourly` 1 · `cos_execute_hourly` 1 · `learning_loop_sweep_hourly` 1 |
| `security_events` | `anon_exposure_drift` high ×50 (last 6 Sep 14:31) · `backup_overdue` high ×5 (last 7 Sep 08:00) · `admin_login` info ×15 · `memory_lint_block` low ×2 · `override_spike` medium ×1 |
| `error_events` | `smoke/integrity_violation` high ×1034 (last 6 Sep 09:00, `email_backlog_stuck`) · `resend_webhook/hard_bounce` ×10 · `ops_watch/watchdog_silent` **critical** ×1 (2 Sep) |
| `os_incidents` | 61 rows |
| AI spend (30d) | AED 154.22 over 2,954 logged calls; **all four task classes in the last 7 days recorded AED 0.00** (`knowledge_research` 374, `agent_reasoning` 13, `rfq_routing` 10, `category_classification` 5) — the estate is already running at zero paid inference |

### Certifications held and exams sat (`public.role_certification`, `public.certification_exam_result`)

`role_certification` holds 105 rows across 54 agents; eleven of them belong to this department.

| Seat | Certification | Pass mark | Exam sat? |
|---|---|---|---|
| `cto` | AWS Certified Solutions Architect – Professional (rank 1) | 75.00 | **does not exist** |
| `cto` | TOGAF 9 Certified (rank 2) | 60.00 | **does not exist** |
| `backend_engineer` | AWS Certified Developer – Associate (rank 1) | 72.00 | **does not exist** |
| `backend_engineer` | EDB PostgreSQL 12+ Professional (rank 2) | 70.00 | **does not exist** |
| `it` | CompTIA Linux+ (rank 1) | 80.00 | **does not exist** |
| `it` | Google Professional Cloud DevOps Engineer (rank 2) | 70.00 | **does not exist** |
| `security` | CISSP (rank 1) | 70.00 | **sat twice, failed twice** |
| `security` | CEH (rank 2) | 70.00 | **does not exist** |
| `qa_manager` | ISTQB Advanced Level Test Manager (rank 1) | 65.00 | **does not exist** |
| `qa_manager` | ITIL 4 Foundation (rank 2) | 65.00 | **does not exist** |
| `red_view_alerter` | ITIL 4 Foundation (rank 1) | 65.00 | **does not exist** |

The only exam results in this department, both on 7 Sep 2026:

- CISSP, `method='semantic'`, 07:46 UTC — **27.50%**. Zero of five in *Domain 3: Security Architecture
  and Engineering* and zero of five in *Domain 6: Security Assessment and Testing*.
- CISSP, `method='lexical'`, 07:55 UTC — **42.50%**. One of five in *Domain 5: Identity and Access
  Management* and one of five in *Domain 6: Security Assessment and Testing*.

*Domain 6 was the worst area in both runs.* Five of the six seats have never sat their exam at all.

### The architecture every seat below implements

1. **Match.** An incoming question is scored against this seat's stored question types by
   `to_tsvector`/`pg_trgm` lexical overlap **plus** cosine distance on `embedding_gte` (free, in-region,
   `vector 0.8.0`). Both signals must clear their floor; a lexical-only or embedding-only match is a
   refusal, because a nearest neighbour is always found.
2. **Resolve.** A coded procedure per type: gather named rows, run the arithmetic, apply the thresholds,
   rank, compute the flip condition (the smallest input change that reverses the verdict).
3. **Compose.** A `format()` template with computed slots and cited `record_id`s. It reads like a memo
   because its skeleton is one.
4. **Refuse or escalate.** No match, stale evidence, or a boundary touched → "cannot answer, here is what
   I need, here is the `org_tasks` row I opened", routed by `fn_founder_mail_route` under
   `founder_mail_policy`. **Nothing in this department may email the founder except an approved kind.**

---

## cto — Chief Product & Technology Officer

Owns technical strategy, architecture decisions and engineering delivery. `routing_tier=director`,
`manager_key=ceo`, `max_open_tasks=50`. Holds the only `autonomous` grants in the department at
`threshold_aed=100000` for `code_selfheal`, `health_report`, `incident_fix`, `security_review` and
`uptime_verify`; `recommend` is `advisory`.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Do we ship this change today, or hold it? | gate | 2–10×/week | any engineer seat, `qa_manager` | A bad ship on a 6,198-row `health_checks` history with no rollback rehearsal; on a live reveal it is refundable revenue |
| 2 | Which of the 611 RLS-on-no-policy tables gets a deliberate policy next? | sequencing | monthly | `security`, `backend_engineer` | Wrong order leaves the customer-facing read path on `service_role` longer than it needs to be |
| 3 | Does this new capability belong in a database routine, an edge function, or the Next.js app? | craft | 3–8×/month | `backend_engineer` | 1387 routines and 206 functions already; a wrong placement adds a component with no owner and no trace policy |
| 4 | Is this incident a platform incident or a business incident? | diagnosis | weekly | `it`, `red_view_alerter` | Mis-routing sends `ops_alert` to the founder's inbox against `founder_mail_policy` |
| 5 | Which department objective does this engineering work serve? | allocation | per work order | `ceo`, `chief_of_staff` | Work that serves nothing burns the `cos_reflection_tasks_per_day = 500` budget |
| 6 | May this action class run autonomously, or must it be gated? | gate | 1–4×/month | `chief_of_staff`, any seat | `action_class_gate` has 90 rows and several carry `FLAGGED FOR REVIEW`; a wrong ungating removes a founder boundary |
| 7 | Is the 393 ms mean HTTP latency about to breach the 400 ms goal? | forecast | weekly | `it`, `ceo` | 1.75% headroom; a breach is a public goal missed with no warning |
| 8 | Which of the 5 `product_eng` goals with `NO INSTRUMENT EXISTS` gets an instrument first? | sequencing | quarterly | founder, `ceo` | Half this department's declared goals are unmeasurable; picking the wrong one keeps the scoreboard fictional |
| 9 | Is a `phase_c_component` row `WIRE_TO_CANONICAL` real debt or an accepted state? | diagnosis | monthly | `qa_manager` | 770 components sit in `WIRE_TO_CANONICAL`; treating them all as debt paralyses delivery |
| 10 | Do we accept this architectural exception, and for how long? | gate | monthly | any seat | An exception with no expiry becomes the architecture |
| 11 | Which seat owns this defect? | allocation | daily | `red_view_alerter`, `it` | Unowned defects sit; `org_tasks` holds 2,466 rows |
| 12 | Is this change reversible, and what is the compensation if not? | gate | per change | `backend_engineer` | The action dispatcher refuses irreversible actions with no declared compensation — an undeclared one silently never runs |
| 13 | Does this deploy need a new `phase_c_component` row? | gate | per edge deploy | `backend_engineer` | A deployed function with no component row is invisible to the exposure board |
| 14 | Should this cron job exist, and at what cadence? | allocation | monthly | `it` | 134 active jobs; each tick costs a `pg_net` slot and a trace row (57,612 already) |
| 15 | Is the `agent_reasoning` cost per call still zero? | forecast | weekly | founder, `cfo` | The KPI target is AED 0.15/call and actual is AED 0.0000; a regression to paid inference breaks the founder's hard rule |
| 16 | Which 30 of 1387 routines are the load-bearing ones? | diagnosis | quarterly | `qa_manager`, `security` | Without a criticality ranking every check is equally urgent, which means none is |
| 17 | Do we build this or does the estate already have it? | craft | weekly | any seat | Re-implementation is the commonest waste in a 1398-file SQL tree |
| 18 | Is this a defect or a misdiagnosis in the brief? | diagnosis | per session | `ceo`, session briefs | Chasing a false positive costs a session; four of eleven audit findings on 3 Sep were real |
| 19 | What is the blast radius of this schema change? | forecast | per DDL | `backend_engineer` | 416 triggers and 1141 indexes; a careless `alter` locks a table the reveal path reads |
| 20 | Should this seat be re-hired or stay parked? | allocation | quarterly | `ceo`, `people_ops` | Nine parked seats; re-hiring one without work for it re-creates the KPI-with-no-measure finding |
| 21 | Is the platform ready for the first paying reveal? | gate | until first revenue | founder, `ceo` | `transactions=0`; declaring readiness that is not there loses the first customer |
| 22 | Which check would have caught this defect, and does it exist? | craft | per incident | `qa_manager` | The CTO's own KPI on this reads `NEEDS AN INSTRUMENT THAT DOES NOT EXIST` |
| 23 | Do we accept this vendor/extension into the estate? | gate | rare | `security`, `it` | Nine extensions today; each is a supply-chain surface and a Supabase upgrade constraint |
| 24 | Is this cost line worth what it buys? | allocation | monthly | `cfo` | AED 154.22 of AI spend in 30 days is small; the risk is a silent return to paid inference |
| 25 | Which technical risk in `risk_register` changes status this month? | diagnosis | monthly | `ceo` | Five `product_eng` risks; #17 (RLS-no-policy) has been `open` since 26 Jul |
| 26 | Does this design keep identities anonymous until the reveal? | gate | per feature | `backend_engineer`, `legal` | Hard rule 4; a leak is AED 15,000/incident or 3× the fee against *us* if we caused it |
| 27 | Is the top-3 comparison logic still deterministic? | gate | per pricing/report change | `qa_manager` | Hard rule 2; a model-scored ranking would breach the founder's constraint |
| 28 | What is the smallest change that turns this red board green *honestly*? | craft | weekly | `red_view_alerter` | The alternative is weakening a check, which is forbidden |
| 29 | Do we adopt this new Postgres/Supabase feature? | craft | quarterly | `backend_engineer` | PostgreSQL 17.6; adopting a feature the platform later restricts is a migration we did not need |
| 30 | Is this knowledge gap a training problem or a data problem? | diagnosis | monthly | `qa_manager`, `people_ops` | `security` scored 27.5% then 42.5% on CISSP; if the corpus lacks Domain 6, retraining the seat is theatre |
| 31 | Which capability do we deliberately *not* build this quarter? | sequencing | quarterly | founder, `ceo` | Scope with no stated exclusions expands until nothing ships |
| 32 | Does this work need the founder, or is that an escalation habit? | escalation | weekly | any seat | `founder_review_gates` is refunds only; every other escalation to him is a policy breach |
| 33 | Is the department's headcount right for the work in `org_tasks`? | allocation | quarterly | `ceo` | Six active seats against 2,466 tasks; the wrong answer is hiring instead of automating |
| 34 | Has an architectural decision been superseded without anyone recording it? | diagnosis | quarterly | `qa_manager` | `decision_trace` holds 1,733 rows; a superseded decision still being cited is how a retired door gets re-opened |

### 2. Domain logic (the models this seat reasons with)

**M1 — Change-risk score.** `risk = 0.35·blast + 0.25·reversibility + 0.20·surface + 0.20·evidence_age`,
each term normalised 0–1.
`blast` = (dependent routines + triggers + views touching the object) ÷ 50, capped at 1, from `pg_depend`
joined to `pg_trigger` and `information_schema.view_table_usage`.
`reversibility` = 0 if the change has a `compensation` recorded on its `action_class`, 1 if not
(`action_class_gate`, 90 rows).
`surface` = 1 if the object is reachable by `anon` or `authenticated` (`pg_policies`,
`has_function_privilege`), else 0.2.
`evidence_age` = days since the last green run of the check that covers it ÷ 7, capped at 1
(`qa_results.run_at`, 288 rows).
**Outputs**: a 0–1 score and the term that dominates it.
**UNMEASURED**: there is no table that records which check covers which object. The mapping
check→object **does not exist**; `evidence_age` is today computable only estate-wide (last `qa_results`
row 7 Sep 03:37) rather than per object.

**M2 — Latency headroom.** `headroom_pct = 100·(goal − actual) ÷ goal` where `goal = 400`
(`company_goals.api_response`) and `actual = round(avg(latency_ms))` over
`health_checks where check_kind='http' and created_at > now() - interval '30 days'`.
Measured 7 Sep: `actual = 393`, `headroom = 1.75%`.
Trend by ordinary least squares on the daily means: `slope = Σ((d−d̄)(y−ȳ)) ÷ Σ(d−d̄)²`, and
`days_to_breach = (400 − actual) ÷ slope` when `slope > 0`, else `∞`.
**UNMEASURED**: `health_checks` records one target per row but no per-route breakdown table exists, so the
seat cannot say *which* route is dragging the mean.

**M3 — Reliability budget.** Over 30 days: `error_rate = errors ÷ total` on `agent_runs`
(681 ÷ 22,563 = **3.02%**), against `it`'s KPI target of ≤3% (97% non-error). Error budget consumed
= `error_rate ÷ (1 − 0.97) = 1.007` — i.e. **the 30-day budget is exactly spent**, while the 7-day window
reads 98.23%. Both are true; the seat must quote the window.

**M4 — Component debt.** `debt = WIRE_TO_CANONICAL + REPAIR_BEFORE_REACTIVATION + DEFERRED_RUNTIME_IMPLEMENTATION`
over `phase_c_component` = 770 + 1 + 119 = **890 of 1870 (47.6%)**.
`canonical = CANONICAL_KEEP + CANONICAL_BETTER_KEEP + ACTIVE_* + ACCESS_CONTROLLED_NO_CALLER` = 887.
Burn-down rate = Δdebt ÷ Δweeks from `measured_at`.
**UNMEASURED**: `phase_c_component.measured_at` is a single snapshot column, not a history table, so the
burn-down rate **cannot be computed today**; it needs a `phase_c_component_history` table that does not exist.

**M5 — Ownership coverage.** `covered = routines with a kernel_routine_ownership row of class
QUOTESDONE_APPLICATION or HISTORICAL_APPLICATION` = 617 + 335 = 952 of 1387 = **68.6%**; the balance is
extension/platform-managed (262) and 2 justified-untracked. Manifest coverage proper =
617 ÷ 952 = **64.8%**.

**M6 — Cost per unit of work.** `aed_per_call = sum(cost_aed) ÷ count(*)` on `ai_cost_log`.
30 days: 154.216130 ÷ 2954 = **AED 0.0522**. Last 7 days: **AED 0.0000** across all four task classes.
KPI target 0.15. **The estate is already deterministic; the model is a regression detector, not a
budgeting tool.**

**M7 — Escalation legality.** A notification may reach the founder iff
`founder_mail_policy.allowed_to_email = true` for its `kind`. Of the 60 policy rows, the ones this
department can legitimately trigger are `platform_down`, `uptime_alert`, `backup_failed_after_retry`,
`security_critical` and `stripe_webhook_failed`. Every other engineering kind — `red_view`, `incident`,
`os_incident`, `health_alert`, `smoke_alert`, `scheduled_runs_failed`, `agent_silence`, `resilience`,
`ops_alert`, `ai_quality_alert`, `llm_drift`, `agent_escalation` — is `false` and routes to a role.
This is a lookup, not a judgement.

**M8 — Revenue exposure of a defect.** `exposure_aed = affected_reveals × mean_selected_quote × 0.03`.
`0.03` is measured (`pricing_config.standard_reveal_rate`).
**UNMEASURED and unmeasurable today**: `mean_selected_quote` — `quotes` holds 0 rows. Until a quote exists
this model returns "cannot compute" and the seat must say so rather than assume a value.

### 3. Reasoning procedures

**Type 1 — ship or hold.**
(a) Read the change's touched objects. (b) Compute M1. (c) Read the latest `qa_results` row; if
`run_at` is older than 24 h or `passed = false`, **stop and refuse** — "the gate has not run against this
tree". (d) Read `agent_runs` errors in the last 24 h; if the count exceeds the 7-day mean by more than 2σ,
hold: the estate is already unstable. (e) Read `deploy_state.dirty`; if dirty, the last deploy did not
complete — refuse. (f) If `M1 ≥ 0.6` **and** the change touches a `SECURITY DEFINER` routine or an object
reachable by `anon`, require `security` sign-off before shipping. (g) Otherwise ship, and record the
decision in `decision_trace` with `policy_keys`, `evidence_refs` and the flip condition ("this becomes a
hold if `qa_results.failed > 0` or `M1` crosses 0.6").
**Options come from**: the change itself, `now`, `next window`, `split into N`, `behind a flag`, `refuse`.
**Stops and refuses when**: no green gate run inside 24 h; `deploy_state.dirty`; the change has no named
check that would fail on the defect it claims to fix.

**Type 2 — which RLS table gets a policy next.**
(a) List the 611 tables with `relrowsecurity` and no `pg_policies` row. (b) Score each:
`priority = 3·(app_reads_it) + 2·(holds_personal_data) + 1·(row_count_bucket)`. `app_reads_it` comes from
grepping `qd_deploy_src` (70 rows) and the Next.js tree for the table name; `holds_personal_data` from
`phase_d_personal_identifier_class`; `row_count_bucket` from `pg_stat_user_tables.n_live_tup`
(0 for <1k, 1 for <100k, 2 above). (c) Rank; take the top three. (d) For each, state the policy shape as
`for select to authenticated using (<predicate>)` where the predicate is drawn from the table's own owner
column. (e) Flip condition: a table whose only reader is a `SECURITY DEFINER` routine scores 0 and must
**not** get a policy — adding one widens the surface for nothing.
**Refuses when**: the table's readers cannot be established from `qd_deploy_src` — 70 of 206 functions are
mirrored there, so for 136 functions the reader set is **unknown**. That gap is itself the finding.

**Type 6 — may this action class be autonomous.**
(a) Read the `action_class_gate` row. (b) Read the executor it actually invokes (`org_action_executor`)
and classify its writes: does it move money (`gl_journal`, `refunds`, `transactions`), send externally
(`notifications`, `send_*`), or delete? (c) If money → `money_move`, gated, full stop. (d) If external
send → bounded by the outbound caps, never ungated. (e) If it writes only internal, reversible state →
eligible. (f) Cross-check `org_authority` for `product_eng` (`code_deploy=supervised`,
`authentication_identity=gated`, `autonomy_framework=gated`, `destructive_data=gated`). (g) Record the
review in `action_class_gate.reviewed_on/by`.
**Stops when**: the rationale on file describes a *different function* from the one the executor points at
— this happened twice already (`code_selfheal` and `incident_fix` both had rationales that did not match
their target code until 2 Sep 2026). Re-reading the target code is step (b) for exactly that reason.

**Type 8 — which unmeasurable goal gets an instrument first.**
(a) List `company_goals where owner_dept='product_eng' and measure_sql is null` → `classification_accuracy`,
`hallucination_rate`, `missing_info_detection`, `production_bugs`, `rto`. (b) For each, name the table that
would have to exist and the row that would have to be written. (c) Score
`value = (goal_is_on_the_revenue_path ? 2 : 0) + (instrument_is_one_table ? 1 : 0) − (needs_a_model ? 3 : 0)`.
(d) `hallucination_rate`, `classification_accuracy` and `missing_info_detection` all score negative: their
honest instrument requires a labelled holdout set that **does not exist**, and grading free text without one
needs a model. `production_bugs` and `rto` score positive: both are one table each (`defect_log` with a
`found_in` column; `dr_drill` timings, where the drill routine already exists).
(e) Verdict: build `production_bugs` and `rto` first; write "needs a labelled holdout set, not an
instrument" against the other three rather than pretending.

**Type 18 — defect or misdiagnosis.**
(a) Restate the claim as a predicate over named rows. (b) Run it. (c) If it returns zero, the claim is a
misdiagnosis — record it so the next session does not re-chase it. (d) If non-zero, check whether the
*count* or the *cause* is what the brief asserted; briefs carry reliable counts and unreliable causes.
(e) Only then open work.
**Stops when**: the claim cannot be turned into a predicate. That is a refusal, not a licence to guess.

**Type 22 — which check would have caught this.**
(a) Take the defect's failing predicate. (b) Search `scripts/checks/*.test.mjs` (110 files) for an
assertion over the same subject. (c) If found, ask why it was green: wrong window, wrong subject,
excluded in `test-profiles.json`, or the guard is dead. (d) If not found, the deliverable is the check
itself, and it must **fail before the fix and pass after** — a check written after the fix that has never
been red proves only that somebody typed it.
**Refuses when**: the defect has no reproducible predicate.

**Type 32 — does this need the founder.**
(a) Read `decision_policy.founder_review_gates` → `["refund_decision","refund_outside_policy"]`. (b) If the
kind is not one of those two, it does not go to him. (c) Read `founder_mail_policy` for the kind; if
`allowed_to_email = false`, route to `owner_role` via `fn_founder_mail_route`. (d) If the kind has no policy
row, it is `agent_action_unclassified` and belongs to the chief of staff — **not** to the founder.
This procedure has one output and no discretion.

### 4. Judgement rules

| Condition | Verdict | Reason |
|---|---|---|
| No `qa_results` row with `passed=true` inside 24 h of the tree being shipped | **hold** | An unproven tree is an unproven tree; 288 rows exist and the latest is 15/15 |
| `deploy_state.dirty = true` | **hold** | The previous deploy did not finish; two half-deploys is worse than one |
| Change touches a `SECURITY DEFINER` routine and no `revoke from public/anon` is in the same file | **reject** | 904 SECDEF routines; a created one is granted to PUBLIC by default. `risk_register` #16 is open on exactly this |
| A check is failing and the proposed fix edits the check | **reject, always** | Never weaken a check. If the check is wrong, that is a separate, argued change with its own evidence |
| A gate turns green only because a CSV was emitted | **reject** | Mirror gates are retired; production proves properties |
| The fix makes a headline number fall | **ship it, and say so** | A real fix that lowers a number is still a fix; hiding it is the defect |
| An escalation kind is not in `founder_review_gates` | **never route to founder** | Refunds only. This is not a judgement call |
| `M1 ≥ 0.6` and no rollback path recorded | **hold** | High blast radius with no way back is the definition of an outage waiting |
| Two seats claim the same defect | **cto assigns; the loser's task is closed with a reason** | Unowned and double-owned are the same failure |
| Proposal scores well but adds a component with no `phase_c_component` row | **reject even though it scores well** | 1870 rows exist so that nothing is invisible; one exception makes the board a lie |
| Proposal is to re-hire a parked seat with no measurable KPI | **reject even though it scores well** | Every parked seat carries "Employee has no measurable KPI" already; re-hiring reproduces the finding |
| Proposal is to raise `auto_action_max_aed` above 0 | **reject; founder boundary** | `decision_policy.auto_action_max_aed = 0` — agents never move money without a human |
| An architectural exception has no expiry date | **reject** | An exception without a date is a decision |
| Any design that requires an LLM call on the customer's request path | **reject** | The founder's constraint, stated twice |
| Latency headroom < 2% and trending up | **open work now, do not wait for the breach** | Measured today: 393/400 = 1.75% |
| An incident's `owner` is `it` but the fix is a schema change | **reassign to `backend_engineer`; `it` keeps the incident** | The runner and the fixer are different seats; `os_incidents` already models this |
| A knowledge gap is claimed but `ops_knowledge` has ≥1 embedded row on the subject | **retrieval defect, not a knowledge gap** | 9,140 rows, all embedded; assume the corpus before assuming ignorance |

### 5. Technical knowledge

- **PostgreSQL 17.6** — `SECURITY DEFINER` semantics and default PUBLIC grant; RLS evaluation order and
  the difference between "RLS enabled with no policy" (deny-all) and "RLS disabled" (open);
  `search_path` pinning inside definer routines; trigger firing order by name prefix (the estate encodes
  order in the prefix — this is in `qa_manager`'s stored knowledge already); lock levels of each `ALTER`
  form; `pg_stat_statements 1.11` for hot-statement ranking; `pg_depend` for blast radius.
- **Supabase platform** — one project, `htdblwldjkcgjvmqkbeh`, no staging. The management SQL API used by
  `scripts/phase_c/lib/db.mjs` runs each call in its own transaction and returns **429** under throttle,
  which reads exactly like a broken query. Edge functions are Deno; `deno check` is the type gate;
  `scripts/deploy_functions.mjs --ref=… --production <slug>` is the deploy path.
- **Extensions in use and their limits** — `pg_cron 1.6.4` (235 jobs, 134 active; jobs run as the
  scheduler role, and a statement timeout cancels them — this is why `red_view_alert_15min` failed three
  times in seven days), `pg_net 0.20.3` (async HTTP; the response must be *collected* in a later tick,
  which is why the action invoker is a dispatch/collect pair), `vector 0.8.0` (`gte-small`, 384 dims, free
  in-region), `pg_trgm 1.6`, `pgcrypto 1.3`, `supabase_vault 0.3.1`.
- **The kernel** — `fn_kernel_wrap_and_enable_cron(jobid, role, dept, authority)`,
  `fn_kernel_cron_exec(jobid)`, `fn_kernel_all_boards()`, `fn_kernel_trace_integrity()`,
  `kernel_write_authority` (47 rows), `kernel_routine_ownership` (1216 rows) and its six classification
  rules R1–R6.
- **The manifest discipline** — a new `scripts/sql/*.sql` file needs its `MANIFEST` line or
  `canonical_routines` fails; the **last** manifest file naming a routine is canonical for **all** its
  overloads, so a file changing one overload must restate every overload.
- **The check battery** — 110 files in `scripts/checks/`, discovered by `run.mjs` (which exports
  `discover()` so `every_test_file_is_run.test.mjs` asserts against the real walk, not a copy);
  `test-profiles.json` carries named, owned exclusions and `every_exclusion_still_matches_a_test.test.mjs`
  stops an exclusion outliving its subject.
- **What must be stored so this seat never has to ask**: the six-rule ownership taxonomy; the 90
  `action_class_gate` rows with their rationales; the 60 `founder_mail_policy` rows; `org_authority` for
  `product_eng` (`code_deploy=supervised`, `authentication_identity/autonomy_framework/destructive_data=gated`,
  `analysis/coordinate/code_selfheal=autonomous`); `decision_policy` (`auto_action_max_aed=0`,
  `financial_review_aed=10000`, `confidence_min=0.6`, `founder_review_gates`); the deploy command line;
  the 429-is-a-throttle fact.
- **Does not exist**: a check→object coverage map; a `phase_c_component` history; a per-route latency
  table; a defect register.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source | Ingest or cite |
|---|---|---|---|
| Enterprise architecture | TOGAF ADM phases, architecture partitioning, governance | The Open Group's freely-registerable TOGAF Standard | **Cite only** — the licence forbids redistribution. Ingest the ADM phase names and the governance-body definition, nothing more |
| Cloud solution design | AWS Well-Architected Framework, six pillars | AWS's own published whitepapers | Cite; ingest the pillar questions as a checklist, not the prose |
| Reliability engineering | SLI/SLO/error-budget arithmetic, toil definition | Google's freely-published SRE material at `sre.google` | **Cite only**; the arithmetic itself (M3 above) is ours |
| Distributed systems | Idempotency, at-least-once delivery, the dispatch/collect pattern | IETF RFCs (RFC 9110 HTTP semantics, RFC 7231 idempotent methods) — public standards | **Ingest** |
| Data modelling | Normalisation, constraint-as-truth | PostgreSQL official documentation (PostgreSQL Licence) | **Ingest** |
| Software architecture | Coupling/cohesion, the "finished capability with no entry point" failure | ISO/IEC/IEEE 42010 abstract + freely published summaries | Cite; the standard text is paid |
| Decision recording | Architecture Decision Records | Public ADR templates (MIT-licensed) | **Ingest** |
| UAE technology governance | UAE Digital Government/Digital Economy strategy documents | UAE government portal publications | **Ingest** |

**Certifications on file**: AWS Certified Solutions Architect – Professional (pass mark 75.00, rank 1) and
TOGAF 9 Certified (60.00, rank 2). **Syllabus areas failed: does not exist — this seat has never sat
either exam.** The recorded syllabus areas it is accountable for are, for AWS SA Pro: *Design Solutions for
Organizational Complexity, Design for New Solutions, Continuous Improvement for Existing Solutions,
Accelerate Workload Migration and Modernization*; for TOGAF: *ADM Phases, ADM Guidelines and Techniques,
Architecture Content Framework, Enterprise Continuum and Tools, Architecture Governance, Architecture
Capability Framework, Architecture Partitioning, Stakeholder Management*. Until an exam is sat, this seat's
competence in those areas is **asserted, not measured**, and this document says so.

### 7. Corporate knowledge

- **The founder's hard rules** live in `fn_company_hard_rules()` and are read from the published Supplier
  Agreement plus `pricing_config` at call time: reveal fee **3.00%** of the selected quotation value, no
  cap, no discount, no promo, no free reveal; comparison free; suppliers pay no commission ever;
  registration free for the first **1000** registrations then **AED 1000/year** with no calendar start
  date; **top-3** comparison on technical *and* commercial merit; the **5-working-day** non-response ladder
  with a chase on day 3 and the founder's final call on day 5; anti-circumvention at **AED 15,000 or 3×**
  the fee for 24 months; a category **opens at 10 verified suppliers**. Never re-ask any of it.
- **The one founder gate** — `decision_policy.founder_review_gates = ["refund_decision","refund_outside_policy"]`.
  Every refund is his; nothing else is.
- **What this seat owns**: the `production_deploy` hard gate behind `action_class code_deploy`
  (`org_authority.product_eng.code_deploy = supervised`); `ai_quality_alert`, `llm_drift`,
  `health_alert` and `agent_escalation` as `founder_mail_policy` **owner_role = cto** — meaning those
  never reach the founder, they reach this seat.
- **Hands to**: `backend_engineer` (schema and routine work), `it` (cron, restarts, backups),
  `security` (SECDEF, RLS, secrets), `qa_manager` (the gate battery), `red_view_alerter` (the alert path),
  `chief_of_staff` (unclassified work), `cfo` (spend above AED 10,000).
- **History it must not forget**: the deleted staging project `pglpqrhvozwepymcuunn` (there is ONE project);
  `attachment.test.ts` sitting unrun for a month; the `$WT/` stale worktree that made `npm test` run a
  second copy of the estate's gates; the 21 production functions that had no source control (risk #9,
  still `mitigating`); mirror gates being retired; phase freezes lifted 2 Sep 2026.
- **Live risks on this seat** (`risk_register`): #9 "21 production functions previously had no source
  control" — `mitigating`, owner `cto`, "CI regeneration still pending"; #17 "257 tables have RLS enabled
  with no policy" — `open`, owner `cto`. **Risk #17's number is now 611, not 257**; the register is stale
  and correcting it is this seat's work.

### 8. One-year plan

**Objective.** Make the paid path provably safe to run unattended, so that revenue is never lost to a
platform defect, and do it at zero paid inference.

**This seat's slice of AED 1,000,000: AED 0 of direct revenue, and the whole of the downside.**
`company_goals.revenue_annual` is owned by `finance`. `product_eng` owns ten goals and none of them is a
revenue goal. The honest arithmetic: at the measured reveal rate of 3.00%, AED 1,000,000 of revenue requires
**AED 33,333,333 of revealed selected-quote value**. How many reveals that is **cannot be computed** — the
mean selected-quote value is unmeasured because `quotes` holds 0 rows. This seat must not guess it, and the
plan below is therefore expressed in availability and defect terms, not in revenue terms.

**Metrics this seat owns** (all three exist and are measured today):
1. **Platform availability** — `employee_kpi` id 62, target 99.5%, actual **100.00%** (7 Sep 03:30).
2. **Cost per `agent_reasoning` call** — id 108, target AED 0.15, actual **AED 0.0000**. Owned as a
   *regression detector*: any non-zero reading is a breach of the founder's constraint.
3. **Prompt tokens per reasoning call** — id 109, target 18,000, actual **0**.

It also carries three KPI rows that **cannot be measured today** and should be honestly re-cut:
- id 107 "Production changes behind a failing-first check", target 100% — `no_measure_reason` reads
  *"NEEDS AN INSTRUMENT THAT DOES NOT EXIST."*
- id 133 "Contribute to: Every production change ships behind a check that fails on the defect it claims to
  catch" — no measure.
- id 87 "Ideas captured", target 10/month, actual **0** — the only KPI this seat is currently *missing*,
  and it measures idea volume, not engineering.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** Sit the AWS SA Pro and TOGAF exams — competence is currently asserted, not
  measured. Build the **defect register** (`defect_log`) so `production_bugs` and CTO KPI 107 become
  measurable; the register is one table with `found_in ∈ {check, production}`. Correct `risk_register` #17
  from 257 to 611. Bring the four `FLAGGED FOR REVIEW` action classes to a decision.
- **Q2 (Dec 2026–Feb 2027).** Build the **check→object coverage map** so M1's `evidence_age` is per-object.
  Take the RLS-no-policy count down by writing deliberate policies for the tables the app actually reads —
  starting with the ones `qd_deploy_src` proves are read. Close risk #9 by regenerating CI from source.
- **Q3 (Mar–May 2027).** Component debt: 890 of 1870 rows are `WIRE_TO_CANONICAL`, `DEFERRED` or
  `REPAIR_BEFORE_REACTIVATION`. Build `phase_c_component_history` first so the burn-down is measurable at
  all, then burn it down. Instrument `rto` from the existing `dr_drill`.
- **Q4 (Jun–Aug 2027).** Latency: 393 ms against a 400 ms goal is not a plan, it is a coincidence. Build
  the per-route latency table and take the mean below 300 ms.

**Capacity check.** Can this seat's work produce AED 1,000,000? **No, and it is not supposed to.** This seat
produces *availability of the path*. Measured capacity: `max_open_tasks = 50`, and `org_tasks` holds 2,466
rows across the company. The Q1–Q4 list above is four builds and one exam sitting — that is deliverable by
one seat in a year. What is **not** deliverable by this seat is demand: `inquiries = 0`. If demand stays at
zero, every metric in this plan can be green and the revenue will still be AED 0.

**Dependencies.** `backend_engineer` for every schema change; `qa_manager` for the failing-first
discipline; `security` for the RLS policy design; `it` for cron and backup; **`marketing`/`growth` and
`supply` for the only thing that turns this department's work into money — inquiries and verified
suppliers.** At 1 verified supplier of 22,265 leads and a category-open threshold of 10, the marketplace
cannot match anything, and no amount of platform work changes that.

**Is the slice achievable?** The availability and cost metrics: yes, they are green today. The
*measurement* metrics: not without the two tables named above, which is why they are Q1. The revenue: not
by this seat, and the plan says so rather than claiming a share of a number it does not move.

### 9. What this seat cannot do without a model

1. **Reading a free-text architectural proposal written by a human and deciding whether it is coherent.**
   The taxonomy match will route it; the *judgement* on novel prose is not arithmetic. Deterministic
   fallback: refuse with "restate this as a change to named objects and I will score it".
2. **Writing the code.** Every resolver here decides *whether* and *in what order*; producing the SQL or
   TypeScript is a model or a human.
3. **Grading `hallucination_rate`, `classification_accuracy` and `missing_info_detection`.** All three
   compare generated text to intent. Without a labelled holdout set they need a model; with one, they need
   only string comparison. The holdout set does not exist. This is why those three goals carry
   `NO INSTRUMENT EXISTS` and why the honest fix is a fixture, not an instrument.

---

## backend_engineer — Backend Engineer

"Builds and maintains edge functions, database and APIs." `routing_tier=analyst_controller`, reports to
`cto`. Authority as recorded: `health_report`, `recommend`, `security_review`, `uptime_verify`
**autonomous** at `threshold_aed = 0`; `code_selfheal` and `incident_fix` **advisory** — "may prepare, but
execution requires the department head". One KPI: *Platform availability*, target 99.5%, actual 100.00%.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Which routine implements this behaviour today? | diagnosis | daily | `cto`, `qa_manager` | 1387 routines; guessing produces a second implementation of a thing that exists |
| 2 | Is this behaviour a trigger, a routine, a cron or an edge function? | craft | weekly | `cto` | Wrong layer = a component with no trace policy and no owner |
| 3 | What lock does this `ALTER` take, and for how long? | forecast | per DDL | `cto` | An `ACCESS EXCLUSIVE` on a hot table stalls the reveal path |
| 4 | Does this function have overloads, and does my file restate them all? | gate | per routine change | `qa_manager` | The manifest engine takes the LAST file naming a routine as canonical for ALL overloads — a partial file silently drops one |
| 5 | Does this new SQL file have its `MANIFEST` line? | gate | per SQL file | `qa_manager` | `canonical_routines` fails; the gate battery goes red on a correct change |
| 6 | Did I revoke `EXECUTE` from `PUBLIC`/`anon` on the `SECURITY DEFINER` function I just created? | gate | per SECDEF create | `security` | 904 SECDEF routines exist; a created one is PUBLIC-executable by default. Risk #16 is open on this |
| 7 | Is this write idempotent under at-least-once delivery? | craft | per handler | `cto` | `pg_net` dispatch/collect can retry; a non-idempotent handler double-writes a transaction |
| 8 | Which index does this query use, and is it there? | diagnosis | weekly | `it` | 1141 indexes; a sequential scan on `kb_chunks` (2,681,290 rows) is an outage |
| 9 | Is this query the one burning the CPU? | diagnosis | weekly | `it` | `pg_stat_statements` is the answer; guessing is not |
| 10 | Does this edge function have a `phase_c_component` row? | gate | per deploy | `cto` | 204 edge components against 206 directories — a missing row is an invisible surface |
| 11 | Does this function import `_shared/llm.ts`, and is it in the credential migration list? | gate | per function change | `security` | An unlisted LLM-importing function bypasses the paid-inference gate |
| 12 | Is this the third caller of the same logic — should it be one routine? | craft | monthly | `cto` | Duplication is where two behaviours silently diverge |
| 13 | Why did this trigger not fire? | diagnosis | weekly | `qa_manager` | 416 triggers; firing order is encoded in name prefixes and a BEFORE trigger cannot read what a later one writes |
| 14 | Is this `NULL` a missing value or an unmeasured one? | diagnosis | weekly | `cto`, `data_intel` | The estate distinguishes them with `no_measure_reason`; collapsing them fabricates a measurement |
| 15 | What is the correct `search_path` for this definer routine? | gate | per SECDEF | `security` | An unpinned `search_path` in a definer routine is a privilege-escalation primitive |
| 16 | Does this schema change need a backfill, and is the backfill restartable? | craft | per migration | `cto` | A backfill that cannot resume from a partial state is a backfill that cannot be run twice |
| 17 | Does this API return the same shape it did yesterday? | gate | per API change | `qa_manager` | The portal and the OS both read it; a silent shape change is a broken screen |
| 18 | Is this error a throttle (429) or a defect? | diagnosis | daily | any seat | The management API 429s under load and it reads exactly like a broken query — this has been misdiagnosed before |
| 19 | Should this be a view or a materialised table? | craft | monthly | `cto` | 214 views; a view over 2.6M rows recomputed per read is a latency problem with no error |
| 20 | Which of the 611 policy-less RLS tables does the app actually read? | diagnosis | quarterly | `cto`, `security` | Only 70 of 206 functions are mirrored in `qd_deploy_src`; for the rest the reader set is unknown |
| 21 | Does this cron job's command still parse? | gate | per cron change | `it` | `every_cron_command_still_parses.test.mjs` exists because it did not once |
| 22 | Is this constraint better expressed in the database than in code? | craft | per feature | `cto` | A DB constraint cannot be forgotten by a new caller; app code can |
| 23 | Is this the right place to enforce the 3% reveal rate? | gate | per pricing touch | `cto`, `finance` | `pricing_config` is the single source; a hard-coded 0.03 anywhere else is a second truth |
| 24 | Does this change keep supplier and customer identities separated until reveal? | gate | per feature | `cto`, `legal` | Hard rule 4; anti-circumvention is AED 15,000 or 3× the fee |
| 25 | Is this data-loss risk real, and is there an undo? | gate | per destructive change | `security` | `undo_log` holds 28,596 rows and `knowledge_ingestion_undo` 33,075 — the estate expects an undo |
| 26 | Should this run in the request or in a queue? | craft | per feature | `cto` | 393 ms mean latency with 1.75% headroom; in-request work is where the headroom goes |
| 27 | Does this function need a per-function credential, and which context? | gate | per new function | `security` | `internal_credential` has 87 rows scoped by `context`; the legacy shared secret was retired 3 Sep 2026 |
| 28 | Is this deploy at parity with what is in the repository? | gate | per deploy | `qa_manager` | `verify_deploy_parity.mjs --all` exists for this; drift means the repo is fiction |
| 29 | Which table should this new fact live in, so the company can know it? | craft | monthly | `cto`, knowledge seats | Company facts must live in a TABLE and be rendered by `fn_company_self_knowledge_sync()`; a fact only in prose is not knowledge |
| 30 | Does this batch size fit inside the statement timeout? | forecast | per batch job | `it` | `red_view_alert_15min` failed three times in seven days on `canceling statement due to statement timeout` |
| 31 | Is this dead code, or a finished capability with no entry point? | diagnosis | quarterly | `cto` | 119 components are `DEFERRED_RUNTIME_IMPLEMENTATION` — built and unreachable is not the same as dead |
| 32 | What does this routine do when its input is absent rather than wrong? | craft | per routine | `qa_manager` | A guard that cannot fire and a guard that always fires are the two commonest defects in this estate |

### 2. Domain logic (the models this seat reasons with)

**M1 — Blast radius.** `blast(object) = deps + trg + views + callers` where `deps` = rows in `pg_depend`
referencing the object, `trg` = triggers on the table (416 non-internal exist estate-wide),
`views` = `information_schema.view_table_usage` rows, `callers` = routines whose `prosrc` names it
(a `pg_proc.prosrc ILIKE` scan over 1387 rows). **Output**: a count and the named dependants.
Threshold: `blast > 20` requires the change be split.

**M2 — Lock class.** A lookup table, not a computation: `ADD COLUMN … DEFAULT NULL` → `ACCESS EXCLUSIVE`
but instantaneous on PG 17; `ADD COLUMN … NOT NULL DEFAULT <const>` → fast-path since PG 11;
`ALTER TYPE` → table rewrite; `CREATE INDEX` → `SHARE` (use `CONCURRENTLY`); `ADD CONSTRAINT … NOT VALID`
then `VALIDATE` → the safe two-step. **Stored as a table** so the seat looks it up rather than recalling it.
**UNMEASURED**: table-level write rates. `pg_stat_user_tables` gives `n_live_tup` but this estate has never
recorded `n_tup_upd` over time, so "how long will this lock hurt" is answerable only as "how big is it".

**M3 — Overload completeness.** For a routine name `r`:
`overloads_live = count(*) from pg_proc where proname = r`;
`overloads_in_file` = definitions parsed from the candidate `scripts/sql` file.
**Rule**: `overloads_in_file must equal overloads_live`, because the manifest engine treats the last file
naming `r` as canonical for all of them. This is pure arithmetic and it is the single most common way a
correct change breaks the gate.

**M4 — Idempotency class.** A handler is one of: `PURE_READ` (no writes), `IDEMPOTENT_UPSERT` (writes are
`on conflict do update` keyed by a natural key), `GUARDED_INSERT` (insert with a uniqueness constraint that
makes the second attempt a no-op), `NOT_IDEMPOTENT`. Derived by parsing the routine body for `insert`,
`update`, `delete` and `on conflict`. **Rule**: anything reached by `pg_net` dispatch/collect or by the
event outbox must not be `NOT_IDEMPOTENT`.

**M5 — Cost of a query.** `cost = calls × mean_exec_time` from `pg_stat_statements 1.11`, ranked. The
top-N by total time is the work list. **UNMEASURED**: `pg_stat_statements` is present but this estate has
no snapshot table, so *trend* is unavailable — only the current cumulative view since the last reset.

**M6 — Batch sizing.** `safe_batch = floor(statement_timeout_ms ÷ (mean_row_ms × 1.5))`, where
`mean_row_ms` is measured by timing a small batch. Measured evidence that this matters:
`red_view_alert_15min` (jobid 324) failed on 5 Sep 21:22, 7 Sep 06:37 and 7 Sep 06:52, each time with
`canceling statement due to statement timeout`, inside `fn_company_connectivity_register`,
`fn_kernel_trigger_state` and `fn_phase_c_step_event` respectively.
**UNMEASURED**: the session `statement_timeout` actually applied to the cron role — it has not been read
in this pass, and the seat must read it rather than assume the Supabase default.

**M7 — Parity.** `parity = |repo_functions ∩ deployed_functions| ÷ |repo_functions|`.
Measured: 206 directories in `supabase/functions`, 204 `edge_function` rows in `phase_c_component`,
**70** rows in `qd_deploy_src`. Those three numbers should agree and do not. The gap
(206 − 70 = **136 functions with no mirrored source row**) is a measured finding, not a model output.

**M8 — Reveal-path arithmetic (the only business model this seat owns).**
`reveal_fee = round(selected_quote_value × pricing_config.standard_reveal_rate, 2)` with
`standard_reveal_rate = 0.0300` and `standard_reveal_cap = 99999999` (i.e. effectively uncapped).
Refund on non-response returns the **full** fee. Supplier then owes `fee + 250 + 0.09·fee·(days/365)`
(`decision_policy.refund_admin_fee_aed = 250`, `refund_late_fee_annual_pct = 9`).
**Every constant here is read from `pricing_config` and `decision_policy` at call time. None may be
hard-coded.** UNMEASURED: `selected_quote_value` — `quotes` has 0 rows.

### 3. Reasoning procedures

**Type 1 — which routine implements this.**
(a) Lexical: `pg_proc.proname ILIKE` and `prosrc ILIKE` over 1387 routines. (b) Semantic: cosine on
`ops_knowledge.embedding_gte` restricted to `dept_key in ('product_eng','it','engineering')` (84 + 573 + 141
rows). (c) Both must return the same routine family or the seat reports *both* candidates and refuses to
pick. (d) Confirm with `kernel_routine_ownership.source_file` — 617 routines name their canonical file.
(e) If `ownership_class = 'HISTORICAL_APPLICATION'` (335 routines), warn: the file exists but is outside the
manifest, so editing it does not make it canonical.
**Refuses when**: neither signal clears its floor, or the routine's ownership row is missing entirely.

**Type 4/5 — the manifest procedure.**
(a) `select pg_get_functiondef(oid) from pg_proc where proname = $1` — **every** row, not the first.
(b) Count them (M3). (c) Write ONE file restating all of them, each terminated with `;`. (d) Dry-run
`node scripts/apply_sql.mjs <file>`; then apply with `--apply --ddl`. (e) `grep -c` the MANIFEST — remember
`grep -c` returning 0 exits non-zero, so it must not be chained with `&&`. (f) Append the one line if absent.
(g) Write the `kernel_routine_ownership` row: `ownership_class='QUOTESDONE_APPLICATION'`,
`classified_by_rule='R4_MANIFEST_DEFINES_IT'`, `source_kind='MANIFEST'`, `source_file='scripts/sql/<file>.sql'`.
(h) Run `canonical_routine_manifest.mjs` and expect **0 problems**.
**Stops when**: step (b) disagrees with the file. That is a hard stop, not a warning.

**Type 6/15 — the SECURITY DEFINER procedure.**
(a) Is `SECURITY DEFINER` actually needed, i.e. does the caller lack a privilege the routine needs? If not,
make it `INVOKER` — 904 of 1387 routines are definer and that ratio is itself a finding.
(b) Pin `set search_path = public, pg_temp` in the definition.
(c) If this is a `CREATE` (not `CREATE OR REPLACE`), add
`revoke execute on function … from public, anon, authenticated; grant execute on function … to service_role;`
**in the same file**. `CREATE OR REPLACE` keeps the existing ACL — do **not** revoke there, or a working
grant is destroyed.
(d) Run `anon_cannot_execute_security_definer.test.mjs`.
**Evidence that this matters**: `security_events` holds 50 `anon_exposure_drift` rows, the most recent on
6 Sep 14:31, each naming `anon_executable_secdef_fns=1`.

**Type 7 — is this write idempotent.**
(a) Classify by M4. (b) If reached by the outbox or the action invoker, `NOT_IDEMPOTENT` is a reject.
(c) Convert: find the natural key, add a unique constraint, change to `on conflict … do update`.
(d) Prove it by running the handler twice inside one aborted transaction and asserting the effect count is
1, not 2 — the aborted-transaction probe (write, count, `raise exception` with the counts so it rolls back)
is the estate's standard and costs nothing.

**Type 18 — throttle or defect.**
(a) Is the error text an HTTP 429? Then it is a throttle: `db.mjs` already backs off 2/4/8/16/32 s.
(b) Is it `canceling statement due to statement timeout`? Then it is M6, a batch-size problem, not a logic
problem. (c) Is it a `42703 column does not exist`? Then the seat's assumption about the schema was wrong —
read `information_schema.columns` first, always. (d) Only if none of these applies is it a defect.
This ordering exists because each of these three has been misread as a defect in this estate before.

**Type 30 — will this fit in the timeout.**
(a) Read the applied `statement_timeout` for the role. (b) Time one batch of 100. (c) `safe_batch` per M6.
(d) If the work cannot be split (a single aggregate over 2.6M `kb_chunks` rows), the answer is not a bigger
timeout — it is a materialised snapshot table refreshed on its own cadence.
**Refuses when**: the timeout cannot be read. Assuming it is the defect.

**Type 32 — what does this do when the input is absent.**
(a) Enumerate the routine's inputs. (b) For each, write the three cases: present-and-valid,
present-and-invalid, absent. (c) Check the guard fires on case 2 and case 3 *differently* — an estate lesson:
a guard whose condition cannot occur is dead, and one that cannot *not* fire is noise.
(d) Prove both with a check that is red before the fix.

### 4. Judgement rules

| Condition | Verdict | Reason |
|---|---|---|
| `pg_proc` shows N overloads and the file defines fewer | **stop, do not apply** | The last manifest file is canonical for all overloads; a partial file drops the rest |
| New SQL file with no MANIFEST line | **not done** | `canonical_routines` fails and the whole battery goes red on a correct change |
| `CREATE` of a `SECURITY DEFINER` function without a `REVOKE … FROM PUBLIC` in the same file | **reject** | Default grant is PUBLIC. 50 `anon_exposure_drift` events on file |
| `CREATE OR REPLACE` with a `REVOKE` in the same file | **reject** | Replace keeps the ACL; revoking there destroys a working grant |
| A definer routine with no pinned `search_path` | **reject** | Privilege escalation primitive |
| A handler reachable by the outbox and classified `NOT_IDEMPOTENT` | **reject** | At-least-once delivery is the estate's contract |
| A constant from `pricing_config` hard-coded in a routine | **reject even though it works** | 3.00% must have exactly one source; a second one is a future contradiction the founder will find |
| A destructive change with no undo path | **reject** | 28,596 `undo_log` rows say the estate expects one |
| Batch job whose worst-case row count is unbounded | **reject** | Three measured cron timeouts in seven days |
| Edge function deployed with no `phase_c_component` row | **not done** | An unregistered surface is invisible to the exposure board |
| A function importing `_shared/llm.ts` and not in the credential migration list | **reject** | It bypasses the paid-inference gate, which is the founder's hard rule |
| A fix that is only in the mirror/export, not in production | **not a fix** | Mirror gates are retired; production proves properties |
| A test written after the fix that has never been red | **not a test** | It proves only that somebody typed it |
| Query fixed by adding an index on a 2.6M-row table during business hours without `CONCURRENTLY` | **reject even though it is faster** | The lock is the outage |
| An error the seat has not classified as throttle / timeout / schema-assumption | **do not call it a defect yet** | All three have been misdiagnosed here before |
| A capability that is finished but has no caller | **record it as `DEFERRED_RUNTIME_IMPLEMENTATION`, do not delete** | 119 rows already sit in that state deliberately |
| Any run-time call to a paid model on the customer path | **reject** | Founder's constraint, stated twice |

### 5. Technical knowledge

- **SQL/DDL**: PostgreSQL 17.6 lock levels per `ALTER` form; `CREATE INDEX CONCURRENTLY`;
  `ADD CONSTRAINT NOT VALID` + `VALIDATE`; `on conflict` semantics; generated columns; partial and
  expression indexes; `pg_trgm` GIN for lexical match; `vector 0.8.0` HNSW/IVFFlat and the 384-dim
  `gte-small` shape.
- **Routine mechanics**: `SECURITY DEFINER` vs `INVOKER`, the default PUBLIC grant, `search_path` pinning,
  `pg_get_functiondef`, overload identity via `pg_get_function_identity_arguments`, and the fact that
  `CREATE OR REPLACE` preserves ACLs while `DROP`+`CREATE` does not.
- **Trigger mechanics**: firing order is alphabetical by trigger name — the estate encodes order in name
  prefixes — and a `BEFORE` trigger cannot read what a later trigger writes
  (`before_triggers_do_not_read_what_a_later_one_writes.test.mjs` exists for this).
- **Edge functions**: Deno; `_shared/` for shared modules; `deno check` as the type gate;
  `scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production <slug>`;
  `scripts/verify_deploy_parity.mjs --all`; every deployed function needs a
  `phase_c_component` row of the form `edge:<slug>`; `_shared/llm.ts` importers must be in the audit-95
  credential migration list.
- **The repository workflow**: never `git add -A`; stage explicit paths; a hook rewrites shell redirect
  targets so files must never be built with `>`; write scripts with the Write tool rather than inline
  `node -e`; `graphify update .` after code changes.
- **The DB client**: `scripts/phase_c/lib/db.mjs`, one transaction per call, 429 backoff at 2/4/8/16/32 s,
  `process.exit(0)` at the end of every script.
- **The aborted-transaction probe**: do the write, count the effect, `raise exception` with the counts so
  the transaction rolls back. This is how a write is proven without leaving a row behind.
- **Must be stored so the seat never asks**: the lock-class table (M2); the manifest procedure verbatim;
  the SECDEF revoke/replace rule; the fixture convention (`ZZ DEMO — …`, `@example.invalid`, inside
  `withRun`/`rehearsal_window`); the deploy command; the check names that cover each of these.
- **Does not exist**: a per-table write-rate history; a `pg_stat_statements` snapshot table; a mapping from
  check to the objects it covers.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source | Ingest or cite |
|---|---|---|---|
| Relational theory | Normal forms, functional dependency, constraint-as-truth | PostgreSQL official documentation (PostgreSQL Licence) | **Ingest** |
| Concurrency | MVCC, isolation levels, lock compatibility matrix | PostgreSQL docs ch. 13 | **Ingest** |
| Query optimisation | Cost model, join methods, selectivity estimation | PostgreSQL docs ch. 14 + `EXPLAIN` output semantics | **Ingest** |
| Distributed messaging | At-least-once, idempotency keys, the outbox pattern | IETF RFC 9110; public outbox-pattern write-ups under permissive licences | **Ingest** |
| API design | Resource shapes, status semantics, versioning | IETF RFC 9110 / RFC 9457 (problem details) | **Ingest** |
| Secure coding | Injection, authz-at-the-boundary, least privilege | OWASP ASVS and Top 10 (Creative Commons) | **Ingest** |
| Cloud service design | The AWS Developer-Associate syllabus areas this seat is certified against | AWS published documentation | Cite |
| Type systems / runtime | Deno permissions model, ES modules | Deno official documentation (MIT) | **Ingest** |

**Certifications on file**: AWS Certified Developer – Associate (pass mark 72.00, rank 1; syllabus areas
*Development with AWS Services, Security, Deployment, Troubleshooting and Optimization*) and
**EDB PostgreSQL 12+ Professional** (70.00, rank 2; syllabus areas *Architecture and Configuration, SQL and
Query Tuning, Backup and Recovery, Replication and High Availability, Security and Roles, Monitoring and
Maintenance, Vacuum and Bloat Management*).
**Syllabus areas failed: does not exist — this seat has never sat either exam.** Given that the company runs
on PostgreSQL and this seat owns 1387 routines, the EDB exam is the one that should be sat first, and
*Vacuum and Bloat Management* is the syllabus area with no corresponding stored knowledge at all: the seat's
seven `agent_knowledge` rows are one role description and six `exam:` fragments.

### 7. Corporate knowledge

- **The four hard rules** (`fn_company_hard_rules()`), and specifically that the 3.00% rate, the AED 1000
  registration fee, the 1000 free registrations, the 5/3-working-day ladder, the AED 250 admin fee, the 9%
  interest and the 10-supplier category threshold all live in `pricing_config` and `decision_policy` — never
  in code.
- **Its own authority**: `code_selfheal` and `incident_fix` are **advisory** for this seat. It prepares;
  `cto` executes. It may run `health_report`, `recommend`, `security_review` and `uptime_verify`
  autonomously at `threshold_aed = 0`.
- **Workflows it owns**: schema and routine change (the manifest procedure), edge-function build and
  deploy, API shape, the reveal-fee arithmetic, backfills. It appears by name in `os_incidents`
  resolutions — e.g. incident 61202, *"step 5 'Fix and verify the metric recovers' completed by
  backend_engineer in the incident_response workflow"*.
- **Hands to**: `cto` (execution of advisory actions, architecture calls), `security` (SECDEF and RLS
  review), `qa_manager` (the failing-first check), `it` (cron scheduling and restarts).
- **History it must not forget**: the retired shared `legacy.shared` credential (`internal_credential` id 1,
  scope `ai_gateway`/`postiz_publish`/`knowledge_exam`, 388 uses, retired 3 Sep 2026) and the per-function
  contexts that replaced it; the manifest's last-file-wins rule; the three cron statement timeouts of
  5–7 Sep; the 42703 schema-assumption errors that this document itself hit four times while being written.
- **Its own improvement plan on file**: *"Your department has had 1 deliverable(s) returned by review
  recently… grounded_in_this_business (minor): The work order says: Be concrete and specific. Open findings
  against your department: Employee has no measurable KPI; Agent failing repeatedly."* The "no measurable
  KPI" finding is accurate: this seat's single KPI is *Platform availability*, which it does not control —
  `it` does.

### 8. One-year plan

**Objective.** Make every change to the 628 tables and 1387 routines provably safe, reversible and
idempotent, and close the parity gap between the repository and production.

**This seat's slice of AED 1,000,000: AED 0 direct.** Its contribution is that the reveal path computes the
right number and never double-charges. The arithmetic it owns —
`reveal_fee = selected_quote_value × 0.0300` — is correct today and has been exercised **zero** times
(`transactions = 0`).

**Metrics it should own** (its current single KPI measures something it does not control):
1. **Manifest coverage** — `QUOTESDONE_APPLICATION/R4` rows ÷ application routines. Measured today:
   617 ÷ 952 = **64.8%**. Target 90% by Q4. Measurable now, no new instrument needed.
2. **Deploy parity** — mirrored functions ÷ repository functions. Measured today: 70 ÷ 206 = **34.0%**.
   Target 100%. Measurable now.
3. **Idempotency coverage of outbox-reachable handlers** — **UNMEASURED**; needs the M4 classification
   stored as a column on `phase_c_component`. That column does not exist and building it is Q1 work.

**Quarterly milestones.**
- **Q1.** Sit the EDB PostgreSQL Professional exam (the one that matters most and has never been attempted).
  Add an `idempotency_class` column to `phase_c_component` and classify all 204 edge and 232 cron
  components. Fix the three timing-out cron paths by batching (`fn_company_connectivity_register`,
  `fn_kernel_trigger_state`, `fn_phase_c_step_event`).
- **Q2.** Close deploy parity: mirror the 136 unmirrored functions into `qd_deploy_src` so the reader-set
  question (taxonomy #20) becomes answerable. Build the lock-class table (M2) as stored knowledge.
- **Q3.** Take `HISTORICAL_APPLICATION` (335 routines) down by bringing the load-bearing ones into the
  manifest. Rank them by `pg_stat_statements` total time, not alphabetically.
- **Q4.** Reduce `SECURITY DEFINER` count where `INVOKER` suffices. 904 of 1387 is not a design, it is an
  accumulation.

**Capacity check.** All four quarters are mechanical, countable work over objects that already exist and
are already enumerated — 136 mirrors, 436 classifications, 335 ownership rows. `max_open_tasks = 50`. This
is achievable by one seat, and none of it depends on demand. **But none of it produces revenue either**;
this seat's plan is entirely downside-protection, and that is the honest statement.

**Dependencies.** `cto` (executes this seat's advisory actions — every `incident_fix` and `code_selfheal`
needs the head), `qa_manager` (the failing-first check for each change), `security` (SECDEF and RLS design),
`it` (cron rescheduling). **Blocking risk**: with `code_selfheal` and `incident_fix` both advisory, this
seat cannot close an incident alone; if `cto` is saturated, the fix queue stalls behind one seat.

**Is the slice achievable?** Yes, and it is measurable from day one on two of three metrics. The third
(idempotency coverage) is not achievable until the column exists, which is why that is stated as a build
rather than a target.

### 9. What this seat cannot do without a model

1. **Writing the SQL or TypeScript.** Everything above decides *what* must change and *how it must be
   shaped*; a human or a model writes the body.
2. **Reading an unstructured bug report and turning it into a predicate.** The seat can refuse and ask for a
   predicate; it cannot infer one from prose.
3. **Naming a new abstraction well.** Trivial, and worth stating: the seat can detect the third duplicate
   deterministically; it cannot invent the name for the routine that replaces them.

---

## it — IT Operations & Site Reliability Engineer

"IT/SRE — platform uptime and safe change." `routing_tier=director`, reports to `cto`. Authority:
`health_report`, `recommend`, `security_review`, `uptime_verify` **autonomous** at `threshold_aed = 1000`;
`code_selfheal` and `incident_fix` **advisory**. Two KPIs, both measured: *Agent run reliability* target
97%, actual **98.23%**; *Platform availability* target 99.5%, actual **100.00%** (both stamped
7 Sep 03:30 UTC). This is the seat with the deepest stored knowledge in the department — **35
`agent_knowledge` rows**, including `platform_uptime_safe_change`, `release_discipline`,
`incident_response_continuity`, `Adopted SLOs (operating instance)` and `Professional standard (Google SRE)`.
It is also the `owner_role` on **eleven** `founder_mail_policy` kinds — more than any other seat in the company.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Is the platform up right now? | diagnosis | continuous | `red_view_alerter`, `ceo` | `platform_down` and `uptime_alert` are two of the five kinds that may email the founder; a false one burns the channel |
| 2 | Is this cron job silent, failing, or working and quiet? | diagnosis | 15 min | `red_view_alerter` | Zero cannot tell a dead guard from an idle system; 134 active jobs |
| 3 | Which of the 681 errored runs in 30 days share one cause? | diagnosis | weekly | `cto` | Treating 681 rows as 681 incidents means none gets fixed |
| 4 | Should this job's cadence change? | allocation | monthly | `cto` | 134 active jobs on one Postgres; cadence is the throughput lever |
| 5 | Is the backup restorable, not merely present? | gate | daily | `security`, founder | 26 of 193 backups in 90 days are `error`; `backup_failed_after_retry` is founder-emailable |
| 6 | Has a backup been missed two days running? | escalation | daily | founder | This is the exact trigger for the only backup kind with `allowed_to_email = true` |
| 7 | What is the recovery time objective, and have we ever measured it? | forecast | quarterly | founder, `cto` | `company_goals.rto` target 30 min carries `NO INSTRUMENT EXISTS` |
| 8 | Is the 393 ms mean latency degrading? | forecast | weekly | `cto` | 1.75% headroom to the 400 ms goal |
| 9 | Which edge function has gone silent? | diagnosis | 15 min | `red_view_alerter` | 1,833 `STALE` probes across 23 functions in 30 days |
| 10 | Is this `STALE` verdict a dead function or a function with nothing to do? | diagnosis | weekly | `cto` | The commonest false alarm in this estate |
| 11 | Should I restart this job, or is restarting it the incident? | gate | weekly | `cto` | A restart loop hides the cause and burns the founder's alert budget |
| 12 | Does this cron job have a `cron_registry` row and a `phase_d_committed_scenario_cron` row? | gate | per new job | `qa_manager` | 230 registry rows against 235 jobs — five jobs are unregistered |
| 13 | Is this job wrapped by the kernel? | gate | per new job | `cto` | Unwrapped jobs do not trace; 57,612 `phase_c_trace` rows are the record |
| 14 | Which credential does this function use, and when does it rotate? | gate | monthly | `security` | 87 `internal_credential` rows, 7,801 audit rows; rotation is on a 30-day-ahead cron |
| 15 | Is this alert new, or the same signature we already raised? | gate | 15 min | `red_view_alerter` | `alert_signature` holds 46 rows; dedupe is the difference between a channel and a spam folder |
| 16 | What is the statement timeout on the cron role? | diagnosis | per timeout | `backend_engineer` | Three timeouts in seven days and the applied value has not been read |
| 17 | Is `pg_net` backing up? | diagnosis | daily | `backend_engineer` | The dispatch/collect pair depends on it; a backed-up queue looks like a dead handler |
| 18 | Is this a capacity problem or a query problem? | diagnosis | monthly | `backend_engineer` | Adding capacity to a bad query buys a month |
| 19 | Which table is growing fastest and will it matter? | forecast | monthly | `cto` | `kb_chunks` at 2,681,290 rows dominates everything else by 44× |
| 20 | Is the email backlog stuck? | diagnosis | 30 min | `customer_experience` | 1,034 `integrity_violation` events, every one of them `email_backlog_stuck` |
| 21 | Do we have enough evidence to declare an incident resolved? | gate | per incident | `cto` | 61 `os_incidents`; a premature resolve is a second incident |
| 22 | Who owns this incident? | allocation | per incident | `cto` | `os_incidents.owner` is a real column; unowned incidents sit |
| 23 | Is this incident past its SLA? | escalation | daily | `cto` | `os_incident_past_sla` routes to this seat, **not** the founder |
| 24 | Should this alert reach the founder or a role? | gate | per alert | `red_view_alerter` | This seat is `owner_role` on 11 kinds; only 2 of them (`platform_down`, `uptime_alert`) may email him |
| 25 | Is the scheduler itself alive? | diagnosis | 15 min | founder | `ops_watch/watchdog_silent` fired **critical** once, on 2 Sep. If pg_cron is dead nothing else reports |
| 26 | Is a deploy in flight? | gate | per deploy | `backend_engineer` | `deploy_state.dirty` is one row and it is the interlock |
| 27 | What changed just before this degradation? | diagnosis | per incident | `cto` | `os_audit_log` holds 28,001 rows; correlation by time window is arithmetic |
| 28 | Is this cost line growing? | forecast | monthly | `cfo` | AED 154.22 over 30 days; the last 7 days are AED 0.00 |
| 29 | Do we need this extension? | gate | rare | `security`, `cto` | Nine extensions; each constrains platform upgrades |
| 30 | Is the DR drill's own staging table clean? | gate | per drill | `qa_manager` | `dr_drill_clears_its_own_staging_table.test.mjs` exists because it did not once |
| 31 | Is a runner past its own cadence? | diagnosis | hourly | `chief_operating_officer` | 38 `runner_silent` warns in 30 days; `runner_silence` is the COO's kind, not the founder's |
| 32 | Is this toil, and can it be a cron? | craft | monthly | `cto` | The SRE test: anything manual, repetitive and automatable is a job waiting to be written |

### 2. Domain logic (the models this seat reasons with)

**M1 — Availability.** `availability = ok ÷ total` on
`health_checks where check_kind='http' and created_at > now() - interval '30 days'`.
Measured: **1064 ÷ 1064 = 100.00%** against a 99.5% KPI and a 99.95% company goal.
Error budget for the goal over 30 days = `0.0005 × 30 × 24 × 60` = **21.6 minutes**; consumed: **0**.

**M2 — Run reliability and its window trap.**
`reliability = 1 − errors ÷ total` on `agent_runs`.
7 days: **98.23%** (KPI actual). 30 days: 1 − 681 ÷ 22,563 = **96.98%**.
Both are correct. **The rule is that the seat always states the window**, because a 30-day total is not a
run rate and the two numbers straddle the 97% target in opposite directions.

**M3 — Silence detection.** For a job `j`: `silent_minutes = now() − last_success(j)`;
`expected_interval(j)` parsed from `cron.job.schedule`.
`verdict = SILENT if silent_minutes > 3 × expected_interval else ALIVE`.
For edge functions the estate already implements this as `edge_health_probe` (`fn_key`, `last_beat_at`,
`silent_minutes`, `verdict`), which recorded **27,922 `ALIVE` across 32 functions and 1,833 `STALE` across
23 functions** in 30 days.
**The known false positive**: a function that is genuinely idle reads identically to a dead one. The
disambiguator is whether anything *should* have invoked it — i.e. whether its trigger source produced an
event in the window. That join is available (`phase_c_event_outbox`, `kernel_trigger_inbox`) but
**is not currently part of the probe**, which is why `STALE` counts are high and largely benign.

**M4 — Failure clustering.** Group `agent_runs where status='error'` by
`(agent, left(note, 60))` and rank by count. 681 errors in 30 days collapse to a small number of
signatures; the estate already does the equivalent for alerts in `alert_signature` (46 rows, watchers
`failed_runs` 30, `founder_mail` 15, `resilience` 2).
**UNMEASURED**: `agent_runs.note` is free text with no error-class column, so clustering is by prefix, which
is a heuristic. A `failure_class` column does not exist.

**M5 — Backup health.** `success_rate = done ÷ (done + error)` over `doc_backups` in 90 days
= 167 ÷ 193 = **86.53%** against a 100% goal. Consecutive-failure counter =
`count of trailing error rows ordered by created_at desc`. **Rule**: 1 failure → `backup_alert`
(owner `it_operations_engineer`, not emailable); 2 consecutive → `backup_failed_after_retry`
(**emailable**). Measured: last `error` was 15 Jul 2026, so the consecutive counter is **0** today, yet
`security_events` still carried a `backup_overdue` high at 08:00 on 7 Sep — meaning *overdue* and *failed*
are two different conditions and the seat must not conflate them.

**M6 — Restart decision.** `restart_is_safe = idempotent(handler) AND consecutive_restarts < 3 AND
cause_is_transient`. `cause_is_transient` is a lookup over the error text: `429`, `statement timeout`,
`connection reset` → transient; `column does not exist`, `permission denied`, `null value in column` →
not transient, and restarting is the wrong action.
**Rule**: after 3 restarts in 24 h the job is disabled and an incident is opened; restarting a
non-idempotent handler is never safe.

**M7 — Capacity headroom.** `growth_rate(table) = Δn_live_tup ÷ Δdays`.
**UNMEASURED**: this estate has no `pg_stat_user_tables` snapshot history, so growth is not computable
today — only the current sizes are (`kb_chunks` 2,681,290; `edge_health_probe` 60,562; `phase_c_trace`
57,612; `phase_c_system_execution` 56,526; `agent_runs` 40,381; `undo_log` 28,596; `os_audit_log` 28,001).
Building that snapshot is the seat's Q1 work.

**M8 — RTO.** `rto = restore_complete_at − failure_detected_at`. The goal is 30 minutes
(`company_goals.rto`). **UNMEASURED and never measured** — `no_measure_reason` is
*"NO INSTRUMENT EXISTS."* The `dr_drill` edge function exists and has its own test; instrumenting it to
write a timed row is the smallest change that makes this goal real.

**M9 — Alert routing (a lookup, not a judgement).** Of the 60 `founder_mail_policy` rows, this seat is
`owner_role` on: `agent_silence`, `backup_alert`, `backup_failed_after_retry`, `incident`, `ops_alert`,
`os_incident`, `os_incident_past_sla`, `platform_down`, `red_view`, `resilience`, `resilience_alert`,
`scheduled_runs_failed`, `smoke_alert`, `uptime_alert`. Exactly **three** of those carry
`allowed_to_email = true`: `backup_failed_after_retry`, `platform_down`, `uptime_alert`. Every other one
routes to this seat.

### 3. Reasoning procedures

**Type 1/25 — is the platform up.**
(a) Read `health_checks` in the last 30 minutes; if any `check_kind='http'` row has `ok=false`, that is a
candidate outage. (b) Cross-check `fn_cron_liveness()` — if pg_cron itself is dead, the absence of failing
health rows is meaningless, because nothing is writing them. This is the `zero-cannot-tell-a-dead-guard-from-an-idle-system`
trap and it fired for real on 2 Sep 2026 (`ops_watch/watchdog_silent`, severity **critical**, one row).
(c) If both the site and the scheduler are down → `platform_down`, which **may** email the founder.
(d) If only the site → `uptime_alert`, also emailable. (e) If neither → `health_alert`, which is the CTO's
and never his.
**Refuses when**: the last `health_checks` row is older than 30 minutes — that means the prober is down and
the honest answer is "I cannot tell", not "we are up".

**Type 2/9/10 — silent, failing, or quiet.**
(a) Compute M3 per job/function. (b) For each `STALE`, ask whether an event that should have invoked it
exists in the window. (c) `STALE + events waiting` → **broken**, open an incident.
(d) `STALE + no events` → **idle**, record and do not alert. (e) `ALIVE + errors` → failing, cluster by M4
before acting. (f) Dedupe against `alert_signature` before raising anything: same `(watcher, signature)`
inside the cooldown is not a new alert.
**Stops when**: step (b)'s event source cannot be identified — that is a finding about the probe, not
about the function.

**Type 3 — 681 errors, how many causes.**
(a) Cluster by M4. (b) Rank by count × (1 if the job is on the revenue path else 0.3). (c) Take the top
three signatures only. (d) For each, produce: first seen, last seen, jobs affected, the exact error text,
and whether it is transient by M6's lookup. (e) The deliverable is three named causes, not 681 rows.
Measured example this window: `action_invoke_rpc_5min` 4, `red_view_alert_15min` 3, and three jobs at 1
each — five signatures, of which the top two are 70% of the failures.

**Type 5/6 — backup restorable.**
(a) `doc_backups` last row: status and age. (b) Consecutive-error count. (c) If ≥ 2 → raise
`backup_failed_after_retry`, which is emailable to the founder. (d) If 1 → `backup_alert` to this seat.
(e) **Presence is not restorability**: the seat must also assert that a restore has been *performed* inside
the retention window. `dr_drill` exists; a timed restore row **does not**. Until it does, the honest verdict
is "backups are being written; restorability is unproven", and this document says so.

**Type 11 — restart or investigate.**
(a) M6. (b) If not transient → do not restart; open an incident with `owner` set by the failing object's
kind (schema → `backend_engineer`, credential → `security`, scheduling → this seat).
(c) If transient and `consecutive_restarts < 3` → restart, and record it in `os_audit_log`.
(d) At the third restart in 24 h the job is disabled and escalated. **A restart is a treatment; three
restarts is a diagnosis.**

**Type 16/17 — timeouts and the net queue.**
(a) Read the applied `statement_timeout` for the cron role — *read it, do not assume the platform default*.
(b) For each timing-out call, take the SQL from `cron.job_run_details.return_message`; the three measured
this week name `fn_company_connectivity_register`, `fn_kernel_trigger_state` and `fn_phase_c_step_event`.
(c) Hand the batch-sizing arithmetic (backend M6) to `backend_engineer` — **this seat does not change the
routine**, its authority on `code_selfheal` is advisory.
(d) Meanwhile reduce the job's cadence so the failure rate falls while the fix is queued, and say plainly
that this is mitigation, not repair.

**Type 24 — founder or role.**
(a) `select allowed_to_email, owner_role from founder_mail_policy where kind = $1`.
(b) `true` → `fn_notify_founder(...)` with `p_kind`. (c) `false` → `fn_founder_mail_route(...)`, one owned
`org_tasks` row. (d) No policy row → the kind is unclassified and belongs to `chief_of_staff`; **do not
invent a policy row to make a notification send**.

**Type 32 — is this toil.**
(a) Is the task manual, repetitive, automatable, tactical and devoid of enduring value? All five → it is
toil. (b) Estimate frequency × minutes. (c) If `annual_minutes > 240`, write the cron. (d) Register it:
`cron.schedule`, then `fn_kernel_wrap_and_enable_cron(jobid, 'it_operations_engineer', 'product_eng',
'routine_operational_decision')`, a `cron_registry` row, a `phase_d_committed_scenario_cron` row, and one
`fn_kernel_cron_exec(jobid)` so it traces. **Five of the 235 jobs have no `cron_registry` row today
(230 rows); that gap is this seat's.**

### 4. Judgement rules

| Condition | Verdict | Reason |
|---|---|---|
| Last `health_checks` row older than 30 minutes | **"I cannot tell", never "we are up"** | The prober being down is not evidence of health |
| pg_cron reports dead | **that is the incident, whatever else is quiet** | Nothing else can report while the scheduler is down; it happened 2 Sep |
| A job is `STALE` and no event was waiting for it | **do not alert** | Idle and dead read identically; only the waiting work distinguishes them |
| Three restarts of the same job in 24 h | **disable and escalate** | A restart is a treatment; the third one is the diagnosis |
| Restarting a `NOT_IDEMPOTENT` handler | **never** | At-least-once delivery will double the effect |
| One backup error | `backup_alert` **to this seat** | Not emailable; one miss is a rerun |
| Two consecutive backup errors | `backup_failed_after_retry` **to the founder** | There may be no restorable backup; this is one of three emailable kinds this seat owns |
| Backups present but no restore ever performed | **report "restorability unproven"** | Presence is not restorability. This is true today |
| A kind with `allowed_to_email = false` | **never reaches the founder, no matter how bad it is** | 11 of this seat's 14 kinds are false. Severity does not override policy |
| A kind with no `founder_mail_policy` row | **route to `chief_of_staff` as unclassified** | Do not create a policy row to make a send succeed |
| An alert whose `(watcher, signature)` is already open | **suppress** | `alert_signature` exists so the channel stays credible |
| A cron job with no `cron_registry` row | **not done** | Five such jobs exist today |
| A cron job not wrapped by `fn_kernel_wrap_and_enable_cron` | **not done** | Unwrapped jobs do not trace |
| A latency or availability claim without its window | **reject the claim** | 96.98% over 30 days and 98.23% over 7 days are both true and straddle the target |
| Cadence reduced to hide a failing job | **allowed only as declared mitigation, never as the fix** | And it must be said out loud in the same report |
| Toil above 240 minutes/year left manual | **write the cron** | The SRE test, and this seat is certified against it |
| A capacity claim with no growth history | **say "not computable"** | No `pg_stat_user_tables` snapshot exists |

### 5. Technical knowledge

- **pg_cron 1.6.4** — `cron.job` (235 rows / 134 active), `cron.job_run_details` and its `status`/
  `return_message`; jobs run under a role with its own `statement_timeout`, and a cancelled statement is
  recorded as a failure, not as a skip. The kernel wrapper
  `fn_kernel_wrap_and_enable_cron(jobid, role, dept, authority)` and the single-shot
  `fn_kernel_cron_exec(jobid)`.
- **pg_net 0.20.3** — asynchronous HTTP; the response must be collected in a later tick, which is why the
  action invoker is three jobs (`action_invoke_dispatch_5min`, `action_invoke_collect_5min`,
  `action_invoke_rpc_5min`) scheduled to interleave so they never contend for the same rows.
- **The alert plumbing** — `fn_exception_alerts()`, `fn_emit_metric_alerts()`, `fn_alert_severe(p_level)`,
  `fn_notify_founder(p_event, p_detail, p_level, p_kind, p_dedupe_key, p_owner_agent)`,
  `fn_founder_mail_route(p_kind, p_subject, p_body, p_level, p_owner_agent)`; `founder_alerts`
  (`level, event, detail, channel, dedupe_key`), `alert_signature` (`watcher, signature, first_seen_at,
  last_seen_at, last_alerted_at, seen_count, resolved_at`), `alert_watermark`.
- **Health surfaces** — `health_checks` (`check_kind, target, ok, status_code, latency_ms`),
  `health_state`, `edge_health_probe` (`fn_key, last_beat_at, silent_minutes, verdict`),
  `fn_cron_liveness()`, `fn_edge_health_scan()`, `fn_kernel_all_boards()`.
- **Incident record** — `os_incidents` (`title, kind, severity, status, owner, opened_by, due_at,
  org_task_id, escalated_at, resolution`). Incidents are opened by `system.action_dispatcher@quotesdone.local`
  through the `incident_response` workflow and resolved with a named step and actor.
- **Credentials** — `internal_credential` (87 rows: `context`, `label`, `secret_hash`, `scope[]`,
  `is_legacy`, `expires_at`, `rotated_at`, `last_used_at`, `use_count`), `internal_credential_audit`
  (7,801 rows: `allowed`, `reason`, `function_name`). Rotation runs 30 days ahead on its own cron.
  `app_secrets` is a flat `(key, value, updated_at)` table of 213 rows — **it has no scope, no owner and no
  expiry columns**, which is a real gap this seat shares with `security`.
- **Backups** — `doc_backups`, the `dropbox_backup` / `backup` edge functions, `dr_drill`.
- **Must be stored so the seat never asks**: the 14 `founder_mail_policy` kinds it owns and which three are
  emailable; the transient/non-transient error lookup; the cron registration five-step; the SLO arithmetic
  and its error budgets; the fact that a 30-day total is not a run rate.
- **Does not exist**: a table-growth history; a timed restore record; a `failure_class` column on
  `agent_runs`; an events-waiting join in the silence probe.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source | Ingest or cite |
|---|---|---|---|
| Reliability engineering | SLI / SLO / error budget; toil; the four golden signals | Google's freely-published SRE material | **Cite only** (copyrighted, free to read); the arithmetic in M1–M2 is ours |
| Incident management | Incident command, severity ladders, blameless post-incident review | NIST SP 800-61r2 *Computer Security Incident Handling Guide* — US Government, public domain | **Ingest** (technical standard, not law) |
| Service management | Event, incident and problem management as distinct practices | ITIL 4 is **copyrighted (AXELOS)** — ingest only the freely published ITIL glossary definitions | Cite |
| Continuity | RTO / RPO definitions, drill discipline | ISO 22301 abstract; UAE Business Continuity guidance published by the UAE Cybersecurity Council | Cite standard, **ingest** UAE guidance |
| Linux systems | Process, filesystem, scripting, troubleshooting — the CompTIA Linux+ areas this seat is certified against | The Linux `man-pages` project (GPL-compatible) and kernel documentation | **Ingest** |
| CI/CD | Pipeline design, promotion, artefact provenance | SLSA framework (Creative Commons); OpenSSF guidance | **Ingest** |
| Observability | Metrics, logs, traces; cardinality discipline | OpenTelemetry specification (Apache 2.0) | **Ingest** |
| Queueing | Little's Law, utilisation vs latency | Published queueing-theory primers under permissive licences | **Ingest** |

**Certifications on file**: CompTIA Linux+ (pass mark 80.00, rank 1; areas *System Management, Security,
Scripting Containers and Automation, Troubleshooting*) and Google Professional Cloud DevOps Engineer
(70.00, rank 2; areas *Bootstrapping a Google Cloud Organization for DevOps, Building and Implementing
CI/CD Pipelines, Applying Site Reliability Engineering Practices, Implementing Service Monitoring
Strategies, Optimizing Service Performance, Managing Service Incidents*).
**Syllabus areas failed: does not exist — this seat has never sat either exam.** It does, uniquely in this
department, carry a stored row named *Professional standard (Google SRE)* and another named
*Adopted SLOs (operating instance)*, so the theory is present in the corpus even though the exam is not on
file. Note the Linux+ pass mark of 80.00 is the highest in the department.

### 7. Corporate knowledge

- **The four hard rules**, and in particular that this seat's uptime work exists so the paid reveal path is
  available; the reveal fee is 3.00% and every refund is the founder's decision.
- **It is the company's most-loaded alert owner**: `owner_role` on `agent_silence`, `backup_alert`,
  `backup_failed_after_retry`, `incident`, `ops_alert`, `os_incident`, `os_incident_past_sla`,
  `platform_down`, `red_view`, `resilience`, `resilience_alert`, `scheduled_runs_failed`, `smoke_alert`,
  `uptime_alert`. Three of those may email the founder; eleven may not.
- **Its authority boundary**: `code_selfheal` and `incident_fix` are **advisory** for this seat too — it may
  prepare, `cto` executes. It runs `health_report`, `uptime_verify`, `recommend` and `security_review`
  autonomously at `threshold_aed = 1000`.
- **What `code_selfheal` actually is** (re-reviewed by the founder 2 Sep 2026): it invokes the edge function
  `resilience_ping`, a **read-only** cron-liveness probe that pages the founder and force-flushes the outbox
  only when pg_cron is dead. It deploys nothing. The earlier rationale on file described a different
  function; that mismatch is a lesson this seat must keep.
- **What `incident_fix` actually is**: it invokes `os_incidents`, whose only actions are runbook reads and
  open/resolve of a tracking row. It changes no production configuration.
- **Live risk on this seat** (`risk_register` #8): *"Platform downtime"*, `operational`, medium/high, owner
  `it`, mitigation *"ai_health and uptime_check every 15 minutes"* — `open`.
- **Its improvement plan on file** names *"Employee has no measurable KPI; Agent failing repeatedly"*. The
  first is wrong for this seat — it has two measured KPIs, both green — and the finding should be corrected
  rather than carried.
- **History it must not forget**: the 2 Sep `watchdog_silent` critical; the retirement of the shared
  `legacy.shared` credential on 3 Sep after 388 uses; that `agent_runs` is a **cron log, not an employee
  log** (~276 runs/day dominated by four heartbeats — this is already in `qa_manager`'s stored knowledge and
  belongs in this seat's too).

### 8. One-year plan

**Objective.** Keep the paid path continuously available and make three currently-unproven properties
provable: restorability, recovery time, and capacity trend.

**This seat's slice of AED 1,000,000: AED 0 direct, and the sharpest downside in the department.** If the
platform is down when the first customer tries to pay a reveal, the revenue is not delayed, it is lost, and
`transactions = 0` means we have never once run that path under real load.

**Metrics it owns.**
1. **Agent run reliability** — target 97%, actual **98.23%** (7d) / 96.98% (30d). Measured, green on the
   KPI's own window.
2. **Platform availability** — target 99.5%, actual **100.00%**. Measured, green.
3. **Backup success** — `company_goals.backup_success`, target 100%, measured **86.53%** over 90 days
   (167 done / 26 error). **Red**, and the only red goal this seat owns with a working instrument.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** (i) Sit the Linux+ and Google DevOps exams. (ii) Build the
  `pg_stat_user_tables` snapshot so M7 capacity trend exists at all. (iii) Add the events-waiting join to
  the silence probe so the 1,833 `STALE` readings stop being ambiguous. (iv) Register the five cron jobs
  that have no `cron_registry` row. (v) Read and record the cron role's `statement_timeout`.
- **Q2 (Dec 2026–Feb 2027).** Instrument **RTO**: have `dr_drill` write a timed row so
  `company_goals.rto` stops carrying `NO INSTRUMENT EXISTS`. Then run a real restore and publish the number,
  whatever it is.
- **Q3 (Mar–May 2027).** Take backup success from 86.53% to 100% by fixing the class of failure the 26
  errors share — cluster them first (M4); do not fix 26 things.
- **Q4 (Jun–Aug 2027).** Latency: own the per-route table `cto` needs and drive the 393 ms mean below
  300 ms, so the 400 ms goal stops being met by 7 ms.

**Capacity check.** Two of the three metrics are already at target and require *holding*, not building.
The builds are four small tables and one join — well inside one seat's year at `max_open_tasks = 50`. The
honest constraint is different: **this seat cannot execute its own fixes.** `code_selfheal` and
`incident_fix` are advisory, so every repair queues behind `cto`. With six active seats and 2,466 open
`org_tasks` company-wide, that is the throughput risk, not the work itself.

**Dependencies.** `cto` (executes every advisory action), `backend_engineer` (batch sizing, the three
timing-out routines, schema for the new snapshot tables), `security` (credential rotation, the
`app_secrets` scope gap), `red_view_alerter` (consumes this seat's silence and health signals),
`qa_manager` (the DR drill's own test).

**Is the slice achievable?** Availability and run reliability: yes, they are green now and the work is to
keep them there while cron count grows. Backup success to 100%: yes, once the 26 errors are clustered.
**RTO: not achievable as a *target* this year, because it has never been measured once — the honest Q2
deliverable is a first measurement, not a 30-minute promise.**

### 9. What this seat cannot do without a model

1. **Reading a novel error message it has never seen and classifying it as transient or not.** The lookup
   table covers the known classes; a genuinely new failure string falls through to "unclassified → do not
   restart, open an incident", which is the safe answer but not an intelligent one.
2. **Writing the runbook prose for a new incident class.** The seat can detect, route, dedupe and escalate
   deterministically; composing a readable runbook from first principles is not arithmetic.
3. **Root-causing a degradation with no signal in any table.** If the cause is outside the estate — a
   provider's regional issue with no local symptom — no amount of stored data reaches it. The deterministic
   answer is "correlated with nothing I hold; here is the window and here is what I checked".

---

## security — Cybersecurity Engineer

"Security engineer — appsec, secrets, threats." `routing_tier=director`, reports to `cto`. Authority:
`health_report`, `recommend`, `security_review`, `uptime_verify` **autonomous** at `threshold_aed = 1000`;
`code_selfheal` and `incident_fix` **advisory**; and uniquely in this department,
**`review_block` autonomous with no threshold** — *"independent stop authority granted 14 Aug 2026: this
role may block unsafe work in its domain and may never approve work it authored."*

Its only KPI on file is *"Cybersecurity Manager — primary objective"*, metric **Platform availability**,
target 99.5%, actual 100.00%. **That is an instrument measuring the wrong subject**: this seat's single KPI
does not measure security at all, and section 8 proposes what should replace it. It is the only seat in the
department that has sat an exam, and it failed twice.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Is anything in `public` reachable by `anon` beyond the two intended surfaces? | gate | 15 min | `red_view_alerter` | 50 `anon_exposure_drift` events on file; `security_critical` is founder-emailable |
| 2 | Which `SECURITY DEFINER` function is anon-executable right now? | diagnosis | 15 min | `backend_engineer` | 904 SECDEF routines; the drift detail literally reads `anon_executable_secdef_fns=1` |
| 3 | Should this table have an RLS policy, or is deny-all correct? | craft | monthly | `cto` | 611 tables RLS-on-no-policy; a needless policy widens the surface |
| 4 | Does this new function need a per-function credential, in which context and scope? | gate | per function | `backend_engineer` | 87 `internal_credential` rows scoped by context; the shared one was retired for exactly this |
| 5 | Is a credential overdue for rotation? | gate | daily | `it` | Rotation runs 30 days ahead on cron; `expires_at` and `rotated_at` are real columns |
| 6 | Has a credential been used by a function outside its scope? | diagnosis | daily | `it` | `internal_credential_audit` holds 7,801 rows with `allowed` and `reason` |
| 7 | Is this a secret in a place secrets must not be? | gate | per change | `backend_engineer` | Never print `app_secrets.value`; a leaked token is `security_critical` |
| 8 | Do we know who owns each of the 213 `app_secrets` rows? | diagnosis | quarterly | `cto` | The table is `(key, value, updated_at)` — **no owner, no scope, no expiry column exists** |
| 9 | Is this incident a personal-data breach under UAE PDPL? | escalation | rare | `legal` | PDPL breach duties are on a statutory clock; `pdpl_requests` exists and holds 0 rows |
| 10 | Is this `SECURITY DEFINER` necessary at all? | craft | per routine | `backend_engineer` | 904 of 1387; each unnecessary one is an escalation primitive |
| 11 | Is `search_path` pinned on this definer routine? | gate | per SECDEF | `backend_engineer` | An unpinned path in a definer routine is the classic Postgres escalation |
| 12 | Does this edge function verify its webhook signature? | gate | per integration | `backend_engineer` | Stripe uses two-secret HMAC with a 600 s replay window and timing-safe compare; WhatsApp inbound **cannot yet verify** `X-Twilio-Signature` |
| 13 | Is this endpoint reachable without authentication, and should it be? | gate | per deploy | `cto` | The kernel board records `0 of 57` state-changing components reachable unauthenticated, with one recorded legal exception |
| 14 | Is `edge:pdpl_request` still the only justified unauthenticated exception? | gate | monthly | `legal` | UAE PDPL Art. 13–17 require the data-subject channel to be usable without an account; a second exception must be argued the same way |
| 15 | Does this change keep identities anonymous until reveal? | gate | per feature | `cto`, `legal` | Hard rule 4; anti-circumvention is AED 15,000 or 3× the fee |
| 16 | Is this dependency or extension safe to adopt? | gate | rare | `it` | Nine extensions; supply chain is the surface nobody inventories |
| 17 | Which of the 17 RLS policies is too permissive? | diagnosis | quarterly | `cto` | All 17 are `SELECT`; most are `os_owner_admin_read` to `authenticated` |
| 18 | Is `blog_posts`/`category_specs` anon-read still the whole of the intended public surface? | gate | 15 min | `red_view_alerter` | These two plus `brand_assets` are the anon-readable set; anything else is drift |
| 19 | Should this work be blocked? | gate | weekly | any seat | This seat holds `review_block` with **no threshold** — its stop is absolute in its domain |
| 20 | Am I about to approve work I authored? | gate | per review | `qa_manager` | The grant text forbids it explicitly; a self-approval voids the control |
| 21 | Is this alert a real exposure or a probe artefact? | diagnosis | 15 min | `red_view_alerter` | 50 drift events, all with the same one-line detail — a repeated identical signature is a suspect instrument |
| 22 | What is the blast radius if this credential leaked? | forecast | per credential | `it` | `internal_credential.scope[]` is an array; the answer is a set, not a guess |
| 23 | Does this log line contain personal data? | gate | per logging change | `legal` | PDPL; `os_audit_log` holds 28,001 rows and `security_audit_log` 2,956 |
| 24 | Is this retention period lawful and implemented? | gate | quarterly | `legal` | `retention_purge` exists as an edge function; whether it matches policy is this seat's to assert |
| 25 | Is the login path safe? | gate | per auth change | `cto` | OTP sign-in via `login_otp`/`mobile_otp`; a phone may confirm, never select — email is the identity |
| 26 | Is there a takeover primitive left in a retired surface? | diagnosis | quarterly | `cto` | "Retired 410 surfaces — dead auth-bypass and takeover primitives deliberately removed" is stored knowledge on three seats |
| 27 | Is this rate limit sufficient for this endpoint? | craft | per public endpoint | `backend_engineer` | Public endpoints with no limit are the cheapest abuse surface |
| 28 | Does this change need a threat model refresh? | craft | quarterly | `cto` | The seat holds a stored `QuotesDone threat model` row |
| 29 | Is this vendor assessment complete? | gate | per vendor | `cto`, `legal` | The seat holds a stored `Vendor security assessment checklist` |
| 30 | Is this vulnerability inside its SLA? | escalation | weekly | `it` | The seat holds a stored `Vulnerability management SLA (joint with IT)` |
| 31 | Does this security event warrant the founder? | escalation | weekly | founder | `security_incident` is **false** (owner: this seat); only `security_critical` is **true** |
| 32 | Is the 42.5% CISSP result a knowledge gap or a retrieval gap? | diagnosis | now | `cto`, `people_ops` | 13 `agent_knowledge` rows against eight CISSP domains; the answer changes what gets built |

### 2. Domain logic (the models this seat reasons with)

**M1 — Anonymity-by-construction invariant.** The estate's stated invariant: nothing in `public` is
reachable by `anon`/`authenticated` beyond `category_specs` and `blog_posts` (published), plus
`brand_assets`. The measurement is a set difference:
`drift = {objects anon/authenticated may read or execute} \ {the intended set}`.
Measured components: 628 tables all with `relrowsecurity = true`; **17** policies total, of which the
anon-granted ones are `blog_posts_public_read`, `brand_assets_public_read` and `specs readable`; the
remaining 14 are `SELECT` to `authenticated`. The recorded drift, 50 times, is
`anon_executable_secdef_fns = 1` — **one** SECURITY DEFINER function executable by anon.
**This is a set of size one and it has been open since at least 6 Sep 14:31. Finding and revoking it is the
single highest-value deterministic act available to this seat.**

**M2 — Definer-necessity score.** For each of the 904 SECDEF routines:
`needs_definer = 1 if the body touches an object the invoker role lacks privilege on, else 0`, computed by
parsing `prosrc` for object names and checking `has_table_privilege(invoker_role, obj, 'select|insert|update|delete')`.
`unnecessary_definers = count(needs_definer = 0)`.
**UNMEASURED**: this has never been run. The count of unnecessary definers **does not exist** and computing
it is a single query this seat should own.

**M3 — Credential exposure.** For credential `c`: `exposure(c) = |c.scope|` functions, weighted by whether
each is externally reachable. Measured shape: `internal_credential` 87 rows;
`cron.monitoring` scopes `ai_health`, `qa_suite`, `uptime_check` with **6,953 uses**, last 7 Sep 08:07;
`cron.agents` scopes ten functions; the retired `legacy.shared` scoped three and had 388 uses before being
retired on 3 Sep 2026.
**Rotation rule**: `due = expires_at − 30 days`. **Staleness rule**: a credential with
`last_used_at < now() − 90 days` and `active = true` should be retired, because an unused live credential is
pure surface.

**M4 — Secret inventory completeness.** `app_secrets` holds **213** rows and its columns are exactly
`(key, value, updated_at)`. There is **no owner, no scope, no expiry and no rotation column**. Therefore:
`unowned_secrets = 213`, i.e. **100%**. This is not an estimate; it follows from the schema. The seat cannot
answer "who owns this secret" for any of the 213 until three columns exist.

**M5 — Exposure of state-changing components.** From `fn_kernel_all_boards()`, board
`fn_kernel_component_exposure_state`: `state_changing_and_reachable_unauthenticated` = **0 of 57**, with
`edge:pdpl_request` excluded on a recorded legal ground (UAE PDPL Art. 13–17 require the data-subject
request channel to be usable without an account); `deferred_or_inactive_but_reachable` = 0 of 106;
`external_entry_disagrees_with_derivation` = 0 of 106. All `ok = true`.
**This board is green and should be quoted whenever someone asks whether the estate is exposed — it is the
measured answer, and it disagrees in emphasis with M1's one anon-executable function, which the board does
not cover.** Both facts must be stated together.

**M6 — Severity → routing (a lookup).** `security_events.severity ∈ {info, low, medium, high, critical}`.
Measured distribution: `anon_exposure_drift` **high** ×50, `backup_overdue` **high** ×5, `admin_login`
info ×15, `memory_lint_block` low ×2, `override_spike` medium ×1.
Routing: `critical` **or** (customer data reachable by anon **or** a secret leaked) → `security_critical`,
`allowed_to_email = true`, owner `cybersecurity_engineer` → the founder is emailed.
Everything else `high` and below → `security_incident`, `allowed_to_email = **false**`, worked by this seat.
**Note the consequence**: all 50 `anon_exposure_drift` events are `high`, not `critical`, so on the current
policy **none of them reached the founder**. Whether "one anon-executable SECDEF function" meets the
`security_critical` text *"customer data exposed to anon"* is the judgement this seat must make and record —
it turns on what that one function returns.

**M7 — Vulnerability SLA.** Stored as `Vulnerability management SLA (joint with IT)`.
`breach = now() > found_at + sla(severity)`. **UNMEASURED**: there is no `vulnerability` or
`security_finding` table in this estate — `security_events` records events, not tracked findings with a
remediation clock. `select to_regclass('public.security_finding')` returns null. **Does not exist.**

**M8 — Exam-gap diagnosis (arithmetic, and it applies to this seat itself).**
For each CISSP domain: `stored_rows(domain)` = `agent_knowledge` rows for `security` whose topic or content
matches the domain's terms, plus `ops_knowledge` rows in the security modules.
Measured: this seat holds **13** `agent_knowledge` rows for **eight** CISSP domains, and `ops_knowledge`
carries 84 rows under `dept_key='product_eng'` across six modules
(`infra-integrations-incident` 16, `kernel-and-app-controls` 16, `auth-identity-and-baseline` 15,
`database-security-rls-grants` 14, `edge-function-attack-surface` 14, `org_task_lane` 9).
Exam results: **27.50%** semantic (Domain 3 and Domain 6 both **0 of 5**) and **42.50%** lexical
(Domain 5 and Domain 6 both **1 of 5**), against a 70.00 pass mark.
**Domain 6, *Security Assessment and Testing*, was the worst area in both runs.** Cross-referencing the
module list, the estate has rows on RLS/grants, edge attack surface, auth baseline, kernel controls and
incident — and **nothing whose title names assessment or testing**. So the verdict is
*knowledge gap, not retrieval gap*, and it is a computed verdict, not an opinion.

### 3. Reasoning procedures

**Type 1/2 — the anon exposure sweep.**
(a) Enumerate objects `anon` and `authenticated` may reach: tables via `pg_policies` where the role list
includes them, and functions via `has_function_privilege('anon', oid, 'execute')` over all 1387 routines.
(b) Subtract the intended set (`category_specs`, `blog_posts` published, `brand_assets`).
(c) A non-empty remainder is drift. (d) For a **function** in the remainder, read what it returns before
classifying severity: a function returning public catalogue data is `high`; one returning any row a
customer or supplier owns is `security_critical` and reaches the founder. (e) Revoke, then re-run the sweep
in the same turn and record both counts.
**This procedure has been raising the same one-line signature 50 times without the (d) step being recorded.
The deliverable is not another alert; it is the name of the function.**

**Type 3 — policy or deny-all.**
(a) Does any application path read this table directly, i.e. not through a `SECURITY DEFINER` routine?
Evidence: `qd_deploy_src` (70 of 206 functions mirrored) and the Next.js tree.
(b) **No** → deny-all is correct; adding a policy is a regression. (c) **Yes** → design the narrowest
predicate over the table's own owner column, `for select to authenticated`, and nothing else.
(d) Never `for all`; never `using (true)`.
**Refuses when**: the reader set cannot be established — true for the 136 unmirrored functions.

**Type 4/5/6 — credential lifecycle.**
(a) New function → new credential in the narrowest `context`, `scope` = exactly the functions that need it.
(b) Never extend an existing credential's scope to cover a new function; that is how `legacy.shared`
grew to three functions and 388 uses before being retired.
(c) Daily: rows where `expires_at < now() + 30 days and rotated_at is null` → rotate.
(d) Daily: `internal_credential_audit where allowed = false` → a function tried to use a credential outside
its scope. That is either a misconfiguration or an attack, and the two are distinguished by whether the
function is one of ours.
(e) Quarterly: `active and last_used_at < now() − 90 days` → retire.

**Type 8 — who owns this secret.**
(a) Read `information_schema.columns` for `app_secrets`. (b) The answer is `(key, value, updated_at)`.
(c) **Refuse**: "ownership cannot be answered; the table has no owner column. 213 rows are unowned by
construction." (d) Open the org task to add `owner_role`, `scope`, `expires_at`.
**This is the correct output. Inferring ownership from the key name would be a guess dressed as a fact.**

**Type 9 — is this a PDPL breach.**
(a) Did personal data leave its intended audience? (b) Whose — a customer, a supplier contact, an employee?
(c) UAE Federal Decree-Law No. 45 of 2021 (PDPL) and its Executive Regulations set the notification duties;
the *legal* determination belongs to `general_counsel` (`pdpl_request` and `legal_flag` both carry
`owner_role = general_counsel`). (d) This seat's deliverable is the **factual** record: what was reachable,
by whom, from when to when, and how many rows.
**Never make the legal call in this seat.** Hand the facts over and block further exposure with
`review_block`.

**Type 19/20 — the block.**
(a) Did this seat author the work? If yes → **it may not approve it**; it may only block or abstain.
(b) Is the work in this seat's domain (authz, secrets, exposure, personal data)? If no → recommend, do not
block. (c) If in-domain and it breaches a rule in section 4 → block, cite the rule and the measured row,
and name what would unblock it. A block with no unblock condition is a veto, not a control.

**Type 21 — real exposure or probe artefact.**
(a) Is the detail identical across occurrences? 50 identical `anon_executable_secdef_fns=1` details is a
counter, not 50 discoveries. (b) Has the underlying count changed? If it has been 1 throughout, this is
**one** open finding reported 50 times. (c) Report it as one finding with a first-seen date; suppress the
repeats through `alert_signature`. (d) Then fix it.
**"A repeated identical alert is a suspect instrument" is the rule; "the instrument is suspect therefore
the finding is false" is the mistake.**

**Type 32 — knowledge gap or retrieval gap (applied to itself).**
(a) Run M8. (b) If `stored_rows(domain) = 0`, it is a knowledge gap: retraining retrieval changes nothing.
(c) If `stored_rows(domain) > 0` but the exam still failed, it is a retrieval gap: the embedding search is
not surfacing what is held. (d) Measured verdict for Domain 6: no stored module names assessment or
testing → **knowledge gap**. The remedy is ingesting OWASP ASVS verification requirements and the NIST
SP 800-115 assessment methodology, not re-running the exam.

### 4. Judgement rules

| Condition | Verdict | Reason |
|---|---|---|
| Any object outside `{category_specs, blog_posts(published), brand_assets}` reachable by `anon` | **drift; open immediately** | The invariant is anonymity-by-construction. 50 events say it is broken today |
| A `SECURITY DEFINER` function executable by `anon` | **revoke first, investigate second** | The measured drift detail names exactly this, count 1 |
| The exposed function returns any customer- or supplier-owned row | **`security_critical`; the founder is emailed** | One of only five kinds in the whole policy that may reach him from this department |
| The exposed function returns public catalogue data only | **`security_incident`, worked by this seat** | `allowed_to_email = false`; severity does not override policy |
| `CREATE` of a definer function with no `REVOKE FROM PUBLIC` in the same file | **block** | Risk #16 is `mitigating` on exactly this standing rule |
| A definer routine with no pinned `search_path` | **block** | Escalation primitive |
| A proposed RLS policy on a table only read by definer routines | **reject even though it looks like hardening** | It widens the surface for zero benefit; deny-all was correct |
| A policy written `using (true)` or `for all` | **reject** | All 17 existing policies are `SELECT`-only for a reason |
| Extending an existing credential's scope to a new function | **reject** | This is exactly how `legacy.shared` accumulated three functions and 388 uses |
| A credential unused for 90 days and still `active` | **retire** | Unused live credentials are pure surface |
| Printing or logging `app_secrets.value` | **absolute prohibition** | Lengths and booleans only |
| A second unauthenticated state-changing endpoint proposed | **reject unless it carries a legal ground as specific as `edge:pdpl_request`'s** | That exception names PDPL Art. 13–17; "convenience" is not an equivalent |
| This seat authored the work | **may block, may never approve** | Verbatim from its `review_block` grant, 14 Aug 2026 |
| A legal determination about a breach | **hand to `general_counsel`, never decide here** | `pdpl_request` and `legal_flag` are the GC's kinds |
| An identical alert detail repeated | **one finding, not N; suppress and fix** | Otherwise the channel trains everyone to ignore it |
| An exam failure in a domain with zero stored rows | **knowledge gap; ingest, do not retrain retrieval** | Domain 6 has no module naming assessment or testing |
| A control that cannot be tested | **not a control** | Domain 6 again, and it is this seat's weakest area on both attempts |

### 5. Technical knowledge

- **Postgres authorisation** — RLS enabled vs policy present (628 enabled, 17 policies, so 611 deny-all);
  `pg_policies` shape (`tablename, policyname, cmd, roles`); role hierarchy `anon` / `authenticated` /
  `service_role`; `has_function_privilege` and `has_table_privilege` as the only honest exposure test;
  the default `EXECUTE TO PUBLIC` on a newly created function; `CREATE OR REPLACE` preserving ACLs;
  `search_path` pinning; `SECURITY INVOKER` as the default that should be preferred.
- **The 17 policies, by name**: `os_owner_admin_read` on `ai_cost_log`, `customers`, `edge_health_probe`,
  `expenses`, `gl_journal`, `inquiries`, `kb_chunks`, `leads`, `org_agents`, `risk_register`,
  `transactions`, `vision_horizon`, `workflow`; `documents_customer_select` on `documents`;
  `blog_posts_public_read`, `brand_assets_public_read`, `specs readable`. All `SELECT`.
- **Credentials** — `internal_credential` (`context`, `label`, `secret_hash`, `scope[]`, `is_legacy`,
  `active`, `expires_at`, `rotated_at`, `last_used_at`, `last_function`, `use_count`) and
  `internal_credential_audit` (`allowed`, `reason`, `function_name`, `detail`). `app_secrets` is
  `(key, value, updated_at)` and nothing more.
- **Edge-function surface** — Deno permissions; the Stripe webhook's two-secret HMAC with a 600 s replay
  window and timing-safe compare (this is stored knowledge on `it` already, `exam:1096`); that
  **WhatsApp inbound cannot yet verify `X-Twilio-Signature`** (stored on `red_view_alerter` as
  `exam:1326`) — a known, recorded gap this seat owns; Twilio SMS uses API-key auth.
- **Auth** — OTP sign-in through `login_otp` and `mobile_otp`; the `qa_mint` account-creation primitive;
  the founder's rule that a phone may confirm but never select, because **email is the identity**.
- **Monitoring surfaces it owns** — `security_events` (`kind, severity, source, subject, detail`),
  `security_audit_log` (2,956 rows), `security_kpi_snapshots` (61), `security_selfaudit_snapshots` (87),
  `os_audit_log` (28,001).
- **The kernel exposure board** — `fn_kernel_all_boards()` → `fn_kernel_component_exposure_state`, with its
  five checks and the recorded `edge:pdpl_request` legal exception.
- **Must be stored so the seat never asks**: the intended anon surface as an explicit list; the SECDEF
  revoke rule with the `CREATE` vs `CREATE OR REPLACE` distinction; the severity→kind routing table;
  `security_critical` vs `security_incident` and which is emailable; the credential lifecycle thresholds
  (30-day rotation, 90-day retirement); the PDPL hand-off boundary.
- **Does not exist**: a `security_finding` / vulnerability table with a remediation clock; owner, scope or
  expiry on `app_secrets`; a computed count of unnecessary `SECURITY DEFINER` routines; any stored module
  on security assessment and testing.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source | Ingest or cite |
|---|---|---|---|
| Security management | Risk, governance, the eight CISSP domains this seat is certified against | ISO/IEC 27001 & 27002 are **copyrighted and paid** — cite clause numbers only | Cite |
| Security controls | Control families, tailoring | NIST SP 800-53r5 — public domain, technical standard | **Ingest** |
| **Assessment and testing (Domain 6 — the measured weakness)** | Test methodology, coverage, verification levels | **NIST SP 800-115** *Technical Guide to Information Security Testing and Assessment* and **OWASP ASVS** (Creative Commons) | **Ingest first — this is the gap** |
| Application security | Top 10, cheat sheets, verification requirements | OWASP (Creative Commons) | **Ingest** |
| Weakness taxonomy | CWE, CAPEC | MITRE, publicly published | **Ingest** |
| Adversary behaviour | ATT&CK tactics and techniques | MITRE ATT&CK (public) | **Ingest** |
| Zero trust / identity | Policy decision and enforcement points | NIST SP 800-207 | **Ingest** |
| Incident handling | Detection, containment, eradication, recovery | NIST SP 800-61r2 | **Ingest** |
| Cryptography use | Key lifecycle, HMAC, timing-safe comparison | NIST SP 800-57 part 1; IETF RFC 2104 (HMAC) | **Ingest** |
| **UAE law and regulation** | Personal data, breach duties, cross-border transfer | **UAE Federal Decree-Law No. 45 of 2021 (PDPL)** and its Executive Regulations; **TDRA / UAE Information Assurance Standards**; **Dubai Electronic Security Center ISR**; UAE Cybersecurity Council guidance | **Ingest — this is the governing jurisdiction** |
| Benchmarks | Hardening baselines | CIS Benchmarks (free for internal use) | Cite |

**Certifications on file**: CISSP (pass mark 70.00, rank 1; domains *Security and Risk Management; Asset
Security; Security Architecture and Engineering; Communication and Network Security; Identity and Access
Management; Security Assessment and Testing; Security Operations; Software Development Security*) and
CEH (70.00, rank 2; *Reconnaissance Techniques; System Hacking Phases and Attack Techniques; Network and
Perimeter Hacking; Web Application Hacking; Wireless and Mobile Hacking; Cloud Computing and Cryptography*).

**Syllabus areas failed — measured, twice, on 7 Sep 2026:**

| Attempt | Method | Score | Verdict | Weakest areas (correct / asked) |
|---|---|---|---|---|
| 07:46 UTC | semantic | **27.50%** | fail | D3 Architecture & Engineering **0/5**; D6 Assessment & Testing **0/5**; D1 1/5; D4 1/5; D7 1/5; D2 2/5; D5 2/5; D8 4/5 |
| 07:55 UTC | lexical | **42.50%** | fail | D5 Identity & Access Management **1/5**; D6 Assessment & Testing **1/5**; D1 2/5; D2 2/5; D4 2/5; D3 3/5; D7 3/5; D8 3/5 |

**Domain 6 is the intersection of both failures.** Domain 8 (Software Development Security) is the only
area at or above pass level on either run (4/5 then 3/5). CEH has never been attempted.

### 7. Corporate knowledge

- **The four hard rules**, and specifically hard rule 4: identities stay anonymous until the reveal and there
  is no off-platform contact before it. **This seat is the technical enforcement of a commercial rule** —
  anti-circumvention is AED 15,000 per incident or 3× the fee, whichever is higher.
- **Its two founder kinds**: `security_critical` — *"customer data exposed to anon, or a secret leaked"* —
  `allowed_to_email = **true**`, owner `cybersecurity_engineer`; and `security_incident` — *"a high-severity
  security event is the security engineer's to close; only a CRITICAL one is his"* — `allowed_to_email =
  **false**`. There is no third.
- **Its independent stop authority**, granted 14 Aug 2026: it may block unsafe work in its domain, at any
  value, and **may never approve work it authored**.
- **Live risks it owns** (`risk_register`): #7 *"Security incident or data exposure"* — security,
  medium/high, owner `cybersecurity_mgr`, `open`, mitigation *"qa_suite anon-read probes now fail closed
  after 26 Jul fix"*; #16 *"New SECURITY DEFINER functions default to anon-executable"* — high/high,
  `mitigating`, with the standing revoke rule as the mitigation.
- **Hands to**: `general_counsel` (every PDPL and legal determination), `backend_engineer` (the revoke and
  the policy), `it` (credential rotation, the vulnerability SLA it shares), `cto` (execution of its
  advisory `code_selfheal`/`incident_fix` actions).
- **History it must not forget**: the 19 Jul 2026 anonymity hotfix that the drift detail still points at
  (`docs/upgrade/hotfix-2026-07-19`); the retirement of `legacy.shared` on 3 Sep after 388 uses; the "410
  retired surfaces" that removed dead auth-bypass and takeover primitives; that the estate has **one**
  Supabase project and the old staging project was deleted on 15 Aug 2026.
- **Its own record**: it is the only seat in this department that has sat an exam, and it scored 27.50% then
  42.50% against a 70.00 pass mark. That is in the file and this plan does not soften it.

### 8. One-year plan

**Objective.** Close the anonymity invariant, make the secret and finding inventories real, and raise this
seat's own measured competence above its pass mark — starting with the domain it failed twice.

**This seat's slice of AED 1,000,000: AED 0 direct, and the largest single-event downside in the company.**
A data exposure on a UAE B2B marketplace is not a lost transaction; it is the licence, the PDPL exposure and
the anti-circumvention promise that the whole 3% model rests on. The measurable contribution is
**zero customer-data exposures**, against a `company_goals` line — `critical_incidents`, target **0**,
annual — that this department already owns and that has a working measure.

**Metrics it should own** (its current KPI measures platform availability, which is `it`'s job):
1. **Anon-reachable object count beyond the intended set** — measured today: **1** (one anon-executable
   SECDEF function, reported 50 times). Target **0**. Measurable now, no new instrument.
2. **Credentials past rotation due** — computable now from `internal_credential.expires_at`/`rotated_at`.
   Target 0.
3. **Owned secrets** — measured today **0 of 213 (0%)**, because the columns do not exist. Target 100% once
   they do. This is honestly a build before it is a metric.
4. **Open findings past SLA** — **not measurable at all today**: there is no `security_finding` table.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** (i) **Name and revoke the one anon-executable SECDEF function.** This is a single
  query and a single revoke, it has been open since at least 6 Sep, and it is the highest-value act
  available. (ii) Ingest NIST SP 800-115 and OWASP ASVS into `ops_knowledge` under a
  `security-assessment-and-testing` module — the measured Domain 6 gap. (iii) Re-sit CISSP **after** the
  ingest, and record the result whatever it is. (iv) Add `owner_role`, `scope`, `expires_at` to
  `app_secrets`.
- **Q2 (Dec 2026–Feb 2027).** Build `security_finding` with a severity clock so the stored Vulnerability
  SLA becomes enforceable rather than decorative. Run M2 and publish the count of unnecessary
  `SECURITY DEFINER` routines — it has never been computed.
- **Q3 (Mar–May 2027).** Close the WhatsApp inbound signature gap (`X-Twilio-Signature` cannot currently be
  verified) with `backend_engineer`. Deliberate RLS policy design for the tables the app genuinely reads,
  with `cto` — narrowest predicate, `SELECT` only.
- **Q4 (Jun–Aug 2027).** Sit CEH. Refresh the stored threat model against the marketplace as it will then
  be — with real suppliers, real quotes and real reveals, the threat model changes shape entirely.

**Capacity check.** Q1 is one revoke, one ingest, one exam and three columns — comfortably inside one seat's
quarter. Q2's two builds are small. **The binding constraint is not capacity, it is authority**:
`code_selfheal` and `incident_fix` are advisory here, so this seat prepares and `cto` executes. Its
`review_block`, by contrast, is autonomous and unthresholded — **this seat can stop anything in its domain
and cannot fix anything alone.** That asymmetry is deliberate and it should be stated to the founder plainly.

**Dependencies.** `cto` (executes), `backend_engineer` (writes the revoke, the columns, the signature
verification), `general_counsel` (every PDPL call), `it` (rotation cron, the shared vulnerability SLA),
`qa_manager` (a failing-first check for each control — a control that cannot be tested is not a control,
which is Domain 6 again).

**Is the slice achievable?** The anon count to zero: yes, this quarter, it is one function. Secret
ownership: yes, once three columns exist. Findings-past-SLA: **no, not until the table exists**, and the
honest Q2 deliverable is the table, not a percentage. The exam: unknown — the seat has failed twice and
the plan's claim is only that the ingest addresses the measured gap, not that the next attempt passes.

### 9. What this seat cannot do without a model

1. **Judging whether a novel data flow is a PDPL breach.** The factual record is deterministic; the legal
   characterisation is not, and it belongs to `general_counsel` regardless.
2. **Reading a new third-party vendor's security documentation and assessing it.** The stored checklist
   gives the questions; extracting the answers from an arbitrary PDF is a model task. Deterministic
   fallback: the vendor answers the checklist in a structured form, and the seat scores the form.
3. **Threat-modelling a feature that does not yet exist from a prose description.** The seat can threat-model
   *deployed* components — it holds their entry methods, actors and exposure states — but not a paragraph.
4. **Writing an exploit or a proof-of-concept.** Detection, revocation and blocking are deterministic;
   demonstrating exploitability is not, and CEH's syllabus areas are largely of this kind.

---

## qa_manager — QA & Release Management Director

"Owns the test suites and the quality gate before anything ships." `routing_tier=reviewer_auditor`, reports
to `cto`. Authority: `qa_gate` and `capability_exam` **autonomous** at `threshold_aed = 1000`;
`knowledge_acquire`, `knowledge_fill` and `knowledge_fill_gap` **advisory**. Four KPIs — one measured and
green, **three carrying `no_measure_reason`**:

| KPI | Target | Actual | Note |
|---|---|---|---|
| Quality gate pass rate before ship | 95% | **100.00%** | measured; `qa_results` 288 rows, latest 7 Sep 03:37, 15/15 |
| Regressions caught before production | 90% | — | *"NEEDS AN INSTRUMENT THAT DOES NOT EXIST."* |
| RFQ qualification accuracy | 90% | — | *"NEEDS A FIXTURE OR HOLDOUT SET THAT DOES NOT EXIST."* |
| Task classes with a measured benchmark | 80% | — | *"NEEDS AN INSTRUMENT THAT DOES NOT EXIST."* |

**Three of this seat's four KPIs are unmeasurable, and the one that is measurable reads 100% because the
15-check smoke suite it measures is not the gate battery.** That is the central fact of this section.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Does this change ship? | gate | 2–10×/week | `cto`, `backend_engineer` | The seat's whole reason to exist |
| 2 | Does this change carry a check that fails **before** the fix? | gate | per change | `cto` | A green-from-birth test proves only that somebody typed it |
| 3 | Which of the 110 files in `scripts/checks/` covers this object? | diagnosis | per change | `backend_engineer` | No check→object map exists; the answer is currently a grep |
| 4 | Is this check green because the property holds, or because it cannot fire? | diagnosis | weekly | `cto` | The most expensive failure mode in this estate |
| 5 | Is this check red for a real reason or a stale fixture? | diagnosis | weekly | `it` | Weakening a check to clear it is forbidden |
| 6 | Should this test be excluded from a profile? | gate | rare | `cto` | `test-profiles.json` exclusions are debts with owners, never a way to hide red |
| 7 | Does every exclusion still match a real test? | gate | per release | `cto` | `every_exclusion_still_matches_a_test.test.mjs` exists so an exclusion cannot outlive its subject |
| 8 | Is every file that looks like a test claimed by a runner? | gate | per release | `cto` | `attachment.test.ts` sat unrun for a month; not failing, not passing, invisible |
| 9 | Does the runner walk anything it should not? | gate | quarterly | `it` | `vendor/` carried 280 of 281 `.test.ts` files; `$WT/` was a stale 159 MB copy of the estate's own gates |
| 10 | Is the suite green in CI and unrunnable locally, or vice versa? | diagnosis | monthly | `cto` | Both have happened here |
| 11 | What is the release risk of this batch of changes? | forecast | per release | `cto` | Batch size is the single best predictor of a bad release |
| 12 | Do we have a fixture for this path, and is it safe? | gate | per test | `backend_engineer` | Fixtures must be `ZZ DEMO — …` / `@example.invalid`, inside `withRun`, and cleaned up |
| 13 | Did this rehearsal page the founder? | gate | per rehearsal | founder | Rehearsals and probes page him unless run inside a rehearsal window |
| 14 | Is `demo_rehearsal_active` set, and was it unset afterwards? | gate | per rehearsal | `it` | `decision_policy.demo_rehearsal_active = false` today; leaving it true holds every real notification |
| 15 | Is this defect a regression or a first occurrence? | diagnosis | per defect | `cto` | The KPI that would answer this has no instrument |
| 16 | Which task classes have a measured benchmark? | diagnosis | monthly | `cto` | KPI target 80%; **no instrument** |
| 17 | Is the RFQ qualifier accurate? | diagnosis | monthly | `marketplace` | KPI target 90%; **needs a holdout set that does not exist** |
| 18 | Does this deliverable meet the work order? | gate | per deliverable | `chief_of_staff` | The department has one deliverable returned for *"grounded_in_this_business"* |
| 19 | Is this agent's knowledge actually held, or is it an exam answer? | gate | per knowledge write | `people_ops` | `an_exam_answer_never_becomes_knowledge.test.mjs` exists; 33 of this department's 77 `agent_knowledge` rows are `exam:` rows |
| 20 | Should this seat sit its certification now? | sequencing | quarterly | `people_ops` | Five of six seats have never sat theirs |
| 21 | Is a failing exam a knowledge gap or a retrieval gap? | diagnosis | per exam | `security`, `cto` | Changes whether we ingest or re-index |
| 22 | Is this benchmark measuring the model or the harness? | diagnosis | monthly | `cto` | A harness that seeds an order reality cannot produce measures nothing |
| 23 | Does this gate assert a delta or an absolute business count? | gate | per new check | `cto` | Absolute counts break the moment the company grows; the estate learned this |
| 24 | Is this a mirror gate? | gate | per new check | `cto` | Mirror gates are retired: production proves properties, never an emitted CSV |
| 25 | Does the fix make a headline number fall, and did we say so? | gate | per fix | `cto`, `ceo` | Hiding it is the defect |
| 26 | Is the quality-gate pass rate measuring the right suite? | diagnosis | now | `cto` | It reads 100% over a 15-check smoke suite, not over the 110-file battery |
| 27 | Is this component covered by any check at all? | diagnosis | quarterly | `cto` | 1870 components, 110 check files, no map between them |
| 28 | Should this release be split? | sequencing | per release | `cto` | Blast radius scales worse than linearly with batch size |
| 29 | Is there a rollback, and has it been exercised? | gate | per release | `it` | An unexercised rollback is a hope |
| 30 | Did the deploy reach parity with the repository? | gate | per deploy | `backend_engineer` | 206 directories, 204 components, 70 mirrored source rows |

### 2. Domain logic (the models this seat reasons with)

**M1 — Gate coverage.** `coverage = |components with ≥1 check asserting a property over them| ÷ |components|`.
Denominator is measured: **1870** `phase_c_component` rows. Numerator is **UNMEASURED** — there is no
check→component map in this estate, and building one is this seat's single most valuable instrument.
Today the honest statement is: 110 check files exist; how many of 1870 components they touch **is not known**.

**M2 — Failing-first evidence.** For change `c` with check `k`:
`valid(k) = k was red at commit(before) and green at commit(after)`.
**UNMEASURED**: nothing records a check's verdict against a commit. `qa_results` records
`(run_at, passed, total, failed)` with no commit reference and no per-check row — it stores a JSON
`results` blob for a 15-check suite. The CTO's KPI 107 says the same thing in its own words:
*"NEEDS AN INSTRUMENT THAT DOES NOT EXIST."* **The smallest instrument that fixes both is one table:
`check_verdict(check_name, commit_sha, verdict, run_at)`.**

**M3 — Release risk.** `risk = 0.4·batch + 0.3·max_blast + 0.2·novelty + 0.1·(1 − rollback_exercised)`.
`batch` = files changed ÷ 20, capped at 1. `max_blast` = the maximum of backend M1 over the touched objects.
`novelty` = 1 if any touched object has no check naming it, else 0. `rollback_exercised` ∈ {0,1}.
**Rule**: `risk ≥ 0.6` → split the release. `novelty = 1` → the deliverable is the check, before the change.

**M4 — Dead-guard detection.** For each assertion, three questions with arithmetic answers:
(a) *Can the condition occur?* Run the guard's predicate against production; if it returns zero rows over
the whole table and always has, the guard is **guarded by a condition that cannot occur**.
(b) *Can it fail to occur?* If it returns every row, the guard **cannot not fire** and is noise.
(c) *Does it fire when the system works?* If its trigger correlates with normal operation, it is a false
alarm generator.
This is the estate's own recorded lens set and it is checkable, not intuitive.

**M5 — Exclusion debt.** `test-profiles.json` currently declares the `phase-d` profile with environment
`NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`,
`PHASE_D_EXTERNAL_EFFECT_MODE=mock`, and **two** exclusions, both owned by "knowledge-pack remediation",
both with a `measured` value and an `unblocks` sentence. `debt = 2`.
**Rule**: every exclusion must carry `test`, `file`, `phase`, `owner`, `reason`, `measured`, `unblocks`.
An exclusion missing `unblocks` is not a debt, it is a suppression.

**M6 — Fixture safety.** A fixture is safe iff: the name matches `ZZ DEMO — %`, every address ends
`@example.invalid`, the run is inside `withRun`/`rehearsal_window`, and cleanup is asserted in the same
test. **Preferred over all of it**: the aborted-transaction probe — do the write, count the effect,
`raise exception` with the counts so it rolls back and leaves nothing.
Measured guard-rail: `decision_policy.demo_rehearsal_active = false` today, and while it is true every
notification to a non-`.invalid` address is **held**, not sent.

**M7 — Accuracy against a holdout.** `accuracy = correct ÷ labelled`.
**UNMEASURABLE**: `labelled` requires a holdout set of inquiries with known-correct qualification verdicts.
`inquiries` holds **0 rows**. This is not an instrument problem, it is a data problem, and the KPI's own
`no_measure_reason` says so. Building the set is the work; measuring is trivial once it exists.

**M8 — Exam integrity.** `an_exam_answer_never_becomes_knowledge.test.mjs` asserts the property. Measured
today, this department holds **77** `agent_knowledge` rows of which **33 have topics beginning `exam:`**
(`it` 3 of 35, `cto` 6 of 8, `qa_manager` 5 of 8, `backend_engineer` 5 of 7, `red_view_alerter` 6 of 6,
`security` 3 of 13). For `red_view_alerter` that is **6 of 6 — every row it holds is an `exam:` row.**
Whether those rows are exam *subjects* (legitimate) or exam *answers* (forbidden) is the check's job, and
this seat should report the ratio, not just the pass.

### 3. Reasoning procedures

**Type 1 — does this ship.**
(a) Is there a check that names the changed object? If no → **the deliverable is the check**, and shipping
waits. (b) Was that check red before the change? If it has never been red, it is unproven (M2).
(c) Run the battery: `node scripts/checks/run.mjs`. (d) Any red → stop; a red check is never edited to make
it green. (e) `canonical_routine_manifest.mjs` must report **0 problems**. (f) M3 risk; `≥ 0.6` → split.
(g) `deploy_state.dirty` must be false. (h) Pass to `cto`.
**Refuses when**: the check cannot be made to fail on the defect. That means the property is not being
asserted, whatever the file says.

**Type 4 — green because it holds, or green because it cannot fire.**
(a) Extract the guard's predicate. (b) Run it against production unaltered. (c) Zero rows always → M4(a),
dead guard. (d) Invert the predicate and confirm it can return rows; if the inverted form is also empty,
the subject does not exist and the check is asserting over nothing. (e) Best evidence of all: make the
defect the check claims to catch, in a transaction, and confirm the check goes red — then roll back.
**This is the aborted-transaction probe applied to the gate itself, and it costs nothing.**

**Type 6/7 — exclusions.**
(a) An exclusion requires all seven fields. (b) `every_exclusion_still_matches_a_test.test.mjs` proves the
subject still exists. (c) Quarterly, re-read each `unblocks` sentence and ask whether it has become
possible. The current two both unblock on regenerating the V3 manifest from `org_departments where active`
— that became possible when the org settled at 10 active departments, so **both are now overdue rather than
blocked**, and this seat should say so.
**Refuses to add an exclusion when**: the reason is "it fails and we do not know why".

**Type 8/9 — is every test claimed, and does the runner walk only what it should.**
(a) `discover()` is exported from `run.mjs` and the guard asserts against the real walk, not a copy — never
re-implement the patterns in the guard, because a guard that restates its subject proves only that somebody
typed the same thing twice. (b) `LOOKS_LIKE_A_TEST` is deliberately wider than `NODE_TEST ∪ DENO_TEST`;
the gap between them *is* the defect being prevented. (c) `SKIP_DIRS` must exclude `vendor` and any
directory carrying its own `.git` — a directory with its own `.git` is a different repository, not part of
this one. (d) A missing `deno` is a **hard failure, never a skip**.

**Type 11/28 — release risk and splitting.**
(a) M3. (b) If `≥ 0.6`, split along the largest independent subset — the set of changed objects with no
`pg_depend` edge between them. (c) Ship the lowest-blast subset first and re-measure the estate before the
next. (d) Record the split reason; "it was big" is not a reason, the risk terms are.

**Type 19/21 — knowledge or exam answer.**
(a) Run the exam-answer check. (b) Compute the `exam:`-prefixed ratio per agent (M8). (c) A seat whose
rows are entirely `exam:` (today: `red_view_alerter`, 6 of 6) has **no substantive stored knowledge of its
own**, whatever the row count says. (d) For a failed exam, cross-reference the failed syllabus areas against
the module titles in `ops_knowledge`; zero matching modules → knowledge gap (ingest), matching modules →
retrieval gap (re-index). Applied to `security`'s CISSP Domain 6: **zero matching modules → ingest.**

**Type 26 — is the pass rate measuring the right suite.**
(a) `qa_results` rows carry `total = 15`. (b) `scripts/checks/` holds **110** files. (c) Therefore the
100.00% KPI is over a 15-check smoke suite, not the gate battery. (d) The honest report is
*"the smoke suite is 15/15; the battery's pass rate is not recorded anywhere"*, and the fix is to write
battery results into `qa_results` with a `suite` column — which **does not exist** today
(`qa_results` is `id, run_at, passed, total, failed, results`).

### 4. Judgement rules

| Condition | Verdict | Reason |
|---|---|---|
| A change with no check naming its object | **the check is the deliverable; do not ship** | Novelty is the term in M3 that should stop a release |
| A check that has never been red | **not evidence** | It proves only that somebody typed it |
| A red check "fixed" by editing the check | **reject, always** | Never weaken a check. If the check is wrong that is a separate, argued change |
| A gate made green by emitting a CSV or writing to a mirror | **reject** | Mirror gates are retired; production proves properties |
| A gate asserting an absolute business count | **reject** | It breaks the day the company grows; assert deltas |
| A fixture without `ZZ DEMO — ` and `@example.invalid` | **reject** | It will reach a real address |
| A fixture run outside `withRun` / `rehearsal_window` | **reject** | Rehearsals and probes page the founder |
| `demo_rehearsal_active` left `true` after a rehearsal | **incident** | Every real notification is held while it is on |
| An exclusion with no `unblocks` sentence | **reject** | That is a suppression, not a debt |
| An exclusion whose `unblocks` condition is now satisfiable | **overdue; open the task** | Both current exclusions are in this state |
| A guard whose predicate returns zero rows over all history | **dead guard; report it as a finding, not as a pass** | Zero cannot tell a dead guard from an idle system |
| A guard that fires whenever the system works normally | **noise; remove or re-scope** | A guard that cannot not fire trains everyone to ignore the channel |
| A `.test.*` file no runner claims | **the suite is not the suite** | `attachment.test.ts` proved this for a month |
| A missing `deno` treated as a skip | **hard failure** | Otherwise the Deno half silently disappears |
| A directory with its own `.git` inside the tree | **exclude from discovery** | `$WT/` handed the runner a stale copy of the estate's own gates, including a reference to the deleted staging project |
| Accuracy claimed with no holdout set | **refuse the number** | `inquiries = 0`; there is nothing to be accurate against |
| A pass rate quoted without naming its suite | **reject the claim** | 15/15 and 110 files are not the same subject |
| A fix that lowers a headline number | **ship and say so in the same sentence** | Hiding it is the defect |
| An `agent_knowledge` row whose topic begins `exam:` counted as expertise | **do not count it** | 33 of this department's 77 rows are such rows |

### 5. Technical knowledge

- **The runner** — `scripts/checks/run.mjs`: exports `discover()`, `NODE_TEST` (`/\.test\.mjs$/`),
  `DENO_TEST` (`/\.test\.ts$/`) and `LOOKS_LIKE_A_TEST` (`/\.(test|spec)\.[cm]?[jt]sx?$/`), with `SKIP_DIRS`
  = `.git, node_modules, .next, dist, build, out, .vercel, coverage, .turbo, vendor` plus any directory
  carrying its own `.git`. `npm test` runs everything; `npm run test:phase-d` runs the profile.
- **The profiles** — `test-profiles.json`: the `phase-d` profile with `NO_PAID_AI=true`,
  `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`, `PHASE_D_EXTERNAL_EFFECT_MODE=mock` and two owned
  exclusions.
- **The battery** — 110 files. The ones this seat must know by name because they encode a lesson:
  `every_test_file_is_run`, `every_exclusion_still_matches_a_test`, `canonical_routines`,
  `application_source_of_truth`, `anon_cannot_execute_security_definer`,
  `before_triggers_do_not_read_what_a_later_one_writes`, `an_exam_answer_never_becomes_knowledge`,
  `every_position_sits_its_certifications`, `protected_table_guards_actually_fire`,
  `phase_b_guards_reject_injected_defects`, `phase_c_guards_reject_injected_defects`,
  `dr_drill_clears_its_own_staging_table`, `every_cron_command_still_parses`,
  `zero_cost_evidence_window_covers_the_work`, `the_founder_is_emailed_exceptions_only`.
- **The post-apply sequence** — `export_from_either_source_is_identical.mjs --write`, then
  `canonical_routine_manifest.mjs` (expect 0 problems), `sql_files_match_live.test.mjs`,
  `application_source_of_truth.test.mjs`, and `verify_deploy_parity.mjs --all` after an edge deploy.
- **The gate contracts** — `phase_d_gate_contract`, 32 rows, each with `gate_id`, `predicate_kind`
  (`MEASURED` or `EVIDENCE_REQUIRED`), `refusal_code`, `correction_owner` and `evidence_source`.
  Examples: `GATE-004 gate004_creator_is_reviewer` (evidence `fn_kernel_reviewer_independent`),
  `GATE-005 gate005_founder_boundary`, `GATE-011 gate011_inquiry_not_ready` (evidence `inquiries.status`).
- **Result surfaces** — `qa_results` (`id, run_at, passed, total, failed, results`; 288 rows, `total = 15`),
  `ai_qa_log` (103 rows), `phase_d_injected_defect_result` (**0 rows**),
  `phase_d_fixture_catalogue`, `phase_d_step_case_result`.
- **Must be stored so the seat never asks**: the fixture convention; the aborted-transaction probe; the
  seven required exclusion fields; the failing-first rule; the "never edit a red check" rule; the post-apply
  command sequence; the distinction between the 15-check smoke suite and the 110-file battery.
- **Does not exist**: a check→component coverage map; a `check_verdict` table keyed by commit; a `suite`
  column on `qa_results`; a labelled holdout set for RFQ qualification; a task-class benchmark register;
  a defect register that would let "regressions caught before production" be computed.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source | Ingest or cite |
|---|---|---|---|
| Test management | Test process, estimation, monitoring, defect management, process improvement | **ISTQB syllabi are published free by ISTQB** — Advanced Level Test Manager and Foundation | **Ingest** |
| Test design | Equivalence partitioning, boundary value, decision tables, state transition, pairwise | ISTQB Foundation syllabus + public combinatorial-testing material (NIST SP 800-142) | **Ingest** |
| Mutation testing | The idea that a suite is measured by the defects it kills, not by lines covered | Public academic literature via open-access venues; NIST SP 800-142 for combinatorial coverage | **Ingest open-access only** |
| Service management | Change enablement, release management, incident vs problem | ITIL 4 is **copyrighted (AXELOS)**; ingest the free glossary only | Cite |
| Statistical quality | Sampling, control limits, false-discovery rate | NIST/SEMATECH *Engineering Statistics Handbook* — public domain | **Ingest** |
| Reliability of measurement | Construct validity — is the instrument measuring the intended subject | Open-access measurement-theory material | **Ingest** |
| Safety-critical assurance | Assurance cases: claim, argument, evidence | ISO/IEC/IEEE 15026 abstract; publicly published assurance-case guidance | Cite |
| Release engineering | Trunk-based development, batch size, change failure rate | DORA's freely published *State of DevOps* metric definitions | **Ingest the four metric definitions** |

**Certifications on file**: ISTQB Advanced Level Test Manager (pass mark 65.00, rank 1; areas *Managing the
Test Process, Test Management in Context, Reviews, Defect Management, Improving the Test Process, Test Tools
and Automation, People Skills and Team Composition*) and ITIL 4 Foundation (65.00, rank 2).
**Syllabus areas failed: does not exist — this seat has never sat either exam.** Two of its seven ISTQB
areas — *Defect Management* and *Improving the Test Process* — have no corresponding instrument in the
estate at all (no defect register, no coverage trend), which means the seat could not practise them even if
it passed the exam.

### 7. Corporate knowledge

- **The four hard rules**, and specifically hard rule 2: the top-3 comparison ranks **all** quotations on
  technical *and* commercial merit and never cheapest-wins. When quotes exist, that ranking is the single
  most important thing this seat tests, and it must be tested **deterministically** — a model-scored
  ranking would breach the founder's constraint.
- **Its own authority**: `qa_gate` autonomous — *"holds work that fails a quality check. Restrictive, never
  permissive."* That phrase is the seat's charter: it may stop, it may not wave through.
  `knowledge_acquire`/`fill`/`fill_gap` are advisory.
- **The founder-boundary tests it owns**: `the_founder_is_emailed_exceptions_only.test.mjs` and its probe,
  `founder_approval_is_refunds_only.test.mjs`, `receipts_never_wait_on_the_founder.test.mjs`,
  `held_rows_have_a_non_founder_owner.test.mjs`. These encode `decision_policy.founder_review_gates =
  ["refund_decision","refund_outside_policy"]` as executable checks, which is the right way to hold a
  founder ruling.
- **The pricing tests it owns**: `pricing_consistency.test.mjs`, `pricing_arabic_parity.test.mjs`,
  `pricing.canonical.json`, `the_refund_ladder_texts_agree.test.mjs` and the refund-ladder probe. These
  guard the 3.00%, the AED 250, the 9%, the 5/3 working days and the 7–14 day bank message across English
  and Arabic.
- **Hands to**: `cto` (ship/hold), `backend_engineer` (the failing-first check for each change),
  `security` (control testability — a control that cannot be tested is not a control), `people_ops`
  (exam sittings), `chief_of_staff` (returned deliverables).
- **History it must not forget**: `attachment.test.ts` unrun for a month; the `vendor/` walk that made the
  suite green in CI and unrunnable on Windows at the 32k command-line limit; the `$WT/` stale worktree
  containing a live reference to the deleted staging project `pglpqrhvozwepymcuunn`; the 9 Aug 2026 Actions
  allowance running out, which turned "green in CI" into no evidence at all.
- **The department's returned deliverable**: *"Returned by review (request_revision). grounded_in_this_business
  (minor): The work order says: Be concrete and specific."* — carried on all six seats' improvement plans.

### 8. One-year plan

**Objective.** Turn the phrase "the gate is green" into a claim with a measurable subject, and give this
seat three KPIs it can actually compute.

**This seat's slice of AED 1,000,000: AED 0 direct.** Its contribution is that the top-3 ranking, the 3.00%
arithmetic and the refund ladder are right the first time a real customer pays — and none of the three has
ever been exercised on real data (`quotes = 0`, `transactions = 0`, `refunds = 0`).

**Metrics.**
1. **Battery pass rate, by named suite** — computable the day `qa_results` gains a `suite` column. Today the
   100.00% figure is over a 15-check smoke suite; the 110-file battery's rate **is not recorded anywhere**.
2. **Failing-first share** — `changes whose check was red before the fix ÷ changes`. Needs the
   `check_verdict(check_name, commit_sha, verdict, run_at)` table. This single table also unblocks CTO
   KPI 107 and this seat's "regressions caught before production".
3. **Component coverage** — checked components ÷ 1870. Needs the check→component map.

All three are builds first and metrics second, and this plan says so rather than setting a percentage
against an instrument that does not exist.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** (i) Add `suite` to `qa_results` and write the battery's own results into it, so
  the pass-rate KPI names its subject. (ii) Build `check_verdict`. (iii) Clear the two `test-profiles.json`
  exclusions — both `unblocks` conditions are now satisfiable. (iv) Sit the ISTQB Advanced Test Manager exam.
- **Q2 (Dec 2026–Feb 2027).** Build the check→component map (M1), even coarsely: a `check_covers`
  table naming (check_file, component_id). Then publish the first honest coverage number over 1870
  components, whatever it is.
- **Q3 (Mar–May 2027).** Run M4 against every guard in the battery — dead-guard and cannot-not-fire
  detection — using the aborted-transaction probe. Report the count of guards that cannot fire. This is the
  highest-value audit available to this seat and it costs nothing but time.
- **Q4 (Jun–Aug 2027).** Build the RFQ qualification holdout set *from real inquiries* — which requires
  inquiries to exist. If `inquiries` is still 0 at Q4, this milestone is not deliverable and the KPI should
  be retired rather than carried as unmeasurable for a second year.

**Capacity check.** Q1–Q3 are three small tables and one systematic audit — deliverable by one seat.
**Q4 is not within this seat's control at all**: it depends on demand this department does not generate.
The honest position is that three of this seat's four KPIs become measurable this year and the fourth
depends on the marketplace producing its first inquiries.

**Dependencies.** `backend_engineer` (the three tables), `cto` (accepts ship/hold and the coverage number),
`security` (testability of controls), `people_ops` (exam sittings — five of six seats in this department
have never sat one, and `every_position_sits_its_certifications.test.mjs` already exists to notice),
`marketplace`/`growth` (inquiries, for Q4 and for nothing else this seat needs).

**Is the slice achievable?** Yes for Q1–Q3, and they are the ones that change what this department can
honestly claim. No for Q4 unless demand arrives; the plan says retire the KPI rather than carry a second
year of `NEEDS A FIXTURE THAT DOES NOT EXIST`.

### 9. What this seat cannot do without a model

1. **Deciding whether a deliverable is *good*, as opposed to whether it passes.** Pass/fail against named
   assertions is arithmetic. "Is this grounded in this business and concrete enough" — the exact wording of
   the returned deliverable on file — is a judgement over prose.
2. **Generating new test cases from a specification written in English.** The seat can enumerate boundary
   values from a typed schema (`phase_d_input_schemas_are_typed_and_closed.test.mjs` already asserts the
   schemas are typed and closed, which makes this tractable); it cannot read a prose spec and invent cases.
3. **Grading free-text agent output for accuracy.** Every accuracy KPI in this seat's list reduces to
   comparing generated text against intent. With a labelled holdout set it becomes string comparison and
   needs no model; without one it needs a model or a human. **The holdout set is the deterministic answer,
   and it does not exist.**

---

## red_view_alerter — Red-view Alerter

The only `kind='agent'` seat in this department (the other five are `kind='brain'`), hired 4 Sep 2026.
`routing_tier=operations_specialist`, reports to `cto`. Its recorded responsibility:

> *"Watches every monitored view and metric; the moment one turns red it raises a founder alert
> (`founder_alerts`) with the measurement, deduplicated, and hands the remediation to the Reliability/SRE
> agent. The alert is the record of a red view, never a substitute for the SRE fixing it. Deterministic:
> `fn_exception_alerts`, `fn_emit_metric_alerts`, `fn_alert_severe`."*

Authority: **`escalate_founder` autonomous at `threshold_aed = 0`** — *"a red view reaches the founder
without a gate; that is the seat"* — plus `metric_alerts` and `health_report` autonomous.
One KPI, measured: **Red-to-alert latency**, *"minutes from a red measurement event to the next founder
alert (7-day mean; null when no red event occurred)"*, target **60**, actual **29.4** — comfortably green.

This seat is already almost entirely deterministic. What follows is mostly a description of what it does
and a small number of gaps.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Is this view red right now? | diagnosis | every 15 min | itself | The whole seat |
| 2 | Is this red a **new episode** or the continuation of an open one? | gate | every 15 min | founder | Re-paging an open episode destroys the channel's credibility |
| 3 | Did a resolved episode re-open? | gate | every 15 min | founder | A recurrence is new information and must page again |
| 4 | Is this red inside a rehearsal window? | gate | every run | `qa_manager` | A rehearsal that pages the founder is a defect; `fn_rehearsal_window_covers()` is the guard |
| 5 | Which of the 14 monitored metrics moved past its threshold? | diagnosis | 15 min | `data_intel` | 14 `metric_definition` rows, 87 snapshots each |
| 6 | Is this metric red or is its `measure_sql` erroring? | diagnosis | 15 min | `it` | `metric_snapshot.error` is non-null on 2 of 14 metrics today — an erroring measure is not a red metric |
| 7 | What severity does this red carry? | gate | per red | founder | Severity decides the channel and whether it may email him at all |
| 8 | Does this kind's `founder_mail_policy` allow email? | gate | per alert | founder | `red_view` is `allowed_to_email = **false**`, owner `it_operations_engineer` |
| 9 | Who gets the remediation? | allocation | per red | `it` | The alert is the record, never the fix |
| 10 | Is this board red because the property broke or because the board timed out? | diagnosis | 15 min | `it` | This seat's own cron failed three times this week on statement timeout |
| 11 | Is a monitored department's health score falling? | forecast | daily | `ceo` | `department:*` episodes exist for exec, finance, marketplace, supply, data_intel, customer_experience |
| 12 | Is a cron job stale? | diagnosis | 15 min | `it` | `watcher:cron_stale:*` and `cron:*` episodes both exist |
| 13 | Is a watcher itself failing? | diagnosis | 15 min | `it` | The largest episode group today is `watcher:kb_embed:*` with 14 episodes across two signatures |
| 14 | Is this red the same underlying condition as that red? | gate | per run | founder | Fourteen episodes are open now; if three describe one cause, that is one page, not three |
| 15 | Has an open episode been open too long? | escalation | daily | `it`, `cto` | 3 of the 14 open episodes date from 4 Sep — three days without resolution |
| 16 | Does the alert body carry the measurement, or just the name? | gate | per alert | founder | "X is red" without the number is not a report |
| 17 | Is the credential stripped from the queued payload? | gate | per post | `security` | The post body carries an internal credential and `__secret` must be removed before anything leaves |
| 18 | Is `net.http_request_queue` draining? | diagnosis | hourly | `it` | Queued-and-never-sent looks identical to never-alerted |
| 19 | Should the boards be included in this pass? | allocation | per run | `it` | `fn_red_view_alert(p_boards boolean)` takes the flag; boards are the expensive half |
| 20 | Is this connectivity gap new? | diagnosis | 15 min | `cto` | `connectivity:*` episodes name a gap class and subject |
| 21 | Is the trace estate intact? | diagnosis | 15 min | `cto` | Two of the 14 open episodes are `board:fn_kernel_trace_integrity:*` |
| 22 | Did a red resolve itself, and should we say so? | craft | 15 min | founder | A resolution notice closes the loop; silence after a page reads as an unfixed problem |
| 23 | Is the 29.4-minute mean latency drifting? | forecast | weekly | `cto` | Target 60; the cadence is `7,22,37,52 * * * *`, so ~15 min is the floor |
| 24 | Is this the founder's channel or a role's queue? | gate | per alert | founder | Only 5 kinds in the entire policy may email him from this department |
| 25 | Is an alert missing — did something turn red and nobody paged? | diagnosis | daily | `qa_manager` | A silent alerter is worse than a noisy one and looks the same as a healthy estate |
| 26 | Is my own job alive? | diagnosis | 15 min | `it` | Job 324 failed 3 times in 7 days; a dead alerter reports nothing, including its own death |

### 2. Domain logic (the models this seat reasons with)

**M1 — Episode identity.** The estate implements this already, in `public.red_episode`
(`id, source, check_key, detail, opened_at, observed_at, last_seen_at, alerted_at, alert_dedupe_key,
paged_by, resolved_at`). Measured: **58 episodes, 14 currently open.**
`check_key` is a structured composite — the live namespaces are
`watcher:<name>:<detail>`, `department:<key>`, `board:<routine>:<check_name>`, `cron:<jobname>`,
`health:<kind>:<target>`, `connectivity:<gap_class>:<subject>`.
Rule: **one page per episode.** A red with an open episode of the same `check_key` updates `last_seen_at`
and pages nothing; a red whose episode was `resolved_at` opens a **new** episode with a new id and pages
once. This is proved in an aborted transaction by
`scripts/checks/red_view_alerter_pages_once_per_episode.mjs`, whose five passes assert exactly:
warm-up → 1 new episode and 1 queued post → resolve with 0 posts → re-fail as a **new** episode with 1 post
→ no change, 0 opened and 0 posts.

**M2 — Red-to-alert latency (the KPI).**
`latency = alerted_at − observed_at`, 7-day mean, null when no red event occurred.
Measured: **29.4 minutes** against a 60-minute target. The scheduler floor is set by the cadence
`7,22,37,52 * * * *` — four runs an hour, so the expected mean for a uniformly-arriving red is ~7.5 minutes
plus execution time. **A measured 29.4 against a 7.5 floor means roughly two runs' worth of delay is being
absorbed somewhere**, which is consistent with the three statement-timeout failures this week. The seat
should report the floor alongside the mean; a green KPI with a 4× gap to its floor is a finding.

**M3 — Metric threshold.** For each of the 14 `metric_definition` rows:
`red = (direction = 'up' and value < target) or (direction = 'down' and value > target)`.
The live definitions and targets: `ai_cost_30d` ≤ 7700 · `avoidable_ai_pct` ≤ 10 · `categories_live` ≥ 10 ·
`failed_runs_24h` ≤ 0 · `inquiries_7d` ≥ 50 · `knowledge_compliance_pct` ≥ 100 · `open_p1` ≤ 0 ·
`quotes_per_inquiry` ≥ target · `refund_rate` ≤ 5 · `reveal_revenue_30d` ≥ 20000 · `reveals_30d` ≥ 40 ·
`rfq_ready_pct` ≥ 70 · `supplier_response_rate` ≥ 60 · `verified_suppliers` ≥ 2000.
`metric_snapshot` holds **87 snapshots of each**, last taken 7 Sep 06:35.
**Critical distinction**: `metric_snapshot.error` is non-null for `failed_runs_24h` and `categories_live`.
An **erroring measure is not a red metric** — it is a broken instrument, and paging the founder about a
business number that failed to compute is a false alarm about the wrong subject.
**Note also**: with `inquiries = 0`, `transactions = 0` and `verified_suppliers = 1`, **six of the fourteen
metrics are red by construction and will stay red until the marketplace has demand.** Paging on those every
15 minutes would be pure noise; the dedupe is what makes the seat survivable.

**M4 — Severity and routing (a lookup, no discretion).**
`founder_mail_policy` for `red_view`: `allowed_to_email = **false**`, `owner_role =
it_operations_engineer`, reason *"a red monitored view is engineering's to turn green."*
So the seat's `escalate_founder` authority is real but narrow: it raises the `founder_alerts` row and the
routing layer decides whether that becomes an email or an owned `org_tasks` row. Measured evidence that this
works: in the last 30 days `founder_alerts` carried `"Red view: 1 new red signal(s)"` twice at `error` and
twice at `high`, and `"Red view: 24 new red signal(s)"` once at `error` on 4 Sep — the day the seat was
hired and swept the standing backlog.

**M5 — Rehearsal suppression.** `fn_rehearsal_window_covers(clock_timestamp())` gates every post.
`decision_policy.demo_rehearsal_active` is **false** today; while it is true, every notification whose
recipient is not a reserved `.invalid` address is **held**, not queued.
**Rule**: a red observed inside a rehearsal window still opens its episode — the record is kept — but pages
nothing. Losing the record would be worse than the false page.

**M6 — Payload hygiene.** The queued post in `net.http_request_queue` carries the internal credential in a
`__secret` field, which is removed before anything leaves the database. Any change to the alert body must
preserve that removal. This is asserted inside the same aborted-transaction probe.

**M7 — Silent-alerter detection (the seat's own failure mode).**
`silent = no red_episode row opened in a window during which a monitored condition was red`.
Measured today: job 324 (`red_view_alert_15min`) failed **three times in seven days**, each with
`canceling statement due to statement timeout`, inside `fn_company_connectivity_register`,
`fn_kernel_trigger_state` and `fn_phase_c_step_event`.
**UNMEASURED**: nothing currently asserts that the alerter ran. `alert_watermark` holds exactly **one** row
and it is for the `failed_runs` watcher, not for this one. A `red_view` watermark **does not exist**, so
"the alerter has been quiet" and "nothing is red" are indistinguishable — which is the exact trap this
department's own lens set names.

**M8 — Episode ageing.** `age = now() − opened_at` on open episodes. Measured: 14 open, of which
`board:fn_kernel_trace_integrity:orphan_traces_task` and
`board:fn_kernel_trace_integrity:traces_with_unmapped_subject_kind` have been open since **4 Sep 05:37** —
three days. **Rule**: an episode open beyond its owner's SLA escalates to the owner's lead, not to the
founder (`os_incident_past_sla` is `allowed_to_email = false`, owner `it_operations_engineer`).

### 3. Reasoning procedures

**Type 1/2/3 — the fifteen-minute pass.**
(a) `fn_red_view_alert(p_boards)`. (b) For each red signal compute its `check_key`. (c) Look up an open
`red_episode` with that key: found → update `last_seen_at`, **page nothing**; not found → insert an episode
and queue **one** post. (d) For each previously-open key that is no longer red, set `resolved_at`.
(e) Before queueing, check `fn_rehearsal_window_covers(clock_timestamp())`; inside a window, open the
episode and queue nothing. (f) Strip `__secret` from the body.
This is the procedure the check proves, pass by pass, and it should not be re-described in prose anywhere
else — the check is the specification.

**Type 6 — red metric or broken measure.**
(a) Read the latest `metric_snapshot` per `metric_key`. (b) `error is not null` → this is an **instrument
failure**: route to `it` as a broken measure, never as a business red. (c) `error is null` → apply M3.
(d) If the metric is red **and** its denominator is zero — `inquiries_7d` with 0 inquiries,
`quotes_per_inquiry` with 0 quotes, `refund_rate` over 0 reveals — say so in the body: *"red because the
denominator is zero"* is a materially different statement from *"red because performance fell"*, and today
six of fourteen metrics are in the first category.

**Type 10 — property broke or board timed out.**
(a) Did `fn_kernel_all_boards()` return, or did it error? (b) A statement timeout is **not** a red board;
it is this seat's own failure and belongs to `it` as a batching problem. (c) Distinguish in the episode
`source` field so the two never merge. (d) If the boards pass timed out, the honest state is
*"boards not measured this run"*, not *"boards green"*.

**Type 14 — one cause or three reds.**
(a) Group open episodes by `source` and by the leading segment of `check_key`. (b) Two episodes whose
`check_key` shares the same routine — e.g. both `board:fn_kernel_trace_integrity:*` — are one cause with two
symptoms. (c) Page the cause once, list the symptoms in the body. (d) Resolve them together or not at all.

**Type 25 — is an alert missing.**
(a) Compare the set of currently-red conditions with the set of open episodes. (b) A red with no episode is
a **miss** and is the most serious defect this seat can have. (c) Compare the last successful run of job 324
against the cadence; more than 30 minutes since the last successful run means the seat has been blind, and
the correct output is *"I have not been running"*, not silence.
**This procedure cannot be executed today** because no `red_view` row exists in `alert_watermark`. Building
it is the seat's first milestone.

**Type 26 — is my own job alive.**
(a) Read `cron.job_run_details` for jobid 324 in the last hour. (b) Any `failed` → report it, with the
`return_message`, to `it`. (c) No rows at all → the scheduler is not running this job, which is a
`platform_down`-class condition and one of the few things in this department that **may** reach the founder.
(d) A seat that cannot report its own death is not a monitor.

### 4. Judgement rules

| Condition | Verdict | Reason |
|---|---|---|
| A red whose `check_key` already has an open episode | **do not page** | One page per episode; the check proves it in five passes |
| A resolved episode's condition recurs | **new episode, new id, page once** | A recurrence is new information |
| Any post while `fn_rehearsal_window_covers()` is true | **suppress the post, keep the episode** | Rehearsals and probes must never page the founder |
| `metric_snapshot.error is not null` | **broken instrument, not a red metric** | Two of fourteen metrics are in this state right now |
| A metric red because its denominator is zero | **say so in the body** | Six of fourteen are red by construction while `inquiries = 0` |
| A board pass that timed out | **"not measured", never "green"** | Job 324 timed out three times this week |
| An alert body with no measurement in it | **not an alert** | The seat's own charter says "with the measurement" |
| `__secret` present in an outgoing body | **block the post** | The credential must never leave the database |
| A red view routed as an email to the founder | **reject** | `red_view.allowed_to_email = false`; it is engineering's to turn green |
| An episode open past its owner's SLA | **escalate to the owner's lead, not the founder** | `os_incident_past_sla` is also `false` |
| Two episodes naming the same routine | **one cause, one page, symptoms listed** | Otherwise the channel reports symptom count as if it were cause count |
| No successful run of job 324 in 30 minutes | **report blindness immediately** | Silence and health are indistinguishable otherwise |
| The seat considering a fix | **never; hand it to the SRE** | "The alert is the record of a red view, never a substitute for the SRE fixing it" — its own charter |
| A red suppressed because it is "always red" | **reject** | Dedupe by episode, never by fatigue. Suppression must be a resolved episode or a rehearsal window, nothing else |

### 5. Technical knowledge

- **Its own routine** — `fn_red_view_alert(p_boards boolean)`, invoked by job **324**
  `red_view_alert_15min`, schedule `7,22,37,52 * * * *`, active, wrapped as
  `select public.fn_kernel_cron_exec(324);`.
- **Its tables** — `red_episode` (58 rows, 14 open; `source, check_key, detail, opened_at, observed_at,
  last_seen_at, alerted_at, alert_dedupe_key, paged_by, resolved_at`), `founder_alerts`
  (`level, event, detail, channel, dedupe_key`; 200 rows), `alert_signature` (46 rows across watchers
  `failed_runs` 30, `founder_mail` 15, `resilience` 2), `alert_watermark` (**one** row, watcher
  `failed_runs`), `metric_definition` (14), `metric_snapshot` (1218 = 14 × 87).
- **The `check_key` namespaces** it must parse: `watcher:`, `department:`, `board:`, `cron:`, `health:`,
  `connectivity:`.
- **The suppression gate** — `fn_rehearsal_window_covers(p_at timestamptz)` and
  `public.rehearsal_window`; `decision_policy.demo_rehearsal_active`.
- **The delivery path** — `net.http_request_queue`, and that the body carries `__secret` which is stripped
  before send.
- **The routing layer** — `fn_notify_founder(p_event, p_detail, p_level, p_kind, p_dedupe_key,
  p_owner_agent)` and `fn_founder_mail_route(...)`; `founder_mail_policy` and the fact that its own kind
  `red_view` is **not** emailable.
- **Its sibling deterministic routines** named in its charter — `fn_exception_alerts()`,
  `fn_emit_metric_alerts()`, `fn_alert_severe(p_level)`.
- **Its own proof** — `scripts/checks/red_view_alerter_pages_once_per_episode.mjs`, and the pattern it
  uses: one transaction, five passes, `RAISE` at the end so nothing survives and the founder is never paged
  by the probe.
- **Must be stored so the seat never asks**: the six `check_key` namespaces; the 14 metric targets and
  directions; the one-page-per-episode rule; the rehearsal gate; the `red_view` routing verdict; the fact
  that an erroring measure is not a red metric.
- **Does not exist**: a `red_view` row in `alert_watermark` (so the seat cannot detect its own silence);
  a `denominator_is_zero` flag on `metric_definition`; a cause-grouping column on `red_episode`.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source | Ingest or cite |
|---|---|---|---|
| Event and incident management | Event → alert → incident as three distinct things; the alert is a record, not a remediation | ITIL 4 is **copyrighted (AXELOS)** — this seat's rank-1 certification. Ingest the free ITIL glossary definitions of *event*, *alert*, *incident*, *problem* only | Cite |
| Alerting practice | Symptom-based alerting, alert fatigue, page-worthiness | Google's freely-published SRE alerting material | **Cite only**; the episode arithmetic is ours |
| Statistical process control | When a moved number is a signal and when it is noise; control limits | NIST/SEMATECH *Engineering Statistics Handbook* — public domain | **Ingest** |
| Detection theory | False positive / false negative trade-off; the cost asymmetry of a missed page | Open-access signal-detection material | **Ingest** |
| Anomaly detection without a model | Threshold, delta, and seasonal-baseline methods | Published open-source detector documentation under permissive licences | **Ingest** |
| Monitoring semantics | Metric, log and trace as distinct signals; cardinality | OpenTelemetry specification (Apache 2.0) | **Ingest** |

**Certification on file**: ITIL 4 Foundation (pass mark 65.00, rank 1; areas *Key Concepts of Service
Management, The Four Dimensions of Service Management, The ITIL Guiding Principles, The Service Value
System, The Service Value Chain, ITIL Practices, Continual Improvement*), recorded because *"raising and
routing alerts is incident and event management inside the ITIL service value system."*
**Syllabus areas failed: does not exist — this seat has never sat the exam.**
It is also the seat with the weakest stored knowledge in the department: **all six of its `agent_knowledge`
rows are `exam:`-prefixed** (`exam:1281`, `1283`, `1326`, `1328`, `1329`, `1514`), so it holds **no
substantive knowledge row of its own**. That is a measured fact, and it is the strongest argument in this
document for writing its charter into `ops_knowledge` as real records rather than leaving it in a
`responsibilities` text field.

### 7. Corporate knowledge

- **Its own charter, verbatim** (from `org_agents.responsibilities`): it watches every monitored view and
  metric, raises a deduplicated `founder_alerts` row **with the measurement**, and hands remediation to the
  SRE. *"The alert is the record of a red view, never a substitute for the SRE fixing it."*
- **Its authority**: `escalate_founder` autonomous at threshold 0 — *"a red view reaches the founder without
  a gate; that is the seat"* — and `metric_alerts` autonomous — *"raising a metric alert is the seat's own
  decision."* It has **no** `incident_fix` or `code_selfheal` grant at all. It cannot fix anything, by design.
- **The counterweight**: `founder_mail_policy.red_view.allowed_to_email = false`, owner
  `it_operations_engineer`. So the seat may raise without a gate, and the routing layer still keeps the
  founder's inbox clean. Both facts are true and the seat must hold both.
- **The four hard rules** apply to what it reports on: six of its fourteen metrics
  (`inquiries_7d`, `reveals_30d`, `reveal_revenue_30d`, `quotes_per_inquiry`, `refund_rate`,
  `supplier_response_rate`) are reveal-economics metrics and every one of them currently reads against a
  zero denominator.
- **Hands to**: `it` (every remediation, and its own job failures), `cto` (board and connectivity reds),
  `data_intel` (metric definitions), `qa_manager` (its own probe).
- **History it must not forget**: it was hired 4 Sep 2026 and its first sweep raised
  *"Red view: 24 new red signal(s)"* — a standing backlog, not 24 new failures. Its job has failed three
  times since. `kb_embed` watcher episodes are the largest group it has ever opened (14 across two
  signatures), and both signatures describe the same underlying I/O storm.

### 8. One-year plan

**Objective.** Never miss a red, never page twice for one, and be able to prove it was awake.

**This seat's slice of AED 1,000,000: AED 0 direct.** Its contribution is time-to-detection on the paid
path. If a reveal fails and nobody is told for an hour, the customer is gone; the seat's measured 29.4-minute
mean is the number that stands between a defect and a lost transaction. With `transactions = 0` that
protection has never been exercised.

**Metrics it owns.**
1. **Red-to-alert latency** — target 60 min, actual **29.4 min**. Measured, green. It should additionally
   report its **floor** (~7.5 min from a 4×/hour cadence), because a 4× gap to floor is a finding hiding
   inside a green number.
2. **Duplicate pages per episode** — target **1.00**, provable today by the existing aborted-transaction
   probe but **not currently recorded as a running metric**. One count over `founder_alerts` grouped by
   `dedupe_key` makes it a live number.
3. **Missed reds** — **not measurable today**. Requires the `red_view` watermark that does not exist.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** (i) Add a `red_view` row to `alert_watermark` so the seat can detect its own
  silence and answer taxonomy #25 and #26. (ii) Fix the three statement-timeout paths with `it` and
  `backend_engineer` — this seat cannot fix them itself and must not try. (iii) Sit the ITIL 4 Foundation
  exam. (iv) Write its charter into `ops_knowledge` as real records; six of six `exam:` rows is not a
  knowledge base.
- **Q2 (Dec 2026–Feb 2027).** Add the zero-denominator flag so the six structurally-red business metrics
  report *"red because there is no demand yet"* rather than *"red"*. This is the difference between a
  dashboard the founder reads and one he learns to ignore.
- **Q3 (Mar–May 2027).** Cause-grouping on `red_episode`, so two symptoms of one routine page once. Close
  the two `fn_kernel_trace_integrity` episodes that have been open since 4 Sep.
- **Q4 (Jun–Aug 2027).** When reveals exist, add the reveal path itself as a monitored view with a
  minutes-level threshold; a failed payment must be a red inside one cycle, not one day.

**Capacity check.** Every milestone is one column, one row, or one exam. This is the smallest workload in
the department and it is entirely achievable. **The seat's real constraint is that it holds no repair
authority at all** — its Q1 (ii) depends wholly on `it` and `backend_engineer`, and its own job will keep
failing until they act. That is correct design and it should be stated rather than worked around.

**Dependencies.** `it` (every remediation and this seat's own cron), `backend_engineer` (batching the three
timing-out routines, the watermark row, the flags), `data_intel` (metric definitions and targets),
`qa_manager` (its probe), and — for Q4 and for six of its fourteen metrics to mean anything —
**the marketplace producing its first inquiry.**

**Is the slice achievable?** Yes on latency and duplicate-page rate: both are green or provable now.
**No on missed reds until the watermark exists**, and the plan does not claim otherwise. The larger honest
point: this seat's dashboard cannot be green while `inquiries = 0`, and no work by this department changes
that. It should report those six metrics as *structurally red pending demand*, and the founder should read
them that way.

### 9. What this seat cannot do without a model

1. **Writing the human-readable explanation of a red the estate has never seen before.** The template fills
   from `check_key`, `detail` and the measurement; a genuinely novel condition gets a correct but
   mechanical sentence.
2. **Deciding that two reds with unrelated `check_key`s share a hidden cause.** Grouping by namespace and
   routine is deterministic; inferring a causal link across namespaces is not. The deterministic fallback is
   to page both and say they are unlinked.
3. **Nothing else.** This is the most fully deterministic seat in the department, and with the watermark
   row added it needs no model at all to do its job completely.

---

## Department summary for the founder

**Six seats, all six answer with OpenRouter switched off.** Everything specified above is a table read, an
arithmetic step, a threshold lookup or a template fill; the only use of a model anywhere is the nineteen
items listed across the six section 9s (`cto` 3, `backend_engineer` 3, `it` 3, `security` 4, `qa_manager` 3,
`red_view_alerter` 3 — of which its third says *nothing else*). **None of them is on a customer's request
path**, and every one has a stated deterministic fallback: refuse and name what is missing.

**What is measured and green today**: platform availability 100.00% against 99.5%; agent-run reliability
98.23% (7d) against 97%; the smoke suite 15/15; the kernel exposure board green on all five checks;
red-to-alert latency 29.4 min against 60; AI spend AED 0.00 in the last seven days.

**What is measured and red today**: backup success 86.53% against 100%; one anon-executable
`SECURITY DEFINER` function open since at least 6 Sep and reported 50 times; five cron jobs unregistered;
136 of 206 edge functions with no mirrored source; 611 tables RLS-on with no policy; two
`fn_kernel_trace_integrity` episodes open since 4 Sep; the `security` seat's CISSP at 42.50% against a
70.00 pass mark, with *Security Assessment and Testing* failed on both attempts.

**What cannot be measured at all today, and is written as "does not exist" throughout**: a check→component
coverage map; a `check_verdict` table keyed by commit; a `suite` column on `qa_results`; a defect register;
a `security_finding` table with a remediation clock; owner/scope/expiry on `app_secrets`; a `red_view`
watermark; a table-growth history; a timed restore record; a labelled holdout set for RFQ qualification;
a `phase_c_component` history; a count of unnecessary `SECURITY DEFINER` routines; a `failure_class` column
on `agent_runs`; a zero-denominator flag on `metric_definition`.
**Every one of those is a single table or a single column — except the holdout set, which is a data problem
and is written as one, and the unnecessary-definer count, which is a single query nobody has run.**

**The honest position on AED 1,000,000.** `company_goals.revenue_annual` is owned by `finance`.
`product_eng` owns ten goals and none of them is revenue. At the measured 3.00% reveal rate, AED 1,000,000
requires **AED 33,333,333 of revealed selected-quote value**; how many reveals that is cannot be computed,
because `quotes` holds zero rows and the mean selected-quote value has never existed. This department's
slice is therefore **AED 0 of production and the whole of the protection** — and every plan above says so
rather than claiming a share of a number it does not move. The binding constraint on the company is not in
this department: it is `inquiries = 0` and `verified suppliers = 1` against a category-open threshold of 10.
