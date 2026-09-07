# Company brain — Data & Intelligence (`data_intel`)

Plan for the founder to approve. Nothing here has been applied to production.

**Positions covered.** The seven rows in `public.org_agents` where `active` and `department = 'data_intel'`:
`intel_director`, `knowledge_director`, `analytics`, `bi_analyst`, `market_analyst`, `supplier_analyst`,
`process_improvement_mgr`. (Seven further rows in this department are inactive — `analytics_director`,
`category_curator`, `forecast_analyst`, `kb_engineer`, `knowledge_validator`, `supplier_intel_analyst`,
`taxonomy_manager` — each carrying an `unavailable_reason` that moved its accountability to `intel_director`
or `knowledge_director`. Their work is folded into the live seats below; none is planned as a re-hire here.)

## The run-time constraint this plan is written to

The founder has said twice that nothing may depend on a language model at run time. Every resolver below is
one of five things and nothing else:

1. a SQL read of a named production table or view;
2. arithmetic on those reads (sums, ratios, medians, weighted scores, linear projections, closed-form
   statistical formulas);
3. a threshold comparison against a stored constant (`decision_policy`, `pricing_config`,
   `employee_kpi.target_value`, `company_goals.target_value`, a new `metric_definition` row);
4. retrieval — lexical (`tsvector` / `fts`, already on `kb_chunks`, `ops_knowledge.tsv`, `dept_library.tsv`)
   and semantic by the free in-region `gte-small` embedding (`kb_chunks.embedding_gte`,
   `ops_knowledge.embedding_gte`, `agent_knowledge.embedding_gte`, matched by `fn_ops_knowledge_match`,
   `kb_match`, `kb_query`);
5. template composition — a memo whose slots are filled by (1)–(4) and whose citations are the row ids read.

Question routing is the same, model-free: an incoming question is scored against the seat's stored taxonomy
rows by (a) `ts_rank_cd` over a `tsvector` of the question text, and (b) cosine distance to the taxonomy row's
`gte-small` embedding; the two are combined by reciprocal-rank fusion. Below a stored floor the seat refuses
and names what it would need. **A nearest neighbour is always found** — so a cosine hit alone never routes;
the lexical arm must also cover at least two content lexemes of the taxonomy row, matching the rule already
used by `fn_apply_playbook` (cosine ≥ 0.85 and ≥ 2 lexemes covering ≥ 30%).

Refusal text is a template, not a sentence a model writes: `cannot answer <type>: <named missing input> is
<empty | stale since <date> | below <n> rows>; opened org_task <id> against <role_id>`.

## What was measured, and when

All figures below were read from production `htdblwldjkcgjvmqkbeh` on **7 September 2026, 06:35–08:15 UTC**
(Dubai is UTC+4), read-only, with no paid model call and nothing written. Where a figure is quoted from the
6 September knowledge audit rather than re-measured, it says so.

**The department's own instruments.**

| Thing | Measured |
|---|---|
| `kb_chunks` | 2,686,026 rows; **147,138 embedded (5.48%)**; 27 `source_kind`s; 356 categories; 2,681,587 carry a citation; 2,591,966 carry an `effective_date` |
| embedding by kind | `qd_kb_pack` 90,488/90,488 · `textbook` 17,858/44,734 · `standard` 14,446/**2,061,332** · `guide` 7,512/30,300 · `regulation` 5,370/5,370 · `document` 2,864/2,864 · `trade` 2,055/2,055 · `spec` 1,918/1,918 · `syllabus` 1,412 · `generated` 1,317 · `framework` 817/898 · `company_faq` 484 · `cert` 174/85,240 · `reference` 224/298,669 · **zero embedded**: `code` 20,119, `handbook` 13,976, `book` 10,271, `manual` 4,772, `report` 3,835, `paper` 2,117, `biography` 1,646, `letters` 1,422, `methodology` 478, `study` 72 |
| `ops_knowledge` | 9,140 rows. In `fn_dept_scope('data_intel')`: `knowledge_eng` 278, `intelligence` 147, `analytics` 136, `data_intel` 110 (of which **101 are the 2 Sep `ops-data_intel-deep-*` records**). All embedded. **0 rows validated in any of the four.** The `knowledge` department's 413 rows sit outside the scope |
| `agent_knowledge` | 2,556 rows. `profession`: 1,611 unvalidated (159 embedded), 287 author_verified (0 embedded), 61 unsourced, 16 quarantined. `experience`: 381 quarantined, 99 unsourced, 53 unvalidated. `company` 46, `state` 2. **0 rows anywhere have a `review_due` in the past** |
| `dept_library` | legal 451, marketplace 361, assurance 318, finance 290, company 36. **data_intel: 0 rows** |
| `employee_knowledge` (12-layer curriculum binding) | intel_director 15, knowledge_director 15, market_analyst 15, supplier_analyst 15, analytics 13, process_improvement_mgr 11, **bi_analyst 0** |
| `employee_workflow` | intel_director 3, knowledge_director 3, process_improvement_mgr 2, analytics 1, market_analyst 1, **bi_analyst 0, supplier_analyst 0** |
| `metric_definition` | 14 rows, all with `measure_sql`, all active. Owners: it 3, exec 2, finance 2, supplier_success 3, knowledge 2, marketing 1, customer_success 1. **None owned by `data_intel`** |
| `metric_snapshot` | 1,218 rows; 87 per metric; last taken 2026-09-07 06:35:00 UTC; standing errors on `categories_live` (1) and `failed_runs_24h` (1) |
| `company_goals` | 64 rows. `data_intel` owns 4 (`categories_covered`, `knowledge_accuracy`, `knowledge_modules_complete`, `knowledge_review_cycle`), all with `measure_sql`. Company-wide, 32 active goals carry a `no_measure_reason` instead of SQL — 20 "NO INSTRUMENT EXISTS", 12 "THE NUMERATOR AND DENOMINATOR ARE A BUSINESS DECISION" |
| `goal_period` | 316 rows; **106 carry an `actual_value` (33.5%)**; data_intel's 4 all do |
| `employee_kpi` | 127 rows; the seven seats hold 14 between them (below), all measured at 2026-09-07 03:30 UTC |
| `experiments` | 2 rows, both `running` since 2026-07-06: `homepage_cta` → metric `reveal_conversion`, `supplier_invite_count` → metric `quotes_per_rfq`. `experiment_assignments` **1 row** (`visitor-123`). `experiment_events` **0 rows** |
| `knowledge_exam_results` | 2,422 rows overall (correct 819 · wrong 578 · partial 512 · not_covered 500 · unverifiable 13). The seven seats: **65 correct of 225 asked (28.9%)**, last sat 2026-09-07 03:23 UTC |
| `certification_exam_result` | 22 rows, for `bookkeeper`, `cs_support`, `marketing_analyst`, `procurement`, `security` only. **No seat in this department has ever sat its certification exam** |

**The business the department is supposed to measure.**

| Thing | Measured |
|---|---|
| `inquiries` | **0** |
| `quotes` | **0** |
| `transactions` | **0** (so `revenue_annual` measures 0 of AED 1,000,000) |
| `inquiry_matches` | **0** |
| `reveal_invoices` | **0** |
| `reviews` | **0** · `supplier_perf` **0** · `customer_score` **0** · `market_intel` **0** |
| `customers` | 1 |
| `leads` | 22,265 — 19,896 with an email, **0 with `email_verified = 'valid'`**, 6,937 with an E.164 phone, 11,569 with a website, 686 embedded, 1 `verified`, 1 with a trade-licence number, 2 with any reveal |
| lead lifecycle | `not_contacted` 22,090 · `no_response`/invite `sent` 161 · `undeliverable`/`bounced` 10 · `no_response`/no invite 3 · `registered`+`approved` **1** |
| `supplier_score` | 20,465 rows, last computed **2026-08-16 03:40 UTC**. `reliability` non-null on **2**; `price_index` **0**; `quality_rating` **0**; `quotes_submitted > 0` **0** |
| `supplier_capabilities` | 15,306 derived rows; `supplier_capability_confirmation` empty |
| supply floor | `v_supply_gap`: 86 categories, **0 at the 10-approved target**, 3 with any approved supplier |
| category knowledge | `v_category_coverage`: 86 categories, **84 with ≥ 8 standard modules** |
| `competitor` / `competitive_position` | 27 verified competitors; 8 scored dimensions — the department's single strongest evidence asset |
| `pricing_config` (id 1, updated 2026-09-06 14:22 UTC) | reveal rate 0.03 standard **and** 0.03 promo; caps 99,999,999; supplier registration AED 1,000 per year; `supplier_free_count` 1,000; refund window 5 working days; chase after 3 working days; `category_open_min_suppliers` 10; bank settlement 7–14 working days; `auto_approve_suppliers` true |

**The reading that follows from those two tables.** Every demand-side instrument this department owns is
dividing by zero. Nothing here is broken; nothing has happened yet. That single fact determines what each
seat can honestly be asked to do in year one, and it is stated plainly in every §8 below.

---

## intel_director — Data & Intelligence Director

`org_role.role_id = data_intelligence_director` · authority `execute_medium`, budget 0 · manager `ceo` ·
owns *metric definitions and their measurement SQL, which intelligence reaches the executive, forecast
methodology, knowledge governance priority* · forbidden *changing a department's reported actual, approving
its own analysis, setting a target* · outputs `metric_definition`, `intelligence_brief`, `forecast` ·
escalates to `ceo`, `chief_of_staff` · hands off to `knowledge_director`, `data_engineer`,
`forecasting_analyst` (inactive), `chief_performance_officer`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Is this number fit to leave the company (brief, board pack, investor line)? | gate | every brief, ~daily | ceo, brief, cfo | the founder acts on a false figure; the estate's credibility with him is the department's only asset |
| 2 | Which metric is the master metric this quarter — liquidity, reveals, or registered suppliers? | allocation | quarterly | ceo, founder | the whole company optimises a number that does not move revenue |
| 3 | Does a proposed KPI have a definition that can be measured in SQL today? | gate | ~weekly (127 `employee_kpi` rows) | any department head | a KPI is created that reads NULL forever and the seat looks idle when it is blocked |
| 4 | What is the denominator for this rate, exactly? | craft | every new metric | analytics, bi_analyst | "supplier response rate 1.0" measured over 2 leads is reported as 100% |
| 5 | Is a metric move signal or noise at this volume? | diagnosis | every alert | ceo, ops_director | the company reorganises around a two-event swing |
| 6 | Two surfaces report different values for the same metric — which is canonical? | escalation | on conflict | any | the founder loses the ability to trust any dashboard |
| 7 | Is the company on pace for AED 1,000,000 by 31 Aug 2027? | forecast | monthly | founder, ceo, cfo | a year is spent on the wrong constraint |
| 8 | What daily/weekly run rate is required from today to still hit the target? | forecast | monthly | ceo, cfo | the plan is set to a pace nobody has checked is reachable |
| 9 | Is this goal instrumentable at all, or does it need an instrument built first? | gate | on every new goal | ceo | 32 goals already sit unmeasured with a stated reason; adding a 33rd hides the backlog |
| 10 | Which of the unmeasured goals gets instrumented next? | sequencing | monthly | ceo | engineering time goes to a vanity goal while revenue stays unmeasured |
| 11 | May this experiment be concluded and its winner adopted? | gate | per experiment | ceo, growth | a winner is crowned on 1 assignment and 0 events (the live state today) |
| 12 | What effect size could we even detect at current traffic? | forecast | before any test | growth, product_eng | months are spent on a test that was never powered |
| 13 | Is this A/B test valid given that supply and demand interfere? | gate | per marketplace test | growth, marketplace | a supply-side test steals suppliers from its own control arm and reports a lift that is a transfer |
| 14 | Does this number contain fixture or demo rows? | gate | every reported figure | all | a `ZZ DEMO` supplier is counted as a registration in a founder brief |
| 15 | Is this KPI's unit consistent with what its `measure_sql` returns? | diagnosis | quarterly audit | own seat | see its own KPI #1 below: a count of failures is compared against a 100% target |
| 16 | Which department owns this metric? | allocation | on creation | ceo, chief_of_staff | nobody explains the variance because nobody owns it |
| 17 | Should this metric be retired? | gate | quarterly | own seat | 14 metrics are maintained; dead ones cost snapshot time and attention |
| 18 | What goes into this week's executive intelligence brief, and what is left out? | sequencing | weekly | ceo | the founder reads noise and misses the one binding constraint |
| 19 | Is this alert threshold too tight or too loose? | craft | on alert fatigue | it, ops_director | alerts are muted; a real one is missed |
| 20 | Is this zero a true zero or a dead instrument? | diagnosis | continuously | all | `market_intel` reading 0 for 30 days is read as "no market activity" instead of "nobody has written a row" |
| 21 | What is the correct cohort definition for supplier registration? | craft | on first cohort report | supply, growth | invite cohorts are mixed with claim cohorts and retention is meaningless |
| 22 | What is the reveal funnel conversion, by category and emirate? | diagnosis | monthly once demand exists | ceo, marketplace | capital goes to a category that cannot convert |
| 23 | Is a trailing-12-month total being reported as a run rate? | gate | every revenue statement | cfo, ceo | a one-off cluster of reveals is annualised and the plan is built on it |
| 24 | Is this measurement worth building — what does knowing it change? | allocation | per instrumentation request | any head | the department builds meters for decisions nobody makes |
| 25 | Which knowledge gap is currently blocking a revenue decision? | sequencing | weekly | knowledge_director | 2.5M chunks are curated while the one decision-blocking record is missing |
| 26 | Which seat gets the next instrumentation hour? | allocation | weekly | own department | the loudest KPI is fixed, not the binding one |
| 27 | A measured number contradicts something the founder believes — say so, or not? | escalation | rare, high stakes | own seat | the standing rule "never state what you have not measured" cuts both ways; silence is a lie by omission |
| 28 | Refuse to report a metric whose evidence is stale beyond its cadence | gate | continuously | own seat | `supplier_score` last computed 16 Aug is quoted on 7 Sep as current |
| 29 | Forecast supplier registrations against the 10-per-category floor across 86 categories | forecast | monthly | supply, ceo | the marketplace opens categories that cannot fill an RFQ |
| 30 | Forecast AI cost against the department budget | forecast | monthly | it, cfo | the bill outruns the plan silently |
| 31 | Which period boundary applies — UTC or Asia/Dubai? | craft | every periodic report | all | a Dubai working day is split across two reported days and month-end is wrong by four hours |
| 32 | Approve or refuse a department's proposed change to a metric definition | gate | ~monthly | any head | a definition is changed mid-period and the trend becomes uninterpretable |
| 33 | Is this variance volume, mix or rate? | diagnosis | monthly | bi_analyst, cfo | the remedy is aimed at price when the cause is mix |
| 34 | How many suppliers must answer a survey for the result to mean anything? | craft | per survey | supply, growth | a 6-response survey sets policy for 22,265 leads |
| 35 | May this competitor claim be cited in a public or investor document? | gate | per claim | growth, ceo, legal | an unsourced competitor claim is published; the market_analyst's own forbidden decision is breached |
| 36 | Is this KPI target achievable given the seat's actual capacity? | gate | at target-setting | ceo, people_ops | a seat is marked "failing" for a target arithmetic never allowed |
| 37 | Open a data-quality incident, or log it and move on? | escalation | on detection | own seat | a definition drift runs for a quarter before anyone notices |
| 38 | Which of two conflicting category taxonomies is canonical? | gate | on drift | knowledge_director, marketplace | supply counts and knowledge coverage stop reconciling |
| 39 | What confidence label does this forecast carry? | craft | per forecast | ceo | a wide-interval guess is read as a commitment |
| 40 | Stop measuring something entirely | allocation | quarterly | own seat | attention is a fixed budget; every live meter spends some |

### 2. Domain logic (the models this seat reasons with)

**M1 — Goal pace and required run rate.** Already deployed as `fn_goal_pace()`.
`frac = (current_date − created_at::date) / (deadline − created_at::date)`, clamped to [0,1];
`expected_at_pace = target × frac`; `behind_pace = actual < expected_at_pace`;
`required_run_rate_per_day = max(target − actual, 0) / days_remaining`.
Inputs: `company_goals` (target_value, deadline, direction, measure_sql), `goal_period` (actual_value,
horizon='annual', period_label = current year).
Output: one row per goal with attainment %, days remaining, required daily rate.
**Unmeasured:** the model only runs for goals that have both a `deadline` and a `measure_sql`. Measured today
that is a very small set — `revenue_annual` is the only revenue goal carrying a deadline (2027-08-31), and its
actual is 0 because `transactions` is empty. Every other year-one goal has `deadline = null` and is therefore
invisible to pace.

**M2 — Metric fitness gate.** A stored predicate, not a judgement:
`fit = has_definition ∧ has_measure_sql ∧ has_owner_dept ∧ (freshness ≤ cadence_days) ∧ (denominator ≥ n_min)
∧ fixture_excluded`.
`freshness` from `metric_snapshot.taken_at` / `employee_kpi.measured_at`; `cadence_days` from
`employee_kpi.cadence` (weekly = 7, monthly = 31, quarterly = 92); `n_min` a new stored column per metric;
`fixture_excluded` = the `measure_sql` text contains both the `@example.invalid` and `ZZ DEMO — ` predicates
(the pattern `suppliers_registered_monthly` already uses).
**Unmeasured:** `n_min` does not exist on any table today. `metric_definition` has no `min_denominator`
column, and `employee_kpi` has none either. Without it the gate cannot fire, and rates like
`supplier_response_rate = 1.0` over 2 rows pass as measured.

**M3 — Signal vs noise on a count metric.** For a count `k` over exposure `n`, the two-sided Poisson/normal
band: `expected ± 1.96 × sqrt(expected)`. A move is *reportable* only when the new value falls outside the
band computed from the trailing median of the last 8 snapshots of the same metric.
Inputs: `metric_snapshot` (87 snapshots per metric today, taken hourly-ish).
Output: `reportable | within_noise`, with the band printed.
**Unmeasured:** nothing — this is computable today from `metric_snapshot`, and is not currently computed
anywhere. `fn_emit_metric_alerts()` exists but fires on absolute target comparison, not on a band.

**M4 — Minimum detectable effect (MDE) for a two-arm test.** Closed form, no model:
`MDE = (z_{1−α/2} + z_{1−β}) × sqrt( 2 × p(1−p) / n_per_arm )`, with `z_{0.975}=1.96`, `z_{0.80}=0.8416`.
Inverted for planning: `n_per_arm = 2 p(1−p) (1.96 + 0.8416)² / MDE²`.
Inputs: baseline `p` from the metric's own history in `metric_snapshot` or from the funnel counts;
`n_per_arm` from `experiment_assignments`.
Output: the MDE the estate can currently detect, and the traffic required for a named target effect.
**Measured consequence:** with `experiment_assignments` holding **1 row** and `experiment_events` **0**, the
detectable effect at any conventional power is undefined — the correct output today is a refusal, not a
number.

**M5 — Experiment conclusion gate (replacing the deployed one).** `fn_experiment_conclude` today concludes an
experiment when the *smallest arm* reaches `p_min_subjects` and then crowns the arm with the highest raw
`conv_rate_pct`. It applies **no significance test at all**. The model this seat needs adds two stored gates
before a winner may be named:
`two_proportion_z = (p1 − p2) / sqrt( p̂(1−p̂)(1/n1 + 1/n2) )`, where `p̂ = (x1+x2)/(n1+n2)`; conclude only if
`|z| ≥ 1.96` **and** `min(n1,n2) ≥ n_min` **and** the observed difference ≥ the pre-registered MDE.
Everything in that formula is arithmetic available in plpgsql.
**Unmeasured:** the estate has no pre-registration record — no table stores an experiment's hypothesis,
primary metric, MDE and planned n before it starts. `experiments` carries only `key, status, metric,
variants, started_at, stopped_at`.

**M6 — Marketplace interference test.** A marketplace A/B test violates the no-spillover assumption when the
arms compete for the same finite supply. Deterministic check before any test is admitted:
`interfering = (unit_of_randomisation ∈ {visitor, inquiry}) ∧ (treatment touches supplier dispatch)
∧ (suppliers_per_category < 3 × match_max_fanout)`.
Inputs: `decision_policy.match_max_fanout` (5), `match_max_fanout_per_trade` (3), `v_supply_gap.approved`.
Output: `admit | switchback_only | refuse`.
**Measured consequence:** `v_supply_gap` shows 0 of 86 categories at the 10-approved floor and 3 with any
approved supplier, so every supply-side test on this estate today is interfering by construction, and the
correct verdict is `switchback_only` or `refuse`.

**M7 — Bottom-up revenue model for AED 1,000,000.**
`revenue = Σ_categories ( inquiries × match_rate × quote_rate × reveal_rate × average_quote_value × 0.03 )`,
minus refunds (`refund_confirmed_at is not null`).
Inputs: `pricing_config.standard_reveal_rate` (0.03, measured), `inquiries`, `inquiry_matches`, `quotes`,
`transactions`, `v_supply_gap.approved` as the capacity ceiling on `match_rate`.
Output: revenue per category per month and the implied inquiry count.
**Unmeasured:** every multiplier except the 3%. `inquiries` 0, `inquiry_matches` 0, `quotes` 0,
`transactions` 0 — so `match_rate`, `quote_rate`, `reveal_rate` and `average_quote_value` have no empirical
value on this estate at all. The model is correct and cannot be run; its inputs must come from an assumption
register the founder signs, and each assumption must carry the row count that would replace it.

**M8 — Value of information.** `VOI = P(decision flips) × (value of the better branch − value of the branch
taken by default)`, compared against the build cost in engineering hours.
Inputs: the decision's own catalogue row; `department_budget`; the cost side from `ai_cost_log` and an hours
estimate.
Output: build / do not build / build a cheaper proxy.
**Unmeasured:** no table records what a decision is worth or which decisions are pending; `decision_record`
holds 12 rows and `decision_log` 935, neither carrying a value. This is a real gap and the reason the
department currently instruments what is easy rather than what is binding.

**M9 — Variance decomposition (volume / mix / rate).** For a metric `V = Σ_i q_i × r_i`:
volume effect `= (Q₁ − Q₀) × r₀`; mix effect `= Q₁ × Σ_i (w_i1 − w_i0) × r_i0`; rate effect
`= Q₁ × Σ_i w_i1 × (r_i1 − r_i0)`; residual is the cross term.
Inputs: any two periods of `goal_period` / `metric_snapshot` with a category or emirate dimension.
**Unmeasured:** no metric in `metric_definition` is stored with a dimension. All 14 return a single scalar,
so the decomposition has nothing to decompose against. This is the concrete reason `bi_analyst`'s KPI
"variance explained with a root cause" sits at 78.35% against 90 — the method has no dimensional input.

### 3. Reasoning procedures

**Type 1 — "Is this number fit to leave the company?"**
1. Resolve the metric key. If the caller named a label rather than a key, match against `metric_definition.label`
   and `employee_kpi.metric` by lexical rank; ambiguity between two keys stops here and asks which.
2. Read the row: `measure_sql`, `owner_dept`, `direction`, `target`.
3. Read the freshest value and its timestamp: `metric_snapshot` (max `taken_at`) or `employee_kpi.actual_value`
   / `measured_at`.
4. Apply M2. Any failed clause is a stop.
5. Compute the denominator by running the `measure_sql`'s own `from` clause with `count(*)` substituted. If
   `denominator < n_min` → **refuse**, and print the denominator.
6. Apply M3 against the trailing 8 snapshots. If inside the band, the number is emitted with the band, and the
   memo says "not distinguishable from the last eight readings".
7. Compose: value, as-of timestamp, denominator, band, `measure_sql` text, `metric_definition` row id.
   **Stops:** stale beyond cadence; denominator below floor; `measure_sql` missing a fixture filter; the metric
   has no `owner_dept`.

**Type 7 — "Are we on pace for AED 1,000,000?"**
1. Read `company_goals` where `key = 'revenue_annual'` — target 1,000,000 AED, deadline 2027-08-31,
   `direction = at_least`.
2. Read the actual by executing its stored `measure_sql` (sum of `reveal_fee`/`app_fee` over 365 days where
   `refund_confirmed_at is null`).
3. Apply M1. Print `time_elapsed_pct`, `attainment_pct`, `required_run_rate_per_day`.
4. Convert the required rate into physical units through M7 in reverse: required reveals per day
   `= required_AED_per_day / (average_quote_value × 0.03)`; required inquiries per day
   `= required_reveals / (match_rate × quote_rate × reveal_rate)`.
5. **Stop condition, and the one that fires today:** any multiplier in step 4 has no measured value.
   The seat must then emit the pace arithmetic it *can* do (attainment 0.0%, required run rate from today) and
   **refuse** the conversion, naming `inquiries`, `inquiry_matches`, `quotes`, `transactions` as empty and
   citing the assumption register as the only lawful substitute.
6. Never annualise a partial period (rule J-7 below).

**Type 11 — "May this experiment be concluded?"**
1. Read `experiments` for status and metric; read the pre-registration row (does not exist — stop here today).
2. Count assignments per arm from `experiment_assignments`; count converting subjects per arm from
   `experiment_events` where `event = 'convert'`.
3. Apply M6. `refuse` or `switchback_only` ends the procedure.
4. Apply M4 to confirm the planned n was reached.
5. Apply M5. Only a `|z| ≥ 1.96` with `min(n) ≥ n_min` and effect ≥ pre-registered MDE may name a winner.
6. Compose the verdict with both arms' n, both conversion rates, the z, the p-value read from a stored normal
   table (a 200-row lookup, not a function call), and the decision.
   **Today's honest output for both live experiments:** `cannot conclude: homepage_cta has 1 assignment across
   2 arms and 0 conversion events; supplier_invite_count has 0 assignments. Both have been running since
   2026-07-06. Recommend stopping both as never-instrumented rather than concluding them.`

**Type 20 — "Is this zero a true zero or a dead instrument?"**
1. Read the metric's value history from `metric_snapshot` / `employee_kpi_history` (1,332 rows).
2. Classify: **never non-zero** → suspect instrument; **was non-zero, now zero** → suspect business;
   **error column non-null** → broken.
3. Independently count the underlying table the `measure_sql` reads. If the table has rows but the metric
   reads 0, the predicate is wrong. If the table is empty, the zero is true.
4. Check the writer: is there a cron in `cron_registry` (213 rows) that is supposed to write that table, and
   when did it last succeed (`cron_job_seen`, 234 rows)?
5. Verdict: `true_zero(business) | dead_writer(cron <id> last ok <date>) | wrong_predicate | broken_sql`.
   **Worked today:** `market_intel` = 0 rows, KPI target 20/month, actual 0 — the table has never held a row
   and no cron writes it → `dead_writer`, not a market with no events.

**Type 15 — "Is this KPI's unit consistent with its SQL?"**
1. Parse the stored `measure_sql` for its outermost aggregate: `count(...)` → count; `round(100.0 * ... )` →
   percent; `avg(...)` → mean; `sum(...)` → total.
2. Compare against `employee_kpi.unit`.
3. Compare `direction` against the aggregate's polarity (a count of failures with `unit = '%'` and
   `target = 100` is a contradiction).
4. Verdict: `consistent | unit_mismatch | polarity_mismatch`.
   **Worked today on this seat's own KPI:** *"Categories with all eight knowledge modules"* has
   `target_value = 100`, `unit = '%'`, and `measure_sql = select count(*)::numeric from v_category_coverage
   where coalesce(standard_modules,0) < 8`. That returns a **count of categories that fail**, currently 2.
   True coverage measured independently is **84 of 86 = 97.7%**. The KPI reports 2 against 100 and the
   director is recorded as failing a target it is in fact within 2 categories of meeting. Verdict:
   `unit_mismatch ∧ polarity_mismatch`. This is the department's own house and is the first thing to fix.

**Type 24 — "Is this measurement worth building?"**
1. Identify the decision the metric would inform, from the asking seat's own taxonomy id.
2. Read the decision's default branch (what happens with no measurement).
3. Estimate `P(flip)` from a stored three-point prior (0.1 / 0.3 / 0.6 chosen by whether the metric has ever
   disagreed with the default in this estate's history).
4. Value the branches from `company_goals.target_value` proportionality — the share of the AED 1M the
   decision moves.
5. Cost: engineering hours × a stored hourly constant, plus the recurring snapshot cost.
6. Verdict: build if `VOI > 3 × cost` (rule J-9). **Stop:** if no decision can be named, refuse — a metric
   with no decision behind it is not built.

**Type 27 — "A measured number contradicts the founder."**
1. Re-measure independently: a second `measure_sql` over a different table reaching the same quantity.
2. If the two agree, the contradiction is real.
3. Compose a memo that states what was measured, its boundary, and what was *not* measured — never a
   correction of the founder's belief, a statement of the evidence.
4. Route it as an exception through `fn_notify_founder` with the right `p_kind` (a new kind needs a
   `founder_mail_policy` row first — 58 exist).
5. **Never** soften the number, and never delay it to a scheduled brief.

### 4. Judgement rules

- **J-1.** `denominator < n_min` → refuse to report a rate; report the raw counts instead.
  *Reason: a rate over 2 rows is a number with no information; `supplier_response_rate` over 2 leads is the
  live example.*
- **J-2.** `value = 0` **and** the metric has never been non-zero → report as *"instrument unverified"*, not as
  zero. *Reason: zero cannot tell a dead guard from an idle system.*
- **J-3.** `now() − measured_at > cadence_days` → the number does not leave the department. *Reason:
  `supplier_score` last computed 2026-08-16; anything quoting it today is quoting a three-week-old estate.*
- **J-4.** A `measure_sql` without both fixture predicates (`@example.invalid`, `ZZ DEMO — `) may not be
  registered. *Reason: a rehearsal supplier counted as a registration is fabricated revenue evidence.*
- **J-5.** No metric definition changes inside an open period. Changes take effect at the next period boundary
  and the old definition is kept with its end date. *Reason: a definition change mid-period destroys the trend
  the change was made to improve.*
- **J-6.** The seat never sets a target and never changes another department's reported actual — both are in
  its `forbidden_decisions`. It may say a target is unreachable; it may not move it.
- **J-7.** A trailing-N-day total is never presented as a run rate. Any annualised figure must state the number
  of periods it was computed from, and fewer than 3 complete periods forbids annualising at all.
- **J-8.** An experiment may not be concluded without `|z| ≥ 1.96`, `min(n_arm) ≥ n_min`, and an observed
  effect at least the pre-registered MDE — **even though the deployed `fn_experiment_conclude` will conclude
  without any of them.** This is the "do not do this even though it scores well" rule for this seat: the code
  path exists and will crown a winner; the seat must refuse to adopt it.
- **J-9.** Build a meter only when `VOI > 3 × build cost`. *Reason: the estate has 14 live metrics and 32
  unmeasured goals; the constraint is attention, not SQL.*
- **J-10.** Two surfaces disagree → **both stop being quoted** until one is declared canonical in
  `metric_definition`. Do not pick the one that flatters.
- **J-11.** A fix that makes the headline fall is still the fix, and the fall is reported in the same memo as
  the fix. *Founder's standing rule; this seat is where it binds hardest.*
- **J-12.** Escalate to `ceo` when a measurement contradicts a stated company plan by more than 25% of target,
  or when a goal's `required_run_rate_per_day` exceeds 3× the best rate ever observed. Escalate to
  `chief_of_staff` when two departments dispute ownership of a number.
- **J-13.** Period boundaries are UTC for machine metrics and Asia/Dubai (UTC+4) for anything a human reads as
  "today" or "this month". Every reported period states which. *Reason: a Dubai working day straddles two UTC
  days and month-end differs by four hours.*
- **J-14.** Any number that will reach the founder carries its own falsification condition — "this would be
  wrong if X" — computed, not written by hand.
- **J-15.** Never present a forecast without its assumption register; a forecast whose multipliers are all
  assumed is labelled *scenario*, never *forecast*.

### 5. Technical knowledge

Must be stored so the seat acts without asking anyone:

- **The measurement estate as built.** `metric_definition` (14 rows, key/label/domain/definition/measure_sql/
  target/direction/owner_dept/active), `metric_snapshot` (metric_key/value/error/taken_at),
  `company_goals` (key/goal/metric/target_value/unit/period/owner_dept/measure_sql/horizon/direction/
  no_measure_reason/deadline), `goal_period` (goal_key/horizon/period_label/target/actual/owner_dept/status),
  `employee_kpi` (agent_key/kpi/metric/target_value/unit/cadence/serves_goal/measure_sql/actual_value/
  measured_at/no_measure_reason/kpi_class), `employee_kpi_history` (1,332 rows).
- **The routines that already do this work,** with what each returns and its known limits:
  `fn_goal_pace()`, `fn_goal_attainment(horizon)`, `fn_goal_decompose()`, `fn_goal_period_refresh()`,
  `fn_employee_kpi_measure()`, `fn_employee_kpi_assign()`, `fn_kpi_review()`, `fn_kpi_scoreboard()`,
  `fn_bi_snapshot()`, `fn_org_scorecard()`, `fn_data_metrics()`, `fn_ops_metrics()`, `fn_quality_metrics()`,
  `fn_strategy_metrics()`, `fn_marketplace_analytics()`, `funnel_metrics(days)`, `fn_emit_metric_alerts()`,
  `fn_metric_class(label, metric, unit)`, `fn_company_snapshot()`, `fn_finance_forecast()`,
  `fn_customer_forecast(customer, horizon_days)`.
- **The experiment machinery and its defect:** `fn_experiment_assign(key, subject)`,
  `fn_experiment_record(key, subject, event, value)`, `fn_experiment_results(key)` (returns per-variant
  subjects / conversions / conv_rate_pct — no test statistic), `fn_experiment_conclude(min_subjects)`
  (concludes on raw rate ordering, files an `fn_agent_decision` for adoption).
- **The `measure_sql` contract:** one numeric scalar; period-bounded; null-safe via `nullif`; fixture-excluded;
  must complete inside the estate's 8-second statement timeout; must not read a view that reads it back.
- **Postgres for analytics on this estate:** window functions, `date_trunc`, `filter (where …)` aggregates,
  `generate_series` for dense periods, partial indexes, `EXPLAIN` reading, and the fact that
  `count(*)` over `kb_chunks` (2.68M rows) is a seconds-scale scan that has previously timed out jobs.
- **Time:** `now() at time zone 'utc'` is the canonical clock; Dubai is UTC+4 with no DST; the UAE working
  week is Monday–Friday with Saturday–Sunday weekend, which is what `chase_after_working_days = 3` and
  `refund_window_working_days = 5` count in.
- **The event and trace fabric** the department reports on: `company_event` (2,607), `event_rollup` (2,197),
  `event_delivery`, `decision_trace` (1,735), `phase_c_trace` (53,703), `agent_runs` (40,373),
  `workflow_step_run` (27,117), `org_tasks` (2,466).
- **The founder's channels:** `founder_mail_policy` (58 rows) gates what may be emailed; every other
  notification routes through `fn_founder_mail_route` into one owned org task; WhatsApp is his command channel.
  A new alert kind needs a policy row before it can exist.

### 6. Academic knowledge

Disciplines and the specific frameworks, each with a lawful primary source we may ingest. No copyrighted study
texts.

| Discipline | Framework the seat needs | Lawful primary source |
|---|---|---|
| Statistical inference | Two-proportion z-test, confidence intervals, Poisson counting bands, multiple-comparison control | NIST/SEMATECH *e-Handbook of Statistical Methods* (US Dept of Commerce, public domain) |
| Experiment design | Randomisation units, pre-registration, sequential testing, switchback designs for interference | Published methodology papers on arXiv/journals with open licences; the estate's own `ops-data_intel-deep-*` records on network interference (101 rows, already present) |
| Measurement systems / data management | DAMA-DMBOK knowledge areas: data quality dimensions, metadata, master data, governance | DAMA-DMBOK is already present in `kb_chunks` (1,371 chunks per the 6 Sep audit) but is **outside `fn_dept_scope('data_intel')`** — a scope change, not an ingest |
| Forecasting | Bottom-up unit-economics forecasting; forecast error tracking (MAPE, MASE); base rates | Open forecasting-competition documentation (M-competitions) and public methodology papers |
| Official statistics | Series definitions, revision policy, seasonal adjustment conventions | UAE Federal Competitiveness and Statistics Centre; Dubai Statistics Centre; Abu Dhabi Statistics Centre — all publish their own methodology notes under open terms (**verify licence per portal**) |
| National accounts / construction demand | Construction and real-estate output series that drive UAE B2B RFQ demand | Dubai Statistics Centre construction and GDP bulletins; Dubai Land Department / RERA published data (**verify**) |
| Quality management | Control charts, common vs special cause | NIST e-Handbook (chapter 6, Process/Product Monitoring and Control) |
| Information economics | Value of information, expected value of perfect information | Public decision-analysis literature and standards-body guidance |

**Certifications this seat holds** (`public.role_certification`):

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | CAP (Certified Analytics Professional) | INFORMS | 70% | Business Problem Framing · Analytics Problem Framing · Data · Methodology Selection · Model Building · Deployment · Model Lifecycle Management |
| 2 | CDMP (Certified Data Management Professional) | DAMA | 60% | Data Governance · Data Architecture · Data Modelling and Design · Data Quality · Metadata Management · Master and Reference Data Management · Data Warehousing and BI · Data Security |

**Syllabus areas it failed: does not exist.** `certification_exam_result` holds 22 rows and none is for this
seat — no seat in `data_intel` has ever sat its certification exam, so there is no per-area failure record to
cross-reference. What *does* exist is the older lexical knowledge exam: **10 correct of 30 asked (33.3%)**,
9 wrong, 9 partial, 2 not covered, mean grader confidence 0.48, last sat 2026-09-07 03:23 UTC, with **8
answers written back into `agent_knowledge` as "experience"** — 7 of them from wrong verdicts, per the 6 Sep
audit. Until the exam grades the CAP and CDMP areas above rather than file recall, "what it failed" is not a
measurable statement about this seat.

### 7. Corporate knowledge

- **The founder's hard rules, as numbers this seat must use, not prose:** the reveal fee is **3%** of quote
  value paid by the buyer (`pricing_config.standard_reveal_rate = 0.03`, cap 99,999,999); supplier
  registration **AED 1,000/year** with the first **1,000** suppliers free (`supplier_free_count`); the
  non-response refund ladder is **5 working days** to the founder's call with a chase at **3 working days**
  (`refund_window_working_days`, `chase_after_working_days`), refunding the 3% plus **9% per annum** interest
  and a flat **AED 250** admin fee charged to the supplier (`decision_policy.refund_late_fee_annual_pct`,
  `refund_admin_fee_aed`); anti-circumvention **AED 15,000 or 3×** the reveal fee; a category opens at **10**
  approved suppliers (`category_open_min_suppliers`); the top-3 comparison is what the buyer is shown.
- **The only founder-reserved decision is a refund.** `decision_policy.founder_review_gates =
  ["refund_decision","refund_outside_policy"]` (updated 2026-09-05). Marketing, budget, legal, strategy,
  partnership and security decisions belong to their accountable roles. This seat escalates to `ceo` and
  `chief_of_staff`, never to the founder, except through `fn_notify_founder` with a `founder_mail_policy` kind.
- **The autonomy constants it reasons inside:** `auto_action_max_aed = 0` (no agent moves money),
  `financial_review_aed = 10,000`, `confidence_min = 0.6`, `fraud_score_max = 0.7`,
  `matching_strike_limit = 3`, `match_relevance_floor = 35`, `match_max_fanout = 5`,
  `match_max_fanout_per_trade = 3`, `event_recur_cooldown_days = 7`, `dispatch_max_batch = 500`,
  `dispatch_max_open_per_dept = 250`. All live in `public.decision_policy` (39 rows) and **no context routine
  reads them into any agent's prompt today** — the 6 Sep audit's finding, unchanged.
- **Its own KPIs and their measured state (2026-09-07 03:30 UTC):** Categories with all eight knowledge
  modules 2 vs 100 (**the unit defect in §3**); Category list matches the specification 2 vs 0; Exam coverage
  1.85% vs 80; Forecasts produced 2 vs 4; Goal periods tracked 33.54% vs 80; KPI instrumentation 88.33% vs 100.
  Five of six read as missed; one of those five is an instrument defect, not a performance one.
- **What the department owns and does not own.** It owns metric definitions and the SQL behind them — yet
  **zero of the 14 `metric_definition` rows name `data_intel` as `owner_dept`**. Ownership of the company's
  metric dictionary exists in the role definition and not in the table. That is the single largest corporate
  inconsistency in this department.
- **The competitive position it must not re-derive:** `competitive_position` holds 8 scored dimensions against
  27 verified competitors — anonymity (no competitor offers it), price discovery, verification, buyer cost
  (3% vs universally free), supplier cost, category depth (incumbents an order of magnitude deeper),
  speed to first quote (unproven, structurally batch), distribution (no asset). This is the company's best
  evidence and this department is its custodian.
- **History it must not forget:** phase freezes were lifted 2026-09-02; mirror gates are retired — production
  proves properties and a CSV never greens a check; paid inference is held and deterministic code is the
  standard; the 6 Sep plumbing fix restored LAYER 2 for 54/54 agents and restarted the embedding backfill.
- **Where each lives:** `pricing_config`, `decision_policy`, `company_goals`, `goal_period`, `employee_kpi`,
  `metric_definition`, `competitor`, `competitive_position`, `founder_mail_policy`, `org_role`,
  `employee_authority`, `docs/KNOWLEDGE_PLAN_2026-09-06.md`, `docs/knowledge_audit/data_intel.md`.
  **Does not exist:** an experiment pre-registration table; a metric-change log; a decision register carrying
  the value of a decision; a `min_denominator` on any metric; an assumption register for the revenue model.

### 8. One-year plan

**Objective.** Make every number the company acts on measurable, and make the AED 1,000,000 path arithmetic
rather than belief.

**Slice of the AED 1,000,000: AED 0 directly, and the whole of it indirectly.** This seat sells nothing. Its
honest slice is *the share of the target that is measurable and paced* — today 0 of 1,000,000, because
`transactions` is empty and `revenue_annual`'s own `measure_sql` returns 0. Any revenue number attributed to
this seat would be fabricated.

**Metrics it owns (all three need creating; none exists today):**
1. `measurable_goal_pct` — active `company_goals` with a working `measure_sql` ÷ active goals. Baseline
   measured: 32 of 64 rows carry a `no_measure_reason` instead of SQL.
2. `goal_periods_with_actual_pct` — already measured at **33.54%** against a target of 80.
3. `reported_number_defect_rate` — reported figures failing the M2 fitness gate, per quarter. No baseline;
   the gate does not exist yet.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** Fix the two unit defects in its own KPIs. Register the 8 marketplace metric
  definitions this department should own (fill_rate by category × emirate, match_rate, time_to_first_quote
  median, quotes_per_rfq, reveal_rate, take_rate, supplier_response_rate, repeat_buyer_30d) with
  `owner_dept = 'data_intel'`, `min_denominator` and fixture predicates — each one **defined and refusing**
  until its table has rows. Stop both zombie experiments and write the pre-registration table.
- **Q2 (Dec 2026 – Feb 2027).** Stand up M1–M3 as routines and put the fitness gate in front of every number
  that reaches the `intelligence_brief` output contract. Publish the assumption register for M7 with the
  founder's sign-off on each multiplier.
- **Q3 (Mar–May 2027).** First real cohorts, if demand exists: reveal funnel by category, supplier
  registration cohorts, variance decomposition with a live dimension.
- **Q4 (Jun–Aug 2027).** Forecast error tracking on M7 (MAPE against actuals), and the go/no-go read on the
  AED 1M with the falsification condition attached.

**Capacity check.** The work is SQL authoring and threshold registration, all inside the estate's own
routines. `max_open_tasks` is 50 and the seat ran 9 deterministic lane tasks in the last 7 days per the 6 Sep
audit — capacity is not the constraint. The constraint is that **eight of the eleven metrics it should own
divide by an empty table.** The seat can build correct meters this quarter; it cannot make them read
non-zero.

**Dependencies.** `supply` and `growth` must produce inquiries and registrations before any funnel metric has
a denominator. `finance` owns `revenue_annual`; this seat owns whether its number is fit to report. `product_eng`
owns the tables the meters read. `knowledge_director` owns the corpus the seat's own answers cite.

**Plainly: this seat's year-one slice is achievable as instrumentation and not achievable as revenue.**
What would make the revenue half achievable is a single working demand loop — one category with ≥ 10 approved
suppliers, real inquiries, and at least one paid reveal. Until then every forecast this seat produces is a
scenario and must be labelled one.

### 9. What this seat cannot do without a model

- Reading an ambiguous free-text question from the founder that matches no taxonomy row above threshold.
  The deterministic path is a refusal that names the closest three types it does know — which is the right
  behaviour, but it is a refusal, not an answer.
- Writing the *narrative* of a variance in natural prose beyond the templated volume/mix/rate sentence. The
  arithmetic is deterministic; the phrasing is a filled template and will read as one.
- Judging whether a *new* kind of metric proposed in free text is conceptually sound. It can check the
  mechanical clauses (SQL parses, denominator exists, fixture filter present); it cannot tell that a
  well-formed metric measures the wrong thing.

---

## knowledge_director — Knowledge Director

`org_role.role_id = knowledge_director` · authority `execute_low`, budget 0 · manager `intel_director` ·
owns *corpus structure and scope, what counts as validated knowledge, knowledge priority and freshness
policy* · forbidden *validating a lesson it proposed, changing the taxonomy, deleting knowledge without
provenance* · outputs `knowledge_plan`, `validation_decision` · escalates to `data_intelligence_director`,
`chief_of_staff` · hands off to `knowledge_engineer`, `knowledge_validator`, `taxonomy_manager`,
`category_curator` — **all four of those hand-off targets are inactive seats**, so every hand-off currently
returns to this desk.

Authority: `knowledge_fill` autonomous, `knowledge_acquire` autonomous ("may pull from approved external
sources"), both at threshold 0.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Does this knowledge record count as validated? | gate | per record, thousands pending | any authoring seat | 0 of 9,140 `ops_knowledge` rows are validated today; calling them validated makes the exam meaningless |
| 2 | Which of the 2,538,888 un-embedded chunks gets embedded next? | allocation | every backfill tick | own seat | the free embedding budget is spent on `biography` and `letters` while `regulation` and `trade` starve |
| 3 | Is this chunk in a category any agent can actually reach? | gate | per ingest | own seat, kb_engineer | knowledge is ingested into a category outside every `fn_dept_scope` and is invisible forever |
| 4 | Should this record be quarantined? | gate | continuously | own seat | 381 `experience` rows are already quarantined; wrong calls either poison agents or delete real lessons |
| 5 | Is this knowledge stale? | diagnosis | per cadence | all seats | a supplier answers a 2026 question from a 2024 regulation |
| 6 | Which department scope does this record belong to? | allocation | per ingest | any department | the `knowledge` department's 413 records sit outside `fn_dept_scope('data_intel')` and reach nobody in it |
| 7 | Is retrieval finding the right thing for this question type? | diagnosis | weekly | all seats | agents answer confidently from the nearest neighbour, which is always found |
| 8 | Should we ingest this source at all? | gate | per proposal | intel_director, market_analyst | a copyrighted study text is ingested; a licence breach with no upside |
| 9 | Is this source lawful to ingest? | gate | per source | own seat, legal | as above; this is a hard red line |
| 10 | What is the citation for this claim? | craft | per answer | every seat | an agent states a fact with no provenance; the founder's rule is breached |
| 11 | Which of the 86 categories has a knowledge hole that blocks an RFQ? | sequencing | monthly | marketplace, supply | an RFQ arrives in a category the platform cannot qualify |
| 12 | Should this record supersede that one? | gate | per revision | authoring seats | two contradictory records both stay live and agents answer either way |
| 13 | Is the corpus growing in the direction the business needs? | diagnosis | monthly | intel_director | 2.06M `standard` chunks and 0.2% UAE content is not a UAE B2B corpus |
| 14 | What is the review interval for this layer? | craft | per record class | own seat | 0 of 2,556 `agent_knowledge` rows have an overdue `review_due` — the decay loop has nothing to act on |
| 15 | Is this exam question fair to this seat's remit? | gate | per exam cycle | people_ops, own seat | supplier-category YAML is asked of a knowledge director and the fill poisons its experience layer |
| 16 | Should a wrong exam verdict be written back as knowledge? | gate | per exam item | own seat | **9 of this seat's own 30 exam answers were filled**; the fill is the pollution mechanism |
| 17 | Which knowledge does the revenue loop actually need first? | sequencing | monthly | intel_director, ceo | months of curation buy nothing the marketplace can use |
| 18 | Is this record's confidence still earned? | diagnosis | per decay cycle | own seat | confidence decays on a clock rather than on evidence |
| 19 | Open a corpus-quality incident? | escalation | on detection | own seat | a bad ingest run pollutes 30,000 chunks and nobody notices |
| 20 | Roll back an ingestion run? | gate | on defect | own seat | `knowledge_ingestion_undo` holds 32,825 rows; using it wrongly deletes good knowledge |
| 21 | Is this chunk size and overlap right for retrieval? | craft | per source kind | own seat | 211-character click-step chunks retrieve nothing useful |
| 22 | Should this record be `deterministic = true` (enters LAYER 2f)? | gate | per policy record | own seat | a soft heuristic enters the prompt as a hard rule |
| 23 | Which records go into the empty `dept_library` for this department? | allocation | once, then monthly | own seat | `dept_library` has 0 rows for data_intel; LAYER 2b returns company FAQ instead |
| 24 | Is a duplicate record entering the corpus? | gate | per ingest | own seat | the same standard is retrieved three times and crowds out the answer |
| 25 | Is a record's `effective_date` real or inferred? | diagnosis | per ingest | own seat | 2,591,966 chunks carry a date; a wrong one makes stale content look current |
| 26 | Does this agent have the curriculum layers its role requires? | gate | monthly | people_ops | `bi_analyst` has **0** `employee_knowledge` rows and 0 workflows |
| 27 | Which knowledge gap became a task, and did the task close it? | diagnosis | weekly | own seat | gaps are logged and never closed; the loop looks alive and is not |
| 28 | Is the embedding job alive? | diagnosis | daily | own seat, it | a stalled backfill reads exactly like a finished one |
| 29 | Is retrieval scoped, or is it searching all 356 categories? | gate | per retrieval path | product_eng | unscoped `k = 8` over 2.68M chunks returns plausible irrelevance |
| 30 | Does a company fact belong in a table or in a record? | gate | per fact | all | a fact written as a record goes stale; written in a table it renders every 15 minutes |
| 31 | Is this record reachable at run time (`runtime_eligible`)? | gate | per record | own seat | knowledge exists and never reaches a prompt |
| 32 | Retire a knowledge domain? | allocation | quarterly | own seat | 107 `knowledge_domain` rows; dead ones dilute every scope |
| 33 | Which seat authored this and may it review it? | gate | per validation | own seat | self-validation; explicitly forbidden for this role |
| 34 | Is the corpus lawful to hold under PDPL? | gate | per ingest of personal data | legal, own seat | personal data enters a retrieval corpus with no basis |
| 35 | Is a translation needed (Arabic) for this record? | craft | per public-facing record | growth, legal | 0 of 484 FAQ rows are Arabic in a market where Arabic is an official language |
| 36 | Should an agent's answer have refused instead? | diagnosis | per exam / per run | own seat | agents answer rather than decline; `bi_analyst` was wrong on 20 of 36 and declined on 0 |

### 2. Domain logic

**K1 — Embedding priority score.** The backfill picker must rank the remaining set, never walk its own
successes.
`priority = w_reach × reach + w_decision × decision_weight + w_recency × recency − w_cost × tokens`,
where `reach` = number of `fn_dept_scope` scopes containing the chunk's category ÷ 10;
`decision_weight` = 1.0 for `regulation`, `trade`, `spec`, `qd_kb_pack`, `company_faq`; 0.6 for `guide`,
`framework`, `syllabus`; 0.2 for `textbook`, `standard`, `reference`; 0.0 for `biography`, `letters`;
`recency` from `effective_date`.
Inputs: `kb_chunks` (source_kind, category, effective_date, `embedding_gte is null`), `kb_category_stats`
(624 rows), `fn_dept_scope`.
Output: an ordered claim set for `fn_kb_embed_claim(limit, source_kinds, categories, newest)` — which already
takes exactly these arguments.
**Measured today:** 147,138 of 2,686,026 embedded (5.48%). `code` 20,119, `handbook` 13,976, `book` 10,271,
`manual` 4,772, `report` 3,835, `paper` 2,117, `biography` 1,646, `letters` 1,422, `methodology` 478,
`study` 72 are **entirely un-embedded**; `standard` is 14,446 of 2,061,332 (0.7%) and `reference` 224 of
298,669 (0.08%). The picker exists; the priority score does not.

**K2 — Validation state machine.** States: `unvalidated → author_verified → validated → superseded`, with
`quarantined` reachable from any state and `unsourced` as an entry defect.
Transition rules are stored predicates, not judgement:
`author_verified` requires a non-null `source_ref` **and** an author ≠ null;
`validated` requires `author_verified` ∧ a reviewer ≠ the author ∧ at least one corroborating record
(cosine ≥ 0.85 to a different `source_ref`) ∧ no contradicting record;
`quarantined` fires on any of: `source_ref is null`, the record was written by the exam fill from a wrong
verdict, the record's scope does not match the holder's `fn_dept_scope`, or `confidence < floor`.
Inputs: `agent_knowledge` (validation_status, confidence, source_ref, supersedes_id, owner_agent),
`ops_knowledge` (validation_status, source_ids, supersedes_id, supersession_state), `kb_revisions` (11,015
rows, all `published`), `review_chain` (7,984 rows).
**Measured today:** `agent_knowledge` — 1,611 profession rows unvalidated, 287 author_verified, 381 experience
rows quarantined, 99 unsourced. `ops_knowledge` — **0 of 9,140 validated**. The KPI "Knowledge validated"
reads 31.57% against 80 because it counts anything not in (`unvalidated`,`unreviewed`), which includes
`quarantined` and `unsourced`. That is a denominator defect this seat owns.

**K3 — Freshness and decay.** `days_since = current_date − greatest(updated_at::date, effective_date)`;
`review_due = updated_at::date + interval_for(layer, record_type)` where the interval is a stored table:
regulation 90 d, pricing/policy 30 d, playbook 180 d, profession 365 d, experience 180 d, company fact 15 min
(rendered, not stored).
`confidence_now = confidence × exp(−λ × days_since / half_life)` — arithmetic, with `λ` and `half_life`
stored per record type.
**Measured today:** `fn_knowledge_review_days(agent_key, layer, topic)`, `fn_knowledge_decay()`,
`fn_knowledge_freshness_sweep()` and `fn_knowledge_staleness_tag(review_due, validation_status)` all exist.
**0 of 2,556 `agent_knowledge` rows have a `review_due` in the past** — so the decay loop can run forever
and change nothing. The intervals table does not exist; the dates were set once on 6 Sep.

**K4 — Retrieval quality (precision at k).** For a held-out set of (question, expected record) pairs:
`precision@k = |retrieved ∩ expected| / k`; `recall@k = |retrieved ∩ expected| / |expected|`;
`MRR = mean(1 / rank of first correct)`.
Inputs: `kb_operational_route_test` (344 rows), `kb_route_test_run(limit)`, `kb_usage_log` (1,488 rows),
`agent_context_retrieval` (848 rows).
**Unmeasured:** there is no labelled held-out set for the *employee* seats — `kb_operational_route_test`
covers category routing, not the seven functional seats' questions. Precision at k for this department's own
retrieval **does not exist**.

**K5 — Corpus reachability.** A record is reachable when
`(dept_key ∈ fn_dept_scope(holder_dept) ∨ role_key = holder) ∧ runtime_eligible ∧ (embedding_gte is not null
∨ tsv matches)`.
**Measured today:** `fn_dept_scope('data_intel')` = {analytics, data_intel, intelligence, knowledge_eng} →
671 `ops_knowledge` rows (110 + 136 + 147 + 278), all embedded, **none validated**. The `knowledge`
department's 413 rows are outside it. `dept_library` for data_intel is **0 rows**, so LAYER 2b is empty for
all seven seats.

**K6 — Coverage against a module standard.** `coverage = modules_present / modules_required` per
(category | role). Required set from `knowledge_module_standard` (14 rows) and
`employee_knowledge_standard` (12 rows).
**Measured today:** `v_category_coverage` — 84 of 86 categories at ≥ 8 standard modules.
`employee_knowledge` bindings: 15/15/15/15/13/11 for six seats and **0 for `bi_analyst`**.

**K7 — Ingest lawfulness gate.** A stored allow-list of source classes: standards bodies publishing openly,
regulators, government statistics portals, published open frameworks, public datasets, our own documents.
A stored deny-list: copyrighted study texts, paywalled standards, scraped third-party catalogues, anything
without a licence statement. Verdict is a lookup, not a judgement.
**Unmeasured:** no `source_licence` column exists on `kb_chunks` or `ops_knowledge`. `compliance_sources`
holds 17 rows; it is not that register.

### 3. Reasoning procedures

**Type 1 — "Does this record count as validated?"**
1. Read the record and its `source_ref` / `source_ids`.
2. If null → `unsourced`, stop.
3. Read the author. If the proposed validator is the author → refuse (`forbidden_decisions`: validating a
   lesson it proposed).
4. Embed the record's claim (free, in-region) and search for corroboration: `fn_ops_knowledge_match` /
   `kb_match` for records with a **different** `source_ref` at cosine ≥ 0.85 **and** ≥ 2 shared content
   lexemes. A nearest neighbour is always found, so the lexeme arm is mandatory.
5. Search for contradiction on the same key terms with an opposing numeric value (a stored regex set for
   AED figures, percentages, day counts).
6. Verdict: `validated` (≥ 1 corroboration, 0 contradictions) | `author_verified` | `conflicted` (escalate) |
   `unsourced`.
7. Write the decision with both row ids cited. **Stop:** any step 4 hit that is the record's own copy.

**Type 2 — "What gets embedded next?"**
1. Read `fn_kb_embed_backlog()` for the estimated remaining set and the frontier `created_at`.
2. Compute K1 over the **remaining** set only — index the un-embedded rows, never re-walk the embedded ones.
3. Claim a bounded batch via `fn_kb_embed_claim(limit, source_kinds, categories, newest)`, passing the top
   source kinds and categories from the score, never an unbounded `where embedding_gte is null` count.
4. After the batch, assert a **delta**: embedded count increased by the batch size. Never assert an absolute
   corpus total as a gate.
5. **Stop:** if the frontier `created_at` has not advanced in two consecutive ticks → open an incident; the
   picker is walking its own successes.

**Type 4 — "Should this be quarantined?"**
1. Check `source_ref is null` → quarantine.
2. Check provenance: was it written by `fn_knowledge_exam_sit`'s fill path from a `wrong` verdict?
   (`knowledge_exam_results.filled = true` joined to `knowledge_id`.) → quarantine.
3. Check scope: does the record's `dept_key` / `category` sit inside the holder's `fn_dept_scope`? → if not,
   quarantine as off-remit.
4. Check confidence against the stored floor.
5. Quarantine is reversible and never deletes: set `validation_status = 'quarantined'`, keep provenance.
   **Never delete without provenance** — that is a forbidden decision for this role.
   **Worked today:** this seat's own last exam filled **9 of 30** answers; the 6 Sep audit found 6 of those
   from wrong verdicts and category-pack items (`02_FIELD_AND_QUESTION_BANK_V2.yaml`, an MEP
   `qualification_playbook.md`, `specialist_manifest.yaml`) sitting in its experience layer. All are
   off-remit by step 3.

**Type 7 — "Is retrieval finding the right thing?"**
1. Take the seat's taxonomy rows as queries.
2. Run both arms: lexical `ts_rank_cd` and cosine `fn_ops_knowledge_match`.
3. Score against the labelled expected record (K4).
4. Report `precision@8`, `recall@8`, `MRR`, and the share of queries where the top hit was off-remit.
5. **Stop today:** there is no labelled set. The honest output is
   `cannot answer: no held-out retrieval set exists for functional seats; kb_operational_route_test (344 rows)
   covers category routing only. Opened task: build a 200-pair set from the seven taxonomies.`

**Type 11 — "Which category's knowledge hole blocks an RFQ?"**
1. Read `v_category_coverage` (86 rows) for module gaps.
2. Read `v_supply_gap` for approved suppliers per category.
3. Rank by `blocking = (modules_missing > 0) ∧ (approved ≥ 1)` — a hole only blocks where supply exists.
4. **Measured today:** 84 of 86 categories have ≥ 8 modules; 3 categories have any approved supplier; 0 have
   10. The blocking set is at most 3 categories and probably 0. The correct output is that **knowledge is not
   the binding constraint on RFQs today; supply is** — and to say so rather than manufacture work.

**Type 23 — "What goes into the empty `dept_library`?"**
1. Read the 671 in-scope `ops_knowledge` rows.
2. Select `record_type ∈ (reference, policy, decision_playbook, decision_rule, SOP, failure_mode)` and
   `runtime_eligible`.
3. Deduplicate by `checksum`.
4. Rank by K1's `decision_weight` and insert the top N as `dept_library` rows with `department = 'data_intel'`.
5. Verify by re-running the LAYER 2b path and asserting it no longer returns company FAQ rows.

### 4. Judgement rules

- **KJ-1.** A record with no source is never validated, whatever it says. → `unsourced`.
- **KJ-2.** The author never validates its own record. → refuse and route to a second seat.
- **KJ-3.** Corroboration requires a **different** `source_ref` and ≥ 2 shared lexemes. Cosine alone never
  corroborates — a nearest neighbour is always found.
- **KJ-4.** Never delete knowledge; quarantine it with its provenance intact. Deletion without provenance is a
  forbidden decision.
- **KJ-5.** An exam fill from a `wrong` verdict is quarantined on sight and never counts toward the "validated"
  KPI. *This is the "do not do this even though it scores well" rule for this seat: filling raises the
  coverage number and lowers the truth of the corpus.*
- **KJ-6.** Copyrighted study texts and paywalled standards are never ingested, however useful. Only the
  lawful classes in K7.
- **KJ-7.** Personal data does not enter a retrieval corpus without a PDPL basis recorded against the ingest
  run.
- **KJ-8.** A record whose category is outside every `fn_dept_scope` is not ingested — invisible knowledge is
  cost with no benefit.
- **KJ-9.** A backfill that does not advance its frontier in two ticks is an incident, not a slow job.
- **KJ-10.** Never assert an absolute corpus count as a gate; assert deltas. *A running company changes the
  denominator underneath any absolute check.*
- **KJ-11.** If a company fact can live in a table, it lives in a table and is rendered by
  `fn_company_self_knowledge_sync()` every 15 minutes — not written as a record that goes stale.
- **KJ-12.** Escalate to `intel_director` when the corpus contradicts itself on a **number** (a price, a day
  count, a percentage). Numeric contradictions are never resolved by this desk alone.
- **KJ-13.** `deterministic = true` is set only when the record states a rule with an explicit condition and
  arm and cites the `decision_policy` key it mirrors. A heuristic never enters LAYER 2f.
- **KJ-14.** A seat with 0 curriculum bindings may not be examined; fix the binding first. (`bi_analyst`
  today.)

### 5. Technical knowledge

- **The corpus tables:** `kb_chunks` (id, source_kind, source_id, category, title, content, citation,
  effective_date, fts, embedding_gte, category_norm, embed_claimed_at), `kb_category_stats`, `kb_revisions`,
  `kb_operational_alias` (4,255), `kb_operational_route` (86), `kb_operational_route_map` (426),
  `kb_operational_route_test` (344), `kb_usage_log`, `knowledge_ingestion_run`, `knowledge_ingestion_undo`
  (32,825), `ops_knowledge` (41 columns including `runtime_eligible`, `deterministic`, `supersedes_id`,
  `supersession_state`, `checksum`, `embedding_status`), `agent_knowledge`, `dept_library`,
  `employee_knowledge`, `employee_knowledge_standard` (12), `knowledge_module_standard` (14),
  `knowledge_domain` (107), `os_knowledge_domain` (445).
- **The routines:** `fn_kb_embed_claim`, `fn_kb_embed_backlog`, `fn_kb_corpus_integrity`,
  `fn_kb_category_stats_refresh`, `fn_kb_reconcile`, `fn_kb_retrieve`, `fn_kb_route`, `fn_kb_route_decide`,
  `fn_kb_route_test_run`, `fn_kb_validate`, `fn_kb_approve`, `fn_kb_gov_approve`, `kb_query`, `kb_match`,
  `kb_sync`, `kb_begin_run` / `kb_finish_run` / `kb_get_hashes` / `kb_stage_upsert`,
  `fn_ops_knowledge_match`, `fn_ops_knowledge_search`, `fn_ops_knowledge_embedding_status`,
  `fn_knowledge_decay`, `fn_knowledge_curator`, `fn_knowledge_freshness_sweep`, `fn_knowledge_gaps`,
  `fn_knowledge_provenance_stamp`, `fn_knowledge_rollback(run)`, `fn_knowledge_review_days`,
  `fn_knowledge_staleness_tag`, `fn_dispatch_agent_knowledge_gaps`, `fn_employee_knowledge_freshness`,
  `fn_company_knowledge_search`, `fn_company_knowledge_upsert`, `fn_company_self_knowledge_sync`.
- **The views:** `v_kb_coverage`, `v_kb_confidence`, `v_kb_risk`, `v_kb_review_due`, `v_kb_citation_check`,
  `v_kb_regulation_gaps`, `v_kb_operational_86_coverage`, `v_kb_route_crosswalk`,
  `v_knowledge_compliance`, `v_knowledge_matrix`, `v_knowledge_review_due`,
  `v_employee_knowledge_compliance`.
- **Embedding mechanics:** `gte-small`, 384 dimensions, in-region, free, run by the `kb_embed` edge function
  in small batches; `pgvector` with HNSW; cosine distance; `embed_claimed_at` is the claim lease that stops
  two workers embedding the same rows.
- **Retrieval mechanics:** hybrid lexical (`tsvector`, `ts_rank_cd`) plus vector, fused; `fn_agent_context`
  builds the prompt head in layers with a character budget; the run-time path keeps head[0:19,500] plus
  ≤ 4,500 retrieved. `fn_apply_playbook` binds at cosine ≥ 0.85 with ≥ 2 lexemes covering ≥ 30%.
- **Chunking:** the source kinds and what a good chunk looks like per kind; the 211-character click-step
  chunks in the `it` category are the counter-example.
- **Provenance and rollback:** every ingest runs inside `kb_begin_run` / `kb_finish_run` with a package id,
  version and sha; `knowledge_ingestion_undo` is how a bad run is reversed.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Knowledge management | KM lifecycle, communities of practice, codification vs personalisation, KM measurement | ISO 30401:2018 is a **paid** standard — ingest only a public overview or the ISO abstract page; never the standard text |
| Data management | DAMA-DMBOK knowledge areas — governance, quality, metadata, master data | Already in `kb_chunks` (1,371 chunks per the 6 Sep audit); the work is a **scope change**, not an ingest |
| Information retrieval | Precision/recall/MRR/nDCG, BM25, hybrid retrieval, reciprocal rank fusion | Open IR literature and the TREC evaluation methodology, published openly by NIST |
| Taxonomy and controlled vocabularies | Facet design, polyhierarchy, alias management, SKOS | W3C SKOS Reference (open W3C Recommendation) |
| Text processing | Tokenisation, stemming, stop words, tsvector semantics | PostgreSQL 16 official documentation, "Full Text Search" chapter (open licence) |
| Vector search | Embedding geometry, cosine vs dot, ANN recall/latency trade-offs, HNSW parameters | pgvector project documentation and the published HNSW paper (open access) |
| Measurement of knowledge work | Coverage, freshness, defect escape rate | NIST e-Handbook (process monitoring) |
| Data protection | Lawful basis for holding personal data in a corpus | UAE Federal Decree-Law 45/2021 (PDPL) and the UAE Data Office's published guidance — primary text, publicly available |

**Certifications this seat holds:**

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | CKM (Certified Knowledge Manager) | KM Institute | 70% | Knowledge Management Fundamentals · KM Strategy and Governance · Knowledge Capture and Codification · Communities of Practice · KM Technology and Taxonomy · Measuring KM Performance |
| 2 | CDMP (Certified Data Management Professional) | DAMA | 60% | Data Governance · Data Architecture · Data Modelling and Design · Data Quality · Metadata Management · Master and Reference Data Management · Data Warehousing and BI · Data Security |

**Syllabus areas it failed: does not exist** — no `certification_exam_result` row for this seat. The lexical
knowledge exam measured **11 correct of 30 (36.7%)**, 9 wrong, 4 partial, 6 not covered, confidence 0.46,
last sat 2026-09-07 03:23 UTC, with **9 answers filled back into `agent_knowledge`**. Note the irony this
seat must own: the highest score in the department belongs to the seat whose exam is polluting its own corpus.

### 7. Corporate knowledge

- **The corpus as it actually is, not as the plan describes it:** 2,686,026 chunks, 5.48% embedded, 356
  categories, 27 source kinds; 2.06M of those chunks are `standard` and 0.7% of them are embedded. The 6 Sep
  audit measured the UAE content share at 0.2–0.25% in the marketing and customer-success categories. This
  seat must know that **the corpus is large and mostly Western textbook material**, and must not describe
  size as coverage.
- **The 101 `ops-data_intel-deep-*` records (2 Sep 2026)** are this department's best asset — "Marketplace
  liquidity is the master metric, not GMV", "A 30-day total is not a run rate", "Statistical power and MDE for
  low-traffic decisions", "Network interference: why marketplace A/B tests violate no-spillover", "Building
  the AED 1M forecast bottom-up", "Do not fabricate data to turn a gate green". All embedded, **none
  validated**. Validating them is this seat's cheapest high-value act.
- **The knowledge plan of record:** `docs/KNOWLEDGE_PLAN_2026-09-06.md` (P1 234 · P2 281 · P3 148 across 54
  agents; data_intel P1 28 · P2 43 · P3 34) and `docs/knowledge_audit/data_intel.md`. Company-wide actions 6
  (a deterministic reasoning half for the exam) and **8 (populate the seven empty `dept_library`
  departments) are still open, and action 8 is owned by this seat.**
- **What the company knows about itself** is rendered from tables every 15 minutes by
  `fn_company_self_knowledge_sync()` as `qd-company:*` records — trade licence DET 1633275 expiring
  2027-06-24, no VAT registration until the AED 375,000 threshold, the pricing in `pricing_config`. Adding a
  permanent company fact means adding a table column and a renderer line, never a hand-written record.
- **Hard rules every agent head opens with** come from `fn_company_hard_rules()`; the head itself from
  `fn_agent_context(text,int)` with a 3-arg overload delegating. Both overloads live in
  `scripts/sql/every_head_carries_the_licence_and_tax_status.sql`.
- **Hand-offs:** all four of this role's hand-off targets (`knowledge_engineer`, `knowledge_validator`,
  `taxonomy_manager`, `category_curator`) are **inactive**. The seat cannot delegate; it must either do the
  work or ask `intel_director` to re-hire. Changing the taxonomy is forbidden to it and the taxonomy owner is
  parked — so a taxonomy change today has **no live owner**. That is a governance hole worth the founder's
  attention.
- **Does not exist:** a source-licence register; a labelled retrieval evaluation set for functional seats;
  a review-interval table; `dept_library` rows for this department; any validated `ops_knowledge` row.

### 8. One-year plan

**Objective.** Every seat answers from current, cited, in-scope knowledge, and the corpus stops growing in
directions nobody can reach.

**Slice of the AED 1,000,000: AED 0 directly.** This seat's contribution is the removal of a blocker, and
today **knowledge is not the blocker** — 84 of 86 categories already carry ≥ 8 modules while 0 of 86 have the
10 approved suppliers a category needs to open. Claiming a revenue slice here would be inventing a causal
chain the estate does not show.

**Metrics it owns (measured baselines):**
1. **Knowledge validated** — 31.57% vs target 80. *Fix the denominator first (K2): the current SQL counts
   `quarantined` and `unsourced` as validated.*
2. **Knowledge quarantined** — 15.53% vs a 5% ceiling. Note this is a *good* number rising for a *good*
   reason if the exam fills are being cleaned; the KPI cannot currently tell those apart.
3. **Retrieval corpus freshness** — 99.89% vs 60 (met, and close to meaningless: it measures
   `created_at > now() − 30 days` over a corpus that was bulk-loaded).
4. **New: decision-reachable embedded share** — embedded chunks in categories inside at least one
   `fn_dept_scope`, ÷ all chunks in such categories. Baseline: does not exist.

**Quarterly milestones.**
- **Q1.** Fix the "Knowledge validated" denominator. Validate the 101 deep records. Populate `dept_library`
  for data_intel (company-wide action 8). Build the review-interval table so decay has something to act on.
  Quarantine every exam fill from a wrong verdict across the seven seats. Give `bi_analyst` its 12 curriculum
  bindings.
- **Q2.** Stand up K1 as the embedding picker's ranking and measure the delta weekly. Build the 200-pair
  held-out retrieval set from the seven taxonomies and publish `precision@8`.
- **Q3.** Source-licence register on every ingest path; UAE-source ingest for `market_analyst` (see that seat).
- **Q4.** Corpus reachability audit: every category mapped to at least one scope or explicitly retired.

**Capacity check.** Embedding is free and in-region; at the observed rate in the 6 Sep restart (703 chunks in
30 minutes ≈ 33,700/day) the remaining 2,538,888 chunks would take **≈ 75 days of continuous running** — so
full coverage is reachable inside the year *if the job stays alive*, which is exactly what K1 step 5 watches.
Validation is the real constraint: 9,140 `ops_knowledge` rows at 0 validated, and validation needs a second
seat because self-validation is forbidden — with all four hand-off targets inactive, this seat can validate
only what `intel_director` or `analytics` reviews.

**Dependencies.** `intel_director` for numeric contradictions and for the second pair of eyes on validation.
`people_ops` owns the exam that is currently polluting the corpus (company-wide actions 5 and 6).
`product_eng` owns `fn_agent_context` and the scope predicates.

**Plainly: achievable, and it is not on the revenue path this year.** The founder should read this seat's
year-one value as *making the other six seats' answers trustworthy*, not as revenue.

### 9. What this seat cannot do without a model

- Judging whether two records that use different vocabulary make the *same* claim, when the lexeme overlap is
  below threshold and the cosine is ambiguous. The deterministic path marks it `conflicted` and escalates —
  correct, but it will escalate more than a human would.
- Writing a summary of a 300-page source into a chunkable record. Chunking is mechanical; *summarising* is not.
  The lawful deterministic substitute is to ingest the source's own executive summary and cite it.
- Deciding that a source is authoritative when it is not on the stored allow-list. The seat can only apply the
  list; extending it is a human act.

---

## analytics — Data Engineer

`org_role.role_id = data_engineer` · authority `advisory`, budget 0 · manager `intel_director` ·
owns *measurement SQL and data pipeline design, data quality rules* · forbidden *changing a metric definition,
reporting a number it also defined, writing to production business tables* · outputs `measurement_path`,
`data_quality_report` · required input `employee_task` · escalates to `data_intelligence_director`,
`chief_of_staff`.

Authority rows: `recommend`, `health_report`, `uptime_verify`, `security_review` autonomous;
`incident_fix` and `code_selfheal` advisory only.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | What SQL measures this KPI, exactly? | craft | per KPI, 127 live | intel_director, any head | the KPI reads NULL or reads the wrong thing for a quarter |
| 2 | Is this `measure_sql` fixture-safe? | gate | per SQL | own seat | a `ZZ DEMO` row is counted as a real registration |
| 3 | Will this query finish inside the 8-second statement timeout? | gate | per SQL | own seat | the snapshot cron fails silently and the metric goes stale |
| 4 | Is this a count, a rate, or a mean — and does the unit match? | craft | per SQL | own seat | the `categories with eight modules` defect, repeated |
| 5 | Does this join fan out and double-count? | diagnosis | per multi-table SQL | own seat | revenue is reported at 3× because a quote joined three matches |
| 6 | Is `null` here "zero" or "unknown"? | gate | per column | own seat | `supplier_score.reliability` is null for 20,463 of 20,465 rows precisely because unmeasured ≠ unreliable |
| 7 | Which table is the source of truth for this quantity? | gate | per metric | intel_director | two tables disagree and both get quoted |
| 8 | Is this pipeline job alive? | diagnosis | daily | own seat, it | a stalled job reads identically to an idle system |
| 9 | Is a schema change about to break a metric? | gate | per migration | product_eng | a column rename silently zeroes a KPI |
| 10 | Should this be a view, a materialised view, or a snapshot table? | craft | per new metric | own seat | a hot view scans 2.68M rows on every dashboard load |
| 11 | Does this metric need an index, and which kind? | craft | per slow query | own seat | the snapshot cron times out at scale |
| 12 | Is this data-quality rule worth enforcing? | allocation | per rule | own seat | 22,265 leads with 0 valid emails; enforcing the wrong rule blocks the funnel |
| 13 | What is the completeness of this column? | diagnosis | per audit | any seat | a report is built on a column populated for 3% of rows |
| 14 | Is this timestamp UTC or local? | gate | per column | own seat | month-end is wrong by four hours |
| 15 | Is this deduplication key correct? | craft | per ingest | own seat | 20,464 rows in `zz_lead_hay` shadow 22,265 leads; a wrong key merges two companies |
| 16 | Is a referential orphan present? | diagnosis | weekly | own seat | quotes point at deleted inquiries and counts disagree |
| 17 | Is this column's cardinality what the model assumes? | diagnosis | per model input | supplier_analyst | a "category" that is 356 distinct values is not a 86-category taxonomy |
| 18 | Should this metric be snapshotted or computed live? | craft | per metric | intel_director | history is lost the moment the underlying row changes |
| 19 | Is the snapshot cadence right? | craft | per metric | own seat | 87 snapshots per metric and no one knows the intended interval |
| 20 | Which `no_measure_reason` is honest here — no instrument, or a business decision? | gate | per unmeasured goal | intel_director | 20 goals say "no instrument"; misclassifying one hides buildable work |
| 21 | Is this an aggregation over a moving denominator? | diagnosis | per rate | own seat | a rate over a growing base looks like decay |
| 22 | Does this query read a view that reads it back? | gate | per SQL | own seat | infinite recursion, or a silently stale layer |
| 23 | Is a partial index safe here? | craft | per index | own seat | the index stops matching after a status value changes |
| 24 | Is this backfill idempotent? | gate | per backfill | own seat | a re-run doubles the rows |
| 25 | Does this pipeline emit a heartbeat? | gate | per job | own seat | liveness cannot be distinguished from emptiness |
| 26 | Is the row count change plausible? | diagnosis | per load | own seat | an ingest that loads 0 rows completes "successfully" |
| 27 | Should this be an event or a status column? | craft | per new instrument | product_eng | a status column overwrites history and the funnel cannot be reconstructed |
| 28 | Is this PII, and may it be in this table? | gate | per column | legal, own seat | PDPL exposure |
| 29 | Is this query's plan a sequential scan it should not be? | diagnosis | per slow query | own seat | cost and timeout |
| 30 | Can this metric be reconstructed if the table is rewritten? | gate | per snapshot design | own seat | a rewrite erases the only record of a period |
| 31 | Is the vector index's recall acceptable at this `ef_search`? | craft | per retrieval change | knowledge_director | retrieval quietly degrades |
| 32 | Is this a genuine data-quality defect or a business reality? | diagnosis | continuously | own seat | "0 valid emails" is a defect; "0 transactions" is a business reality; treating either as the other wastes a quarter |

### 2. Domain logic

**A1 — `measure_sql` contract check.** A parse-and-assert routine over the stored SQL text:
returns exactly one numeric scalar; contains a period bound (`interval` or `date_trunc`); wraps every division
in `nullif`; contains both fixture predicates when it touches `leads`, `inquiries`, `quotes` or `transactions`;
does not reference the view it is defined on; `EXPLAIN` cost below a stored ceiling.
Inputs: `employee_kpi.measure_sql` (127 rows), `company_goals.measure_sql`, `metric_definition.measure_sql`.
Output: pass / a list of failed clauses.
**Measured today:** 88.33% of active `employee_kpi` rows have any `measure_sql` at all (the KPI
"KPI instrumentation"). The contract check itself **does not exist**.

**A2 — Column completeness and null semantics.**
`completeness = count(col) / count(*)`; `distinctness = count(distinct col) / count(col)`;
`null_meaning ∈ {absent, unknown, not_applicable}` — a stored per-column declaration, not inferred.
**Measured today on `leads` (22,265 rows):** email 89.4%, phone_e164 31.2%, website 52.0%, embedding_gte 3.1%,
trade_license_no 0.004%, `email_verified = 'valid'` **0.0%**. On `supplier_score` (20,465 rows):
reliability 0.01%, price_index 0%, quality_rating 0%.
**Unmeasured:** the `null_meaning` declaration does not exist as a table. It matters: `fn_supplier_score_refresh`
deliberately writes NULL rather than 0 for an unmeasured supplier, and any downstream `coalesce(x,0)` silently
converts "unknown" into "worst".

**A3 — Fan-out detection.** For a join `A ⋈ B`, `fanout = count(*) after / count(*) before`. A metric whose
`measure_sql` produces `fanout > 1` on any join and then aggregates without `distinct` is defective.
Inputs: the SQL text plus a dry-run row count at each join.
**Unmeasured:** no such check runs. With `quotes`, `inquiries`, `transactions` and `inquiry_matches` all at 0
rows, fan-out defects cannot show themselves today and will appear the moment demand starts.

**A4 — Job liveness.** `alive = (last_success_at > now() − 2 × interval) ∧ (rows_affected_last > 0 ∨
work_remaining = 0)`.
Inputs: `cron_registry` (213), `cron_job_seen` (234), `health_checks` (5,790), `agent_runs` (40,373),
`dead_letter` (141), `error_events` (937), `edge_health_probe` (60,331).
Output: `alive | stalled | idle_correctly`.
**This is the single most valuable model this seat owns**, because zero cannot tell a dead guard from an idle
system, and the estate currently has many honest zeros next to at least one dead writer (`market_intel`).

**A5 — Plausibility band on a load.** For an ingest with history, `expected_rows = median(last 8 runs)`;
flag when outside `[0.5 ×, 2 ×]` or exactly 0.
Inputs: `knowledge_ingestion_run`, `scrape_runs` (28), `screening_run`, `agent_runs`.

**A6 — Referential integrity sweep.** For each declared parent/child pair, count orphans.
Inputs: the FK catalogue in `information_schema`; plus the *undeclared* pairs (e.g. `quotes.supplier_id` →
`leads.id`) which need a stored list.
**Unmeasured:** the undeclared-pair list does not exist.

**A7 — Query cost gate.** `EXPLAIN (format json)` total cost against a stored ceiling per metric class; plus
an assertion that no metric's plan contains a sequential scan over `kb_chunks`, `leads`, `supplier_score`,
`phase_c_trace` or `phase_c_system_execution` (the five tables above 20,000 rows that a metric might touch).

### 3. Reasoning procedures

**Type 1 — "What SQL measures this KPI?"**
1. Read the KPI's `metric` text and `unit` from `employee_kpi`.
2. Resolve the quantity to a source table by a stored quantity→table map (does not exist yet; build it from
   the 14 `metric_definition` rows and the 112 `employee_kpi` rows that already have SQL).
3. Draft the SQL from a template per unit: percent → `round(100.0 * count(*) filter (where …) /
   nullif(count(*),0), 2)`; count → `count(*)::numeric`; AED → `coalesce(sum(...),0)::numeric`;
   days → `round(avg(extract(epoch from (b − a))/86400.0)::numeric, 2)`.
4. Add the period bound from `cadence`.
5. Add the fixture predicates if the table is a business table.
6. Run A1, A3, A7.
7. Emit as a `measurement_path` artefact — **never register it**, because changing a metric definition is a
   forbidden decision for this seat. It proposes; `intel_director` registers.

**Type 6 — "Is this null zero or unknown?"**
1. Read the column's declared `null_meaning` (build the table first).
2. If absent, refuse and open a task — do not guess.
3. If `unknown`, forbid `coalesce(col, 0)` in any downstream metric and say so in the memo.
   **Worked today:** `supplier_score.reliability` is null on 20,463 of 20,465 rows by deliberate design —
   `fn_supplier_score_refresh` writes NULL when there is no response history *and* no quotes, with the comment
   "UNMEASURED IS NOT UNRELIABLE". Any KPI that coalesces it to 0 would report the entire supplier base as
   maximally unreliable. The seat's job is to make that impossible, not to notice it afterwards.

**Type 8 — "Is this pipeline job alive?"**
1. For each job in `cron_registry`, read the last seen row in `cron_job_seen` and the last matching run in
   `agent_runs` / `health_checks`.
2. Apply A4.
3. For a `stalled` verdict, check `dead_letter` and `error_events` for a cause in the same window.
4. Emit a `data_quality_report` row per job with `alive | stalled | idle_correctly` and the evidence
   timestamps. Escalate `stalled` to `intel_director` and `it`.
5. **Never** report "0 rows processed" as success.

**Type 32 — "Defect or reality?"**
1. Count the table.
2. If the table is empty, ask whether any writer exists (`cron_registry`, an edge function in
   `phase_c_component`, a workflow step). No writer → **reality, awaiting a feature**; a writer that ran and
   wrote nothing → **defect**.
3. If the table has rows but the column is empty, find the writer of that column specifically.
   **Worked today:** `leads.email_verified = 'valid'` on **0 of 19,896 emails** while `email_verifications`
   holds 125 rows and `email_domain_mx` holds 8,764 — a writer exists and the column is not being set. That is
   a defect. `transactions = 0` with no reveal ever paid is a reality. Both are zeros; only one is work.

**Type 3 — "Will it finish in 8 seconds?"**
1. `EXPLAIN (analyze false, format json)`.
2. Compare total cost to the stored ceiling; reject a sequential scan over any of the five large tables.
3. If rejected, propose the fix in order: add a period bound → add a partial index → precompute into a
   snapshot table → materialise. Never propose raising the timeout.
   **Known case:** `count(*) where embedding_gte is null` over `kb_chunks` (2.68M rows) is exactly the query
   that stalled the embedding backfill; `fn_kb_embed_backlog()` now estimates from `pg_stats.null_frac`
   instead. That routine is the worked exemplar this seat must carry.

### 4. Judgement rules

- **AJ-1.** Never `coalesce` an unknown to a value. An unmeasured supplier is not a zero-reliability supplier.
- **AJ-2.** A business-table metric without both fixture predicates is rejected, no exceptions.
- **AJ-3.** Any metric whose plan sequentially scans a table above 20,000 rows is rejected before it is
  registered.
- **AJ-4.** Never raise the statement timeout to make a query pass. Fix the query or precompute it.
- **AJ-5.** This seat proposes SQL and never registers it; it never reports a number from a definition it
  wrote. *Both are in its `forbidden_decisions` and both are the classic self-marking failure.*
- **AJ-6.** Every job emits a heartbeat and a rows-affected count. A job that cannot say how much work it did
  is not deployed.
- **AJ-7.** An ingest that loads 0 rows fails loudly. *"Completed successfully, 0 rows" is the most expensive
  line in any pipeline.*
- **AJ-8.** A status column is never the instrument for a funnel; the funnel is instrumented on events.
  *Status columns overwrite history.*
- **AJ-9.** Never assert an absolute business count in a check. Assert a delta, or assert against a snapshot
  taken in the same transaction. *A running company moves the number under the assertion.*
- **AJ-10.** Do not "fix" a null by writing a default. Escalate the missing writer.
- **AJ-11.** Escalate to `intel_director` when a proposed metric's source table has no writer, and to `it` /
  `product_eng` when a schema change would change a live metric's value.
- **AJ-12.** PII does not enter an analytics table. Masked columns exist on `inquiries`
  (`summary_masked`, `raw_input_masked`, `budget_masked`, `spec_masked`, `boq_masked`,
  `completeness_masked`) and are the only versions an analytics path may read.

### 5. Technical knowledge

- **PostgreSQL 16 as deployed:** window functions, `filter (where …)`, CTEs and their materialisation,
  `generate_series` for dense periods, `date_trunc` and `make_interval`, `nullif`/`coalesce` semantics,
  partial and expression indexes, GIN over `tsvector`, `pgvector` HNSW and `ef_search`, `EXPLAIN` reading,
  autovacuum and `reltuples` staleness (the census in this document used `reltuples` and had to re-count
  every table that mattered), `pg_stats.null_frac` as a cheap cardinality estimate.
- **The estate's constraints:** an 8-second statement timeout; the management API runs each call as its own
  transaction; `SECURITY DEFINER` functions are granted to PUBLIC on creation and must be revoked in the same
  file; `CREATE OR REPLACE` keeps the ACL.
- **The measurement plumbing:** `employee_kpi.measure_sql` and `fn_employee_kpi_measure()`;
  `metric_definition.measure_sql` and the snapshot cron writing `metric_snapshot`;
  `company_goals.measure_sql`, `goal_period` and `fn_goal_period_refresh()`; the ten `*_kpi_snapshots` tables
  (`customer_kpi_snapshots`, `document_kpi_snapshots`, `finance_kpi_snapshots`, `knowledge_kpi_snapshots`,
  `legal_kpi_snapshots`, `ops_kpi_snapshots`, `report_kpi_snapshots`, `security_kpi_snapshots`,
  `strategy_kpi_snapshots`, `supplier_kpi_snapshots`) — which exist and are documented nowhere.
- **The data-quality surface:** `health_checks`, `edge_health_probe`, `error_events`, `dead_letter`,
  `cron_registry`, `cron_job_seen`, `agent_runs`, `undo_log` (27,050), `knowledge_ingestion_undo` (32,825).
- **The business tables and their real shapes:** `leads` (about 150 columns — the widest table in the estate,
  and the reason a `select *` on it is never the answer), `inquiries` (with the six `_masked` columns),
  `quotes`, `transactions`, `supplier_score`, `supplier_capabilities`, `lead_category` / `lead_subcategory`,
  `catalog_supplier_categories` (86), `catalog_subcategories` (468).
- **Fixture convention:** `ZZ DEMO — ` names and `@example.invalid` emails, only inside a `rehearsal_window`,
  and the aborted-transaction probe pattern (write, count, `raise exception` with the counts so it rolls back)
  as the safe way to measure a write path.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Relational theory and query optimisation | Normal forms, join algorithms, cost-based optimisation, index selection | PostgreSQL 16 official documentation (open licence) — chapters "Queries", "Performance Tips", "Indexes", "Full Text Search", "Date/Time" |
| Data quality | The DAMA dimensions: completeness, uniqueness, timeliness, validity, accuracy, consistency | DAMA-DMBOK (present in `kb_chunks`, out of scope — a scope change) |
| Statistical process control | Control charts for run-rate monitoring, common vs special cause | NIST/SEMATECH e-Handbook chapter 6 (public domain) |
| Sampling | Finite-population sampling for audit of a 22,265-row table | NIST e-Handbook; official-statistics methodology notes |
| Data protection | PDPL obligations on storage, minimisation and masking | UAE Federal Decree-Law 45/2021 and UAE Data Office guidance (primary, public) |
| Time and calendars | UTC, offsets, the UAE Mon–Fri working week | IANA tz database documentation (public domain) |
| Vector search | Recall/latency trade-off, HNSW parameters | pgvector documentation; the HNSW paper (open access) |

**Certifications this seat holds:**

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | Google Professional Data Engineer | Google | 70% | Designing Data Processing Systems · Ingesting and Processing Data · Storing the Data · Preparing and Using Data for Analysis · Maintaining and Automating Data Workloads |
| 2 | EDB PostgreSQL 12+ Professional | EnterpriseDB | 70% | Architecture and Configuration · SQL and Query Tuning · Backup and Recovery · Replication and High Availability · Security and Roles · Monitoring and Maintenance · Vacuum and Bloat Management |

**Syllabus areas it failed: does not exist** — no `certification_exam_result` row. The lexical exam measured
**11 correct of 39 (28.2%)**, 10 wrong, 7 partial, 11 not covered, confidence 0.59 (the highest in the
department), 6 answers filled, last sat 2026-09-07 03:23 UTC. Note that the two certifications above are the
only two in this department that map cleanly onto work the estate actually does — "SQL and Query Tuning",
"Monitoring and Automating Data Workloads" and "Vacuum and Bloat Management" are literally A1, A4 and A7.

### 7. Corporate knowledge

- **Its own KPI:** *"Data & Analytics Engineer — primary objective"*, metric *Platform availability*, target
  99.5%, weekly, measured **100.00%** on 2026-09-07 03:30 UTC from
  `health_checks where check_kind='http' and created_at > now()-interval '7 days'`. This is met — and it is
  worth the founder knowing that **the data engineer's only KPI measures HTTP uptime, not data quality**.
  Nothing this seat is actually accountable for is currently instrumented.
- **What it may and may not do:** advisory authority, budget 0; `recommend`, `health_report`, `uptime_verify`
  and `security_review` run autonomously; `incident_fix` and `code_selfheal` are advisory — it may prepare a
  fix and the department head executes it.
- **The SQL change discipline on this estate:** a new file in `scripts/sql/` with a header saying why; dry run
  then `--apply --ddl`; a MANIFEST line or the `canonical_routines` gate fails; a
  `kernel_routine_ownership` row following the manifest; `fn_kernel_wrap_and_enable_cron` for any new cron
  plus `cron_registry` and `phase_d_committed_scenario_cron` rows.
- **Standing rules that bind this seat hardest:** never fabricate or back-date data to turn a gate green;
  never weaken a check; if a real fix makes a headline number fall, say so. Mirror gates are retired —
  production proves properties, and a CSV never greens a check.
- **Does not exist:** a quantity→table map; a `null_meaning` declaration; an undeclared-FK list; a
  documented purpose for the ten `*_kpi_snapshots` tables; any data-quality KPI on this seat.

### 8. One-year plan

**Objective.** Every number the company reports comes from SQL that has passed a contract check, and every
pipeline can prove it is alive.

**Slice of the AED 1,000,000: AED 0 directly.** This seat writes no revenue and its output contract is
`measurement_path`. Its year-one value is that the revenue number, when it exists, is correct on the first
day it exists rather than after a quarter of reconciliation.

**Metrics it owns (all new; none exists today):**
1. `measure_sql_contract_pass_pct` — stored SQL passing A1. Baseline: unmeasured; 88.33% of active KPIs have
   any SQL at all.
2. `pipeline_liveness_pct` — jobs in `cron_registry` verifiably alive by A4. Baseline: unmeasured across 213
   registered jobs.
3. `column_completeness_defects_open` — declared-critical columns below their completeness floor. Baseline
   measured: `leads.email_verified` 0.0% of 19,896 emails is defect #1.

**Quarterly milestones.**
- **Q1.** Build A1 and run it over all 127 `employee_kpi` and 14 `metric_definition` rows; publish the failing
  list to `intel_director` (who registers the fixes — this seat may not). Build A4 and publish the first
  liveness report across the 213 cron jobs. Declare `null_meaning` for the 30 columns any live metric reads.
- **Q2.** A3 fan-out check wired into the metric registration path before demand arrives, so the first real
  revenue join is checked before it is trusted. Fix the `email_verified` writer or prove it is intentional.
- **Q3.** A5 plausibility bands on every ingest; A6 orphan sweep with the undeclared-FK list.
- **Q4.** A7 cost gate on every registered metric; document the ten `*_kpi_snapshots` tables or retire them.

**Capacity check.** All four models are SQL and plpgsql inside routines that already exist in shape. The seat
ran 10 deterministic tasks in the last 7 days (6 Sep audit) against `max_open_tasks` 50. This is achievable.
The one thing it **cannot** do is make its own checks meaningful on empty tables — A3 and A6 have nothing to
find while `quotes`, `transactions` and `inquiry_matches` are all 0.

**Dependencies.** `intel_director` registers everything this seat proposes. `product_eng` owns the migrations
that would break metrics and the writers this seat will name as missing. `it` owns the cron fabric A4 reads.

**Plainly: achievable, and it is the highest-leverage non-revenue work in the department**, because it is what
stops the first real revenue number from being wrong.

### 9. What this seat cannot do without a model

- Reading a KPI stated in free text ("how fast do suppliers actually answer us?") and resolving it to a
  quantity when the quantity→table map has no entry. The deterministic path refuses and names the closest
  three mapped quantities.
- Explaining *why* a query plan changed between two runs, beyond reporting that it did and which node
  differs.
- Naming a data-quality rule nobody has thought of yet. It can enforce the declared rules and detect the
  declared defects; discovering a new class of defect is a human act.

---

## bi_analyst — Business Intelligence Analyst

`org_role.role_id = business_intelligence_analyst` · authority `advisory`, budget null · manager
`intel_director` · owns *report construction and its citations, interpretation of a measured trend* ·
forbidden *changing the underlying measurement, stating a number it has not measured* · outputs `bi_report` ·
required inputs: **none declared** · escalates to `data_intelligence_director`, `chief_of_staff`.

The seat's single `employee_authority` row is a placeholder seeded 14 Aug 2026 ("an active role with no
authority record is undefined, not restricted"). It holds **0 `employee_knowledge` rows** and **0
`employee_workflow` rows** — the only seat in the department with neither. Its knowledge scopes are the four
`fn_dept_scope('data_intel')` names and nothing else.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Why did this KPI miss its target? | diagnosis | per miss, weekly | ceo, department heads | its own KPI: root cause named on 78.35% of misses vs a 90% target |
| 2 | Is the variance volume, mix or rate? | diagnosis | per material variance | cfo, intel_director | the remedy is aimed at the wrong lever for a quarter |
| 3 | Is this trend real or an artefact of a changing denominator? | diagnosis | weekly | ceo | growth is declared because the base shrank |
| 4 | What goes in the weekly founder brief? | sequencing | weekly | ceo, brief | the founder reads six numbers and misses the binding one |
| 5 | Which number leads this report? | craft | per report | own seat | the report is read and the decision is not made |
| 6 | Is a number in this draft one I measured myself? | gate | per line of every report | own seat | its explicit forbidden decision — stating a number it has not measured |
| 7 | What is the citation for this figure? | craft | per figure | own seat | an unsourced number in a founder brief |
| 8 | Should this report be produced at all this period? | allocation | per cadence | own seat | a report is produced from an unchanged, zero-denominator base |
| 9 | Which comparison is fair — period over period, or against plan? | craft | per report | cfo, ceo | a seasonal artefact is read as performance |
| 10 | Is this chart's axis honest? | craft | per chart | own seat | a truncated axis makes a 2-row move look like a trend |
| 11 | Is this an average that hides a bimodal distribution? | diagnosis | per mean reported | own seat | "average supplier response 24h" over 2 suppliers |
| 12 | Does this segment have enough rows to be shown separately? | gate | per segment | own seat | a category with 1 lead gets its own line and its own conclusion |
| 13 | Is this correlation being read as causation in the draft? | gate | per claim | own seat | a spend increase is credited with a revenue rise that predates it |
| 14 | Has this metric's definition changed inside the compared periods? | gate | per comparison | intel_director | the trend measures the definition change |
| 15 | Which of the 32 unmeasured goals should the report say nothing about? | gate | per report | own seat | silence is honest; a proxy quietly substituted is not |
| 16 | What does "on track" mean for this goal, numerically? | craft | per goal | ceo | "on track" with no pace arithmetic behind it |
| 17 | Is a target still the right one given measured capacity? | escalation | quarterly | intel_director | seats are marked failing against arithmetic that was never possible |
| 18 | Which department owns the explanation for this miss? | allocation | per miss | own seat | the miss is explained by the wrong desk and the real cause survives |
| 19 | Is the root cause recorded actually a cause, or a restatement? | gate | per recorded cause | own seat | "attainment 0% because throughput is 0" is a restatement, and it is what is recorded today |
| 20 | Is this a leading or a lagging indicator? | craft | per metric in a report | ceo | the company steers by a number that only confirms the past |
| 21 | Should this be reported weekly or monthly? | craft | per metric | own seat | weekly reporting of a monthly-moving number generates noise |
| 22 | Is a zero in this report a business fact or a missing instrument? | gate | per zero | own seat | the founder reads "0 market signals" as a quiet market |
| 23 | Does this report reconcile with finance's own numbers? | gate | monthly | cfo | two versions of revenue reach the founder |
| 24 | Which cohort does this retention figure describe? | craft | per cohort chart | growth, supply | invite cohorts and claim cohorts mixed |
| 25 | Is this outlier a data defect or a real event? | diagnosis | per outlier | analytics | a defect is explained as a business story |
| 26 | What is the confidence interval on this rate? | craft | per rate reported | own seat | a rate from 2 observations is reported bare |
| 27 | Is this forecast a forecast or a scenario? | gate | per forward number | intel_director | a labelled scenario becomes a commitment in the retelling |
| 28 | Should this report escalate rather than inform? | escalation | per report | own seat | a material breach is buried on page three |
| 29 | Is a metric being reported that nobody owns? | gate | per report | intel_director | nobody acts and nobody is accountable |
| 30 | Does this report state what would falsify it? | craft | per report | own seat | the report cannot be checked and so is never corrected |
| 31 | Which categories and emirates are worth a breakdown? | allocation | monthly | marketplace, supply | 86 categories × 7 emirates of noise |
| 32 | Is the comparison period contaminated by a rehearsal window? | gate | per comparison | own seat | a ZZ DEMO rehearsal shows up as a demand spike |

### 2. Domain logic

**B1 — Variance decomposition.** As M9 above: volume, mix, rate and residual, computed for any metric stored
with a dimension.
Inputs: two periods from `goal_period` / `metric_snapshot` / `employee_kpi_history` (1,332 rows) plus a
dimension column.
**Unmeasured:** **no metric in the estate is stored with a dimension.** All 14 `metric_definition` rows and
all 127 `employee_kpi` rows return a scalar. Until at least one metric carries category or emirate, this
model has nothing to run on — and that is the mechanical reason this seat's own KPI sits at 78.35% instead of
90%.

**B2 — Root-cause classification (deterministic).** A decision tree over the miss, not a narrative:
1. `actual is null` → **NOT MEASURED** (instrument).
2. `denominator = 0` → **NO THROUGHPUT** (the input has not started; this is not under-performance).
3. `denominator > 0 ∧ numerator = 0` → **TOTAL CONVERSION FAILURE**.
4. `attainment < 100 ∧ volume effect dominates` → **DEMAND**.
5. `… ∧ mix effect dominates` → **MIX**.
6. `… ∧ rate effect dominates` → **EXECUTION**.
7. `target > best observed × 3` → **TARGET UNREACHABLE** (escalate; do not record as a miss).
Inputs: `employee_kpi` + `employee_kpi_history`; `goal_period`; B1.
**Measured today:** the `improvement_plan` text on every seat in this department already carries the class-2
verdict — *"EXECUTION — no throughput: attainment 0.0% means the input that feeds this metric has not started,
not that it under-performed."* That verdict is **mislabelled**: by this tree it is class 2 (NO THROUGHPUT),
not class 6 (EXECUTION). The label is doing real damage because it reads as a performance failure of the seat.
Fixing the label is this seat's first act.

**B3 — Reportability gate.** A figure may appear in a `bi_report` only if:
measured (not null) ∧ fresh within cadence ∧ denominator ≥ `n_min` ∧ owned (`owner_dept` set) ∧ the definition
did not change inside the compared window ∧ the window contains no `rehearsal_window` row.
Inputs: `metric_definition`, `employee_kpi`, `goal_period`, `rehearsal_window` (30 rows).
Output: include | include with caveat | exclude with a named reason.

**B4 — Confidence interval on a proportion (Wilson).**
`(p̂ + z²/2n ± z·sqrt( p̂(1−p̂)/n + z²/4n² )) / (1 + z²/n)`, `z = 1.96`. Wilson rather than normal because the
estate's n values are tiny and near the boundary — a normal interval on 2 of 2 gives [1,1], which is a lie.
**Worked today:** `supplier_response_rate` computed over `leads where rv_reveals > 0` — n = 2. Wilson 95% CI
on 2/2 is approximately [0.34, 1.00]. The correct report line is *"2 of 2 suppliers responded; 95% CI
[34%, 100%]; not reportable as a rate"*, not "100%".

**B5 — Leading/lagging classification.** A stored attribute per metric plus a measured lag: cross-correlate
each candidate leading metric against the revenue metric at lags 0…8 periods and store the lag with the
highest coefficient.
**Unmeasured:** requires a revenue series. `transactions` is empty, so no lag can be estimated for any metric.
The classification must be declared by hand for now and marked *declared, not measured*.

**B6 — Report composition template.** The `bi_report` artefact is a fixed structure whose slots are computed:
`headline` (the single metric with the largest |attainment − 100| that passed B3) ·
`pace` (from `fn_goal_pace()`) · `variance` (B1 + B2) · `what changed` (a diff of `goal_period.actual_value`
between periods) · `what is not measured` (the count and list of `no_measure_reason` goals in scope) ·
`falsification` (the condition under which the headline would be wrong) · `citations` (every row id read).
**Unmeasured:** no `bi_report` template exists in the estate today. `exec_reports` holds 324 rows and
`board_reports` 172; neither is this contract.

### 3. Reasoning procedures

**Type 1 — "Why did this KPI miss?"**
1. Read the KPI row: `target_value`, `actual_value`, `measured_at`, `cadence`, `measure_sql`, `serves_goal`.
2. Run B3. An excluded figure stops here with the named reason.
3. Compute the denominator by counting the `measure_sql`'s source with the same predicates.
4. Run B2 top to bottom and take the **first** matching class. Do not narrate past the first match.
5. If the class is DEMAND / MIX / EXECUTION, run B1 for the dominant effect — and if the metric has no
   dimension, say **"cannot decompose: metric is stored without a dimension"** rather than guessing.
6. Attribute the cause to the department that owns the failing input, from `company_goals.owner_dept` or the
   input table's writer.
7. Compose. Cite the KPI row id, both period rows, and the denominator query.
   **Worked today across this department's own 14 KPIs:** market_analyst's *Market signals captured* 0 vs 20 →
   denominator is `market_intel` with 0 rows and no writer → class 2 NO THROUGHPUT, cause **instrument**, not
   performance. supplier_analyst's *Supplier scoring coverage* 0.01% vs 95 → denominator 22,265 leads,
   numerator 2 → class 3 TOTAL CONVERSION FAILURE, cause **`fn_supplier_score_refresh` correctly writes NULL
   because there is no response history**, so the KPI is measuring the absence of a marketplace, not the
   analyst. intel_director's *Categories with all eight knowledge modules* 2 vs 100 → **unit mismatch**, not a
   miss at all.

**Type 2 — "Volume, mix or rate?"**
1. Require a dimensioned metric; else refuse.
2. Compute `Q₀, Q₁` (totals) and `w_i, r_i` per dimension level for both periods.
3. Compute the three effects and the residual; the dominant effect is the one with the largest absolute value,
   and if two are within 20% of each other report **both** rather than picking.
4. State the arithmetic in the memo, not the conclusion alone.

**Type 4 — "What goes in the weekly founder brief?"**
1. Take every metric in scope that passes B3.
2. Rank by `|attainment − 100| × goal_weight`, where `goal_weight` is the goal's share of the AED 1M path
   (revenue goals 1.0; supply goals 0.6; knowledge and ops goals 0.2) — a stored table.
3. Take the top 3. The founder's own doctrine is a top-3 report.
4. Add one mandatory line: the count of goals that could not be reported and why.
5. Add the falsification condition on the headline.
6. **Never** substitute a proxy for an unmeasured goal. Silence with a reason is the honest form.

**Type 19 — "Is this root cause a cause or a restatement?"**
1. Take the recorded cause text.
2. Test it against a stored predicate: a cause must name **a different quantity** from the metric itself.
   "Attainment is 0% because throughput is 0" names the same quantity twice → restatement.
3. A cause must also name a **writer or an owner** — the thing that would have to change.
4. Verdict: cause | restatement | unfalsifiable. Restatements do not count toward the KPI.
   **Consequence the founder should know:** applying this test to the causes currently recorded in this
   department's `improvement_plan` fields, they are restatements. The seat's KPI of 78.35% is therefore
   **overstated**, and fixing the test will make it fall before it rises. That is the correct direction.

**Type 26 — "What is the confidence interval?"**
1. Read `n` and `k`.
2. If `n < n_min` (stored, default 30 for a proportion) → do not report a rate at all; report `k of n`.
3. Else compute B4 and report the interval alongside the point estimate, always.

### 4. Judgement rules

- **BJ-1.** Never state a number this seat has not itself measured in the same report run. *Its explicit
  forbidden decision.*
- **BJ-2.** Never change the underlying measurement to make a report work. Propose the change to
  `intel_director` and report the current definition meanwhile. *Also explicitly forbidden.*
- **BJ-3.** A rate over fewer than `n_min` observations is reported as `k of n`, never as a percentage.
- **BJ-4.** Every rate carries a Wilson interval. Point estimates alone are not reported.
- **BJ-5.** A zero is labelled `business zero` or `instrument unverified`; never printed bare.
- **BJ-6.** No proxy is ever substituted for an unmeasured goal. The report says the goal is unmeasured and
  names the `no_measure_reason`.
- **BJ-7.** A comparison window containing a `rehearsal_window` row is rejected outright.
- **BJ-8.** A definition change inside the compared window voids the comparison. Report the two periods
  separately.
- **BJ-9.** A restatement is not a root cause and does not count toward the KPI, **even though counting it
  would move this seat's own number from 78% toward 90%.** This is this seat's "do not do it even though it
  scores well" rule, and it is the sharpest one in the department.
- **BJ-10.** Correlation is never written as cause without a stated mechanism and a temporal ordering check.
- **BJ-11.** Axes start at zero for counts and money; any other baseline is stated in the caption.
- **BJ-12.** Escalate to `intel_director` when two surfaces disagree, when a target is arithmetic-impossible,
  or when the honest report would materially contradict a stated plan.
- **BJ-13.** A report that cannot state what would falsify its headline is not sent.

### 5. Technical knowledge

- **The reporting surfaces:** `exec_reports` (324), `board_reports` (172), `company_snapshot` (26),
  `metric_snapshot`, `goal_period`, `employee_kpi_history`, the ten `*_kpi_snapshots` tables, and the views
  `v_bi_scorecard`, `v_business_health`, `v_department_health`, `v_os_scoreboard`, `v_unit_economics`,
  `v_marketplace_liquidity`, `v_invite_funnel`, `v_customer_ltv`, `v_supply_gap`, `v_gap_report`.
- **The routines that produce report bodies:** `fn_bi_snapshot()`, `fn_org_scorecard()`, `fn_kpi_scoreboard()`,
  `fn_kpi_review()`, `fn_goal_attainment(horizon)`, `fn_goal_pace()`, `fn_company_snapshot()`,
  `fn_marketplace_analytics()`, `funnel_metrics(days)`, `fn_eval_snapshot(days)`.
- **The founder's reading conventions:** a top-3 report; the AED 15,000 / 3× anti-circumvention rule and the
  3% reveal fee are company facts that must appear correctly whenever money is described; brand wording and
  document branding come from `company_brand` (53 rows) and `brand_assets` (58).
- **Chart and table craft for a founder audience:** one claim per exhibit; the axis rule; sample size printed
  on every rate; the interval printed beside every proportion; the "as of" timestamp on every figure with its
  timezone named.
- **What a `bi_report` must contain** (the output contract): headline, pace, variance with class, what
  changed, what is not measured and why, falsification condition, citations.
- **Where the fixture boundary is:** `ZZ DEMO — ` / `@example.invalid` / `rehearsal_window`, and that a
  rehearsal in the window invalidates any comparison across it.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Statistical inference | Wilson score interval, two-proportion tests, multiple comparisons | NIST/SEMATECH e-Handbook (public domain) |
| Index numbers and variance analysis | Laspeyres/Paasche decomposition; volume-mix-rate bridges | Official-statistics methodology manuals published openly by national statistics offices |
| Data visualisation | Encoding choice, axis integrity, small multiples, avoiding dual axes | Open visualisation-grammar literature and the repo's own `dataviz` conventions |
| Cohort analysis | Cohort definition, survival curves, retention triangles | Open methodology papers; NIST e-Handbook (reliability chapter) for survival basics |
| Decision framing | Base rates, reference-class forecasting, anchoring | Published open decision-science literature |
| Business measurement | Leading vs lagging indicators, north-star and guardrail design | The 101 `ops-data_intel-deep-*` records already in `ops_knowledge` (2 Sep 2026) |
| Official UAE statistics | Series definitions and revision policy | Federal Competitiveness and Statistics Centre; Dubai Statistics Centre (**verify licence**) |

**Certifications this seat holds:**

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | Microsoft PL-300 Power BI Data Analyst | Microsoft | 70% | Prepare the Data · Model the Data · Visualize and Analyze the Data · Deploy and Maintain Assets |
| 2 | CAP (Certified Analytics Professional) | INFORMS | 70% | Business Problem Framing · Analytics Problem Framing · Data · Methodology Selection · Model Building · Deployment · Model Lifecycle Management |

**Syllabus areas it failed: does not exist** — no `certification_exam_result` row. The lexical exam is the
worst in the department: **5 correct of 36 (13.9%)**, 20 wrong, 11 partial, **0 not covered**, confidence 0.49,
3 answers filled, last sat 2026-09-07 03:23 UTC. The pattern matters more than the score: with 0 "not covered"
it **answered every question rather than declining**, and was wrong on 56% of them. For a seat whose forbidden
decision is *stating a number it has not measured*, a zero abstention rate is the exact failure mode to fix,
and it is fixed by making refusal a first-class output, not by adding knowledge.

### 7. Corporate knowledge

- **Its own KPI:** *"Variance explained with a root cause"*, 78.35% vs 90, monthly, measured 2026-09-07
  03:30 UTC from `org_tasks where title like 'KPI missed:%'` counting rows with a non-null `root_cause`.
  Applying BJ-9 will lower this number before it raises it.
- **It has no curriculum and no workflows.** 0 `employee_knowledge` rows, 0 `employee_workflow` rows, 1
  placeholder authority row. Before this seat can be held to a standard it needs its 12-layer binding — that
  is `knowledge_director`'s Q1 item.
- **What it may report on:** everything in `fn_dept_scope('data_intel')`. It has the narrowest knowledge
  scope of the seven (4 names against 15–18 for the others), which is a defect for a seat that reports on
  finance, supply and marketplace numbers.
- **The company facts every report must get right:** 3% reveal fee, AED 1,000/year supplier registration with
  the first 1,000 free, 5-working-day refund window with a 3-working-day chase, AED 250 admin fee, 9% p.a.
  interest, AED 15,000 / 3× anti-circumvention, 10 approved suppliers to open a category, top-3 comparison.
  All from `pricing_config` and `decision_policy`, not from memory.
- **Who it hands to:** `intel_director` only. Escalation to `chief_of_staff` for cross-department disputes.
- **Does not exist:** a `bi_report` template; any dimensioned metric; a root-cause quality test; an `n_min`
  anywhere.

### 8. One-year plan

**Objective.** Every miss has a cause that names a different quantity and an owner, and every rate the company
reads carries its sample size.

**Slice of the AED 1,000,000: AED 0 directly.** Its measurable contribution is that decisions taken on its
reports are taken on numbers that survive checking.

**Metrics it owns:**
1. **Variance explained with a root cause** — 78.35% vs 90, and expected to *fall* when BJ-9 is applied.
2. **New: reportable-figure share** — figures passing B3 ÷ figures requested. Baseline: does not exist.
3. **New: abstention rate on unanswerable questions** — target > 0. Baseline measured: **0%** on 36 exam
   questions.

**Quarterly milestones.**
- **Q1.** Get the 12 curriculum bindings and the workflow rows this seat lacks. Build the `bi_report`
  template with all seven slots. Apply BJ-9 to the recorded causes and report the honest fall.
- **Q2.** Wilson intervals and `k of n` on every rate in every report. Widen the knowledge scope beyond the
  four data names so it can lawfully report on finance and supply.
- **Q3.** First dimensioned metric (category × emirate) so B1 has an input; first real variance decomposition.
- **Q4.** Leading/lagging classification once a revenue series exists, or a written statement that it still
  does not.

**Capacity check.** Report composition from templates is cheap. The binding constraint is that **B1 has no
dimensioned input and B4 has n = 2 on the only rate the marketplace produces.** This seat can be excellent at
refusing well long before it can be excellent at explaining.

**Dependencies.** `analytics` for the SQL, `intel_director` for definitions and registration,
`knowledge_director` for the curriculum binding it does not have, and the whole business for a denominator.

**Plainly: the honesty half of the slice is achievable this quarter; the analysis half is not achievable until
a metric carries a dimension and a rate carries thirty observations.**

### 9. What this seat cannot do without a model

- Writing the connecting prose of a report in a register that reads like a person wrote it. The template
  produces a correct memo that reads like a template.
- Interpreting a trend whose cause lies outside the estate's tables (a competitor's price move, a regulatory
  change) — it can only report the movement and name that the cause is external and unmeasured.
- Choosing the *right* exhibit for an argument nobody has made before. Ranking by the stored weight table is
  mechanical and will sometimes lead with the wrong thing.

---

## market_analyst — Market Intelligence Analyst

`org_role.role_id = market_intelligence_analyst` · authority `advisory`, budget 0 · manager `intel_director` ·
owns *market and competitive assessment with sources* · forbidden *acting on the intelligence itself, stating
a competitor fact without a source* · outputs `market_brief` · required input `knowledge_lifecycle` ·
escalates to `data_intelligence_director`, `chief_of_staff`. `knowledge_acquire` is **autonomous** ("owns
market signal capture").

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Is this a market signal worth recording? | gate | continuously | own seat | its KPI is 0 signals vs 20/month; the table has never held a row |
| 2 | What is the source for this competitor claim? | gate | per claim | own seat, growth, ceo | its explicit forbidden decision; an unsourced claim in an investor document |
| 3 | Has this competitor changed its pricing? | diagnosis | monthly | ceo, growth | our 3% is compared against a stale "free" |
| 4 | Is a new competitor entering the anonymity space? | diagnosis | monthly | ceo | the single differentiator is lost without notice |
| 5 | Which of the 86 categories has the strongest UAE demand signal? | allocation | monthly | supply, growth, ceo | supply-building capital goes to a dead category |
| 6 | Is UAE construction output rising or falling? | forecast | quarterly | ceo, cfo | the demand model's base rate is wrong |
| 7 | What is the addressable size of category X in the UAE? | forecast | per category decision | supply, ceo | a category is opened that cannot produce 25,000 RFQs a year between all of them |
| 8 | Which emirate should supply-building target next? | allocation | quarterly | supply | invites go where the licences are not |
| 9 | Is a regulatory change about to move demand? | diagnosis | monthly | legal, ceo | a permit change closes a category overnight |
| 10 | Is a tender pipeline visible for this category? | diagnosis | monthly | supply, growth | the public-buyer channel is missed |
| 11 | Which competitor is closest to us on which dimension? | diagnosis | quarterly | ceo | positioning is built against the wrong rival |
| 12 | Is a competitor claim in our own marketing still true? | gate | per publication | growth, legal | a false comparative claim is published |
| 13 | Is this source lawful and current to cite? | gate | per source | own seat, legal | scraped or paywalled data is cited |
| 14 | What is the base rate for supplier registration on platforms like ours? | forecast | quarterly | supply, ceo | the 0.58% invite→approval rate is judged against nothing |
| 15 | Is our supplier invite response rate normal for this market? | diagnosis | monthly | supply | a normal rate is treated as a crisis, or a crisis as normal; measured today it is 0 registrations from 171 invitations and we hold nothing to compare it against |
| 16 | Which incumbent behaviour are we actually competing against? | diagnosis | quarterly | ceo, growth | we benchmark platforms while losing to WhatsApp |
| 17 | Is this "market" a market, or one buyer? | gate | per sizing | own seat | a pipeline of one is sized as a segment |
| 18 | What did this signal change about a decision? | craft | per signal | intel_director | signals accumulate and change nothing |
| 19 | Should a signal escalate immediately or wait for the brief? | escalation | per signal | own seat | a competitor launching anonymity waits a month |
| 20 | Is a price we observed comparable to ours? | craft | per price observation | own seat | a listing fee is compared to a transaction fee |
| 21 | Is this trend seasonal? | diagnosis | per series | ceo | Ramadan and summer are read as decline |
| 22 | How stale is this competitor record? | gate | per citation | own seat | `competitor.verified_at` ages and the 27 records quietly rot |
| 23 | Which categories do incumbents cover that we do not? | allocation | quarterly | supply, marketplace | we build depth where depth already exists |
| 24 | Is a supplier cluster forming or closing in this emirate? | diagnosis | monthly | supply | invite lists are built on companies that closed |
| 25 | What licence activity corresponds to this category? | craft | per category | supply, marketplace | the licence gate refuses valid suppliers |
| 26 | Is a public tender portal a channel or a competitor? | craft | quarterly | ceo | a channel is treated as a threat |
| 27 | What would have to be true for this market read to be wrong? | craft | per brief | own seat | an unfalsifiable brief |
| 28 | Is this claim about the UAE or about the GCC? | gate | per claim | own seat | Saudi construction data is presented as UAE demand |
| 29 | Which market fact has changed since the last brief? | craft | monthly | ceo | the brief repeats itself and is stopped being read |
| 30 | Is a competitor's stated feature actually shipped? | gate | per feature claim | growth | roadmap marketing is treated as capability |
| 31 | Which of our 27 competitors needs re-verification this quarter? | sequencing | quarterly | own seat | all 27 rot together |
| 32 | Does a market signal imply a pricing change? | escalation | rare | intel_director, ceo | this seat may not act; it must escalate |

### 2. Domain logic

**MK1 — Signal register.** A signal is a stored record, not an impression: `(kind, title, detail, source_url,
observed_at, effective_date, impact ∈ {high, medium, low}, affected_categories[], affected_emirates[],
decision_it_changes)`.
`impact` is computed, not judged: `high` if it touches pricing, anonymity or a licence gate;
`medium` if it changes a category's supply or demand base rate by > 20%; `low` otherwise.
Inputs: `market_intel` (kind, title, detail, source, impact, status, created_at).
**Measured today:** `market_intel` holds **0 rows** and the KPI reads 0 against a target of 20 per month.
The table's shape is adequate; it lacks `source_url`, `observed_at`, `affected_categories` and
`decision_it_changes`. **The seat has no writer and no source registry — both must exist before the KPI can
be anything but zero.**

**MK2 — Source registry.** `(source_name, publisher, url, cadence, licence_terms, last_checked, series_keys[])`
for every lawful source. Verdict on a citation is a lookup: a claim whose `source_url` is not in the registry
is refused.
**Unmeasured:** **does not exist.** `compliance_sources` (17 rows) is a compliance register, not this.
This is the single missing object that makes the seat's forbidden decision unenforceable today.

**MK3 — Competitor freshness and threat.**
`staleness_days = current_date − verified_at`; a record older than 90 days may not be cited without
re-verification. `threat = overlap_score × capability_score × distribution_score`, each 0–1 from stored
attributes.
Inputs: `competitor` (27 rows: name, url, kind, what_they_do, business_model, overlap, strength, weakness,
offers_anonymity, threat_level, verified_at, source_url), `competitive_position` (8 dimensions).
**Measured today:** 27 competitors across `marketplace`, `global_platform`, `tender_portal`, `directory`,
`adjacent`, `incumbent_behaviour`; `offers_anonymity` is the decisive column and the recorded position is that
**none of the verified competitors offers supplier anonymity**. This is the company's core claim and this seat
owns keeping it true.

**MK4 — Category demand proxy (no first-party demand exists).**
With `inquiries = 0`, demand cannot be measured internally. The lawful deterministic proxies are:
supplier density per category from `lead_category` (18,539 rows) and `catalog_supplier_categories` (86);
licence activity counts from the issuing authorities' public registers;
published construction and real-estate output series; public tender counts per category.
`demand_index = z(supplier_density) + z(tender_count) + z(output_growth)` — a standardised sum, all three
terms external or internal-structural, none of them a guess.
**Unmeasured:** the tender and output series are not ingested. `market_intel` is empty. So today the index
reduces to supplier density alone, and the brief must say so.

**MK5 — Base rates for the funnel.** The estate's own invite funnel is the only measured series. Measured
2026-09-07: 22,090 leads `not_contacted` with no invite status · **161** `no_response` with
`invite_status = 'sent'` · **10** `undeliverable` / `bounced` · 3 `no_response` with no invite status · **1**
`registered` and `approved` — and that single registered lead carries **no `invite_status` at all**, so it
did not come through the invite path. Measured strictly, invite→registration is therefore **0 of 171
invited**. (The 6 Sep audit reports 0.58%, i.e. 1 of 171, by attributing that lead to the invite cohort. The
disagreement is stated, not resolved — and resolving it is exactly the cohort-definition question at taxonomy
id 24 of the bi_analyst's list.)
A base rate from outside is needed to say whether either figure is bad. Sources: published marketplace and B2B
directory benchmarks with an open licence; the competitors' own published supplier counts against their
stated market age.
**Unmeasured:** no external base rate is stored. Until one is, the honest statement is *"0 registrations from
171 invitations; no comparable base rate is held, so this cannot yet be called good or bad."*

**MK6 — Seasonality adjustment.** For any monthly series, `index_m = mean(series in month m) / mean(series)`
over ≥ 3 years. UAE-specific effects to carry: Ramadan (moving), the summer slowdown (Jun–Aug), Q4 and Q1
construction pushes, and the Mon–Fri working week.
**Unmeasured:** the estate has no series of that length. This model waits on ingest of external series.

### 3. Reasoning procedures

**Type 2 — "What is the source for this claim?"**
1. Look up the claim's `source_url` in MK2.
2. Not present → **refuse**: `cannot state: source not in the registry`. Do not reason about it.
3. Present → check `last_checked` against the source's cadence; stale → refuse and schedule re-verification.
4. Check licence terms permit citation.
5. Emit the claim with the citation and the `verified_at` date.
   **This procedure is the whole of the seat's integrity and it cannot run today**, because MK2 does not
   exist. That is the first thing to build for this seat.

**Type 1 — "Is this a signal worth recording?"**
1. Deduplicate against `market_intel` on a normalised title + source hash.
2. Compute impact by MK1's rule.
3. Determine affected categories by matching the signal text against `category_keyword` (1,813 rows) and
   `subcategory_keyword` (6,489) — lexical, free.
4. Name the decision it changes; **if none can be named, do not record it.** A signal that changes no decision
   is noise, and 20 pieces of noise a month would satisfy the KPI while being worthless.
5. Write the row; `high` impact also escalates immediately rather than waiting for the brief.

**Type 5 — "Which category has the strongest demand signal?"**
1. Compute MK4 for all 86 categories.
2. Cross with `v_supply_gap` (approved suppliers per category) — the answer the company needs is
   `high demand ∧ low supply`, not high demand alone.
3. Cross with `category_licence_activity` to check the category is not gated by a permit nobody holds.
4. Rank; report the top 3 with each term of the index printed separately.
5. **Today's honest output:** only the supplier-density term is available; the ranking is a supply-structure
   ranking, not a demand ranking, and the brief must be labelled that way.

**Type 11 — "Which competitor is closest to us on which dimension?"**
1. Read all 8 `competitive_position` rows.
2. For each dimension, read the competitors whose `overlap` text matches that dimension's terms.
3. Rank by MK3's threat score.
4. Report per dimension, with `verified_at` beside every competitor named.
   **Standing result the seat must not lose:** on *supplier anonymity* the recorded market norm is that not
   one of the verified competitors offers it, and on *buyer cost* the market norm is free while ours is 3%.
   Those two facts together are the company's entire positioning, and they are the two most important things
   in this department's custody.

**Type 22 — "How stale is this competitor record?"**
1. `staleness_days` per row.
2. Over 90 days → not citable; open a re-verification task.
3. Re-verification means visiting the source URL and recording what changed — an act with no model in it.
4. Rank the 27 by `threat × staleness` and re-verify in that order, a stored quarterly schedule.

### 4. Judgement rules

- **MJ-1.** No competitor fact leaves this desk without a source URL and a `verified_at` date. *Explicit
  forbidden decision.*
- **MJ-2.** A source not in the registry is not a source. Refuse rather than reason from memory.
- **MJ-3.** A competitor record older than 90 days is not citable.
- **MJ-4.** A signal that changes no named decision is not recorded — **even though recording it would move
  the KPI from 0 toward 20.** This is this seat's "do not do it even though it scores well" rule, and it is
  the one that matters most, because the KPI is currently the loudest failure in the department and the
  cheapest to fake.
- **MJ-5.** GCC is not UAE. Any claim must state its geography, and a GCC figure may not stand in for a UAE one.
- **MJ-6.** A listing fee, a subscription and a transaction fee are not comparable. Price comparisons state
  the fee's basis.
- **MJ-7.** Never act on the intelligence — no outreach, no pricing suggestion executed, no supplier contacted.
  *Explicit forbidden decision.* Route to the owning seat.
- **MJ-8.** Scraping is bounded by robots and terms; Apify is paused until approximately February 2027, so no
  scraped acquisition is planned in this year.
- **MJ-9.** Personal data of sole traders is personal data under PDPL; a market register may hold company
  facts, not individuals' details.
- **MJ-10.** Escalate immediately, outside the brief cycle, when: a competitor announces supplier anonymity;
  any competitor introduces a buyer-side fee; a licence or permit regime changes for a live category; a
  regulator names the RFQ or marketplace category.
- **MJ-11.** A market read carries its falsification condition — "this read is wrong if X is observed".
- **MJ-12.** Never present a supply-structure ranking as a demand ranking.

### 5. Technical knowledge

- **The estate's market objects:** `market_intel` (0 rows), `competitor` (27), `competitive_position` (8),
  `marketing_category_demand`, `meta_insights`, `brand_signal`, `scrape_runs` (28), `screening_entry` (4,961),
  `yello_staging` (13,123), `leads` (22,265 with sector, sub_type, emirate, city, categories, license_activity,
  license_authority), `lead_category` (18,539), `lead_subcategory` (25,438), `category_keyword` (1,813),
  `subcategory_keyword` (6,489), `catalog_supplier_categories` (86), `catalog_subcategories` (468),
  `catalog_domains` (66), `mdm_emirates`, `mdm_cities` (18), `mdm_brands` (51), `regulations` (17),
  `reg_catalog` (38), `compliance_sources` (17), `category_licence_activity`.
- **UAE market structure it must hold as data, not memory:** the seven emirates and their licence issuers
  (DET for Dubai, ADDED/TAMM for Abu Dhabi, SEDD for Sharjah, and Ajman, RAK, Fujairah, UAQ); the free-zone
  authorities (JAFZA, DMCC, DAFZA, DSO, IFZA, RAKEZ, SHAMS, SAIF, KEZAD); the sector regulators that gate
  categories (Civil Defence, SIRA, Dubai Municipality, DEWA/ADDC, RTA, MOIAT/ECAS, MOCCAE, TDRA, RERA/DLD);
  the public procurement portals (Dubai eSupply, Abu Dhabi ADGPG, the federal platform at procurement.gov.ae).
  **Verify every portal and authority against its own site before ingest** — none of these is currently a
  stored record in this department's scope.
- **The competitor taxonomy already in the table:** marketplace, global_platform, tender_portal, directory,
  adjacent, incumbent_behaviour — and the fact that the recorded incumbent behaviour is *"WhatsApp to three
  known contractors"* and *"Google Search and Maps"*, not a platform at all.
- **Citation mechanics:** `kb_chunks.citation` and `effective_date` (2.68M and 2.59M rows populated
  respectively); `ops_knowledge.source_ids`, `source_type`, `source_authority`, `source_freshness`.
- **The company's own position** as recorded in `competitive_position`: anonymity, price discovery,
  verification behind an AED 1,000/year gate, 3% buyer cost against a free market norm, category depth an
  order of magnitude behind incumbents, speed to first quote unproven and structurally batch, and **no
  verified distribution asset**.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Market research method | Research design, sampling, data collection, reporting, ethics | Market Research Society published Code of Conduct and guidance (open); ESOMAR published guidelines |
| Industrial organisation | Two-sided market economics, network effects, chicken-and-egg entry, multi-homing | Open-access economics working papers and published regulator market studies |
| Competitive analysis | Structural analysis of an industry; substitute vs rival mapping | Published competition-authority market-study methodology (e.g. open guidance from competition regulators) |
| Official statistics | Series definitions, revision policy, seasonal adjustment | UAE Federal Competitiveness and Statistics Centre; Dubai Statistics Centre; Abu Dhabi Statistics Centre — each publishes methodology notes (**verify licence**) |
| Construction and real-estate demand | Project pipeline, permit and contract-award series as demand leading indicators | Dubai Land Department / RERA published data; Dubai Municipality permit statistics; public tender portals (**verify**) |
| Public procurement | UAE federal and emirate procurement rules and supplier registration prerequisites | The federal procurement platform, Dubai eSupply and Abu Dhabi ADGPG published rules (primary, public) |
| Forecasting | Base rates, reference-class forecasting, standardisation (z-scores) | NIST e-Handbook; open forecasting-competition documentation |
| Data protection in research | Lawful basis for holding business-contact data | UAE Federal Decree-Law 45/2021 (PDPL) and UAE Data Office guidance |

**Certifications this seat holds:**

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | MRS Advanced Certificate in Market and Social Research Practice | Market Research Society | 50% | The Research Environment · Research Design · Data Collection Methods · Sampling · Data Analysis and Interpretation · Reporting Findings · Legal and Ethical Standards |
| 2 | CAP (Certified Analytics Professional) | INFORMS | 70% | Business Problem Framing · Analytics Problem Framing · Data · Methodology Selection · Model Building · Deployment · Model Lifecycle Management |

**Syllabus areas it failed: does not exist** — no `certification_exam_result` row. The lexical exam measured
**7 correct of 30 (23.3%)**, 7 wrong, 12 partial, 4 not covered, confidence **0.41** (the lowest but one in
the department), **7 answers filled**, last sat 2026-09-07 03:23 UTC. The MRS syllabus area *Legal and Ethical
Standards* maps directly onto MJ-1, MJ-2, MJ-8 and MJ-9 and is the area the estate can most cheaply teach from
primary sources.

### 7. Corporate knowledge

- **Its own KPI:** *"Market signals captured"* — target 20 signals per 30 days, **actual 0**, measured
  2026-09-07 03:30 UTC from `market_intel where created_at > now() − interval '30 days'`. The table has never
  held a row. By the bi_analyst's B2 tree this is class 2 (NO THROUGHPUT / instrument), not a performance
  failure — but unlike the other zeros in this department, **this one is genuinely this seat's to fix**,
  because it owns `knowledge_acquire` autonomously and the writer it needs is its own.
- **The 27 verified competitors and the 8 scored dimensions are this company's best evidence asset** and this
  seat is their custodian. Their `verified_at` dates are the seat's most important operational clock.
- **The founder's decisions this seat must never re-open:** the 3% reveal fee; anonymity as the product;
  AED 1,000/year supplier registration; the AED 15,000 / 3× anti-circumvention rule; the top-3 comparison.
  Market intelligence informs these; it does not change them, and this seat may not act on its own findings.
- **Apify is paused until approximately February 2027** — no paid scraping is available this year, which
  constrains MK4's external terms to what can be read from published portals.
- **Arabic:** the 6 Sep audit measured 0 Arabic content across 32 blogs, 24 SEO pages, 484 FAQ rows and 13
  response templates. A market analyst in the UAE working only in English is a real limitation on source
  coverage, and it belongs on this plan.
- **Does not exist:** the source registry (MK2); any UAE statistics series in the department's scope
  (the 6 Sep audit measured Dubai Statistics 0, DET 0, RERA 0, FCSC 0, Dubai Municipality 0 mentions in the
  data-department ops rows); any tender-pipeline data; any external base rate for the invite funnel.

### 8. One-year plan

**Objective.** Every market claim the company makes has a source, a date and a decision it changes; and the
company knows whether its own funnel rates are normal.

**Slice of the AED 1,000,000: AED 0 directly, and one causal contribution that can be measured.** The seat's
lawful claim on revenue is **category selection**: if MK4 plus `v_supply_gap` routes supply-building to
categories with real demand, the effect shows up in registrations and then in RFQs. That chain is measurable
once the first link exists; today it does not, and the seat should not claim a share of the AED 1M.

**Metrics it owns:**
1. **Market signals captured** — 0 vs 20/month. To be re-defined as *signals recorded that name a decision*,
   or the KPI will be met by noise (MJ-4).
2. **New: citable-source coverage** — competitor and market claims whose source is in the registry and fresh
   within cadence. Baseline: 0, because the registry does not exist.
3. **New: competitor record freshness** — share of the 27 verified within 90 days.

**Quarterly milestones.**
- **Q1.** Build MK2, the source registry, and populate it with the UAE statistics portals, the emirate licence
  authorities, the sector regulators and the three procurement portals — **each verified against its own site
  before it is entered.** Re-verify the 27 competitor records. Add the four missing columns to `market_intel`.
- **Q2.** First MK4 index across 86 categories on the terms that exist, published with its limits stated.
  Ingest the first external series (construction output, permits) under a recorded licence.
- **Q3.** External base rates for the invite funnel so the measured 0-of-171 can finally be judged.
  Seasonality index once a series exists.
- **Q4.** Quarterly competitor re-verification on the `threat × staleness` schedule; a written market read with
  its falsification condition.

**Capacity check.** Signal capture and registry maintenance are record-writing, well inside `max_open_tasks`
50 and the 11 deterministic runs a week the 6 Sep audit measured. The binding constraint is **external
source access without paid scraping**: everything must come from published portals read directly, which is
slower and narrower than the estate assumes.

**Dependencies.** `knowledge_director` for the ingest route and the licence gate; `legal` for the lawfulness
of each source; `supply` to act on the category ranking (this seat may not act); `intel_director` for
escalation.

**Plainly: the source-registry half is achievable and overdue; the demand-index half is only as good as the
external series we can lawfully read, and with Apify paused that is a genuine ceiling this year.**

### 9. What this seat cannot do without a model

- Reading a competitor's website and deciding what changed since the last visit. Fetching is mechanical;
  **judging that a re-worded page means a new business model is not.** The deterministic substitute is a
  content hash plus a diff, escalated to a person when it changes materially.
- Summarising a 40-page statistical bulletin into a market read. It can extract named series and compute
  changes; it cannot write the interpretation.
- Recognising a category-defining event that fits no stored signal kind. The taxonomy catches what it has seen
  before.

---

## supplier_analyst — Supplier Intelligence Analyst

`org_role.role_id = supplier_intelligence_analyst` · authority `advisory`, budget 0 · manager `intel_director` ·
owns *supplier reliability risk price and response scoring, customer lifetime value and churn assessment,
manufacturer brand and catalogue intelligence* · forbidden *confirming or suspending a supplier, setting
price, acting on its own score* · outputs `supplier_intelligence`, `customer_intelligence` · required inputs:
**none declared** · escalates to `data_intelligence_director`, `chief_of_staff`. `capability_review` is
autonomous ("owns supplier and customer scoring"). It holds **0 `employee_workflow` rows**.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | What is this supplier's reliability score? | craft | per match, per RFQ | marketplace, supply | an unreliable supplier is put in front of a paying buyer |
| 2 | Is a null score "unknown" or "bad"? | gate | every score read | own seat, marketplace | 20,463 of 20,465 rows are null by design; coalescing them to 0 condemns the whole base |
| 3 | Does this supplier have enough history to be scored at all? | gate | per supplier | own seat | a cold-start supplier is ranked against one with 50 quotes |
| 4 | Which suppliers should be invited to this RFQ? | allocation | per RFQ | marketplace | the buyer sees three quotes from the wrong trade |
| 5 | Is this supplier's capability claim corroborated? | gate | per capability | supply, marketplace | 15,306 derived capability rows, 0 confirmed — a derived claim is treated as a confirmed one |
| 6 | Should this supplier be excluded from matching? | escalation | per strike event | marketplace | this seat may not suspend; it must escalate |
| 7 | Is this supplier's price position high, normal or low? | diagnosis | per category | marketplace, ceo | a buyer is shown a spread that is an artefact of two quotes |
| 8 | What is this customer's lifetime value? | forecast | per customer | ceo, growth | acquisition spend is set from a number with one customer behind it |
| 9 | Is this customer at risk of churn? | forecast | monthly | customer_experience | retention effort goes to the wrong account |
| 10 | Which categories are under-supplied against the floor of 10? | allocation | weekly | supply | RFQs open in categories that cannot fill |
| 11 | Is this supplier a duplicate of one we already hold? | gate | per registration | supply, own seat | the same company is invited twice and the anonymity set is smaller than it looks |
| 12 | Which manufacturer brands does this supplier actually carry? | craft | per supplier | marketplace | a brand-named RFQ is routed to a supplier who cannot supply it |
| 13 | Is this supplier's licence activity consistent with the category? | gate | per match | supply, legal | a supplier without the licensed activity is matched into a regulated category |
| 14 | Is a supplier's document set expiring? | diagnosis | weekly | supply | a matched supplier's licence lapsed last month |
| 15 | Is this response-rate figure trustworthy at this n? | gate | per report | own seat | "response rate 100%" from 2 of 2 |
| 16 | What is the cold-start prior for a new supplier? | craft | per new supplier | marketplace | new suppliers are permanently ranked last and never earn a score |
| 17 | Is the matching score threshold right at 35? | escalation | quarterly | marketplace, intel_director | below-floor suppliers are contacted, or good ones are never seen |
| 18 | Are the scoring weights still right? | escalation | quarterly | intel_director | the weights are 40/20/15/15/15 and have never been validated against an outcome |
| 19 | Which supplier attributes actually predict a won quote? | diagnosis | quarterly, once outcomes exist | own seat | the model weights beliefs instead of evidence |
| 20 | Is this supplier's inactivity a churn signal? | diagnosis | monthly | supplier_success | a dormant supplier is written off, or a churned one is still counted as coverage |
| 21 | Is a supplier's quote completeness good enough to submit? | gate | per quote | marketplace | an incomplete quote reaches a buyer and burns the reveal |
| 22 | Is a supplier concentration risk forming in a category? | diagnosis | monthly | supply, ceo | one supplier holds a category and the anonymity promise is empty |
| 23 | Does this category have enough suppliers for a blind comparison to mean anything? | gate | per category open | marketplace | a "blind" comparison of two quotes is not a comparison |
| 24 | Is this supplier's reported team size / capacity plausible? | diagnosis | per registration | supply | a two-person firm is matched to a AED 2m package |
| 25 | Which emirate does this supplier actually serve? | craft | per match | marketplace | a Fujairah supplier is matched to a same-day Dubai job |
| 26 | Which suppliers are worth re-inviting? | allocation | monthly | supply | re-invites go to bounced or closed companies |
| 27 | Is this lead's company record stale or closed? | gate | per invite | supply | 2 leads are marked permanently closed; the rest are unverified |
| 28 | Should a supplier's strike count reset? | escalation | per strike | marketplace | `matching_strike_limit = 3`; a wrong reset re-exposes buyers to a non-responder |
| 29 | Is a supplier attempting circumvention? | escalation | rare | trust_safety, legal | the AED 15,000 / 3× rule exists and nobody is measuring for it |
| 30 | What is the observed spread between the cheapest and dearest quote in this category? | diagnosis | monthly | ceo, marketplace | the platform's core value claim — price discovery — is unquantified |
| 31 | Which supplier data field is blocking a match? | diagnosis | per unmatched RFQ | marketplace | RFQs go unmatched and nobody knows which field caused it |
| 32 | Is the capability-matching switch producing better matches than keyword retrieval? | diagnosis | quarterly | marketplace, intel_director | `use_capability_matching` is on and has never been compared against the alternative |
| 33 | Is a supplier's registration fee status blocking a match it should not? | gate | per match | supply, finance | the first 1,000 suppliers are free; a wrongly-charged supplier is lost |

### 2. Domain logic

**S1 — Reliability score (as deployed, and its defect).** `fn_supplier_score_refresh()` computes:
`reliability = round(least(100, greatest(0,
  rv_response_rate × 0.55
+ (won / submitted × 100) × 0.25
+ (verified ? 20 : 0)
− rejected × 2
− rv_nonresponse_refunds × 5)), 1)`,
and deliberately returns **NULL** when `rv_response_rate is null` **and** `quotes_submitted = 0` — the
function's own comment says "UNMEASURED IS NOT UNRELIABLE".
Inputs: `leads` (rv_response_rate, verified, rv_nonresponse_refunds), `quotes` (submitted/won/rejected,
price_index), `reviews` (quality rating × 20, verified suppliers only).
**Measured today:** 20,465 `supplier_score` rows; `reliability` non-null on **2**; `price_index` **0**;
`quality_rating` **0**; `quotes_submitted > 0` on **0**; last computed **2026-08-16 03:40 UTC**, three weeks
stale. The function is correct. The score is empty because `quotes` and `reviews` are both empty. The KPI
"Supplier scoring coverage" reads **0.01% against 95** and is measuring the absence of a marketplace.
**The defect that is real:** the weights (0.55 / 0.25 / 20 / −2 / −5) have never been fitted to an outcome,
and there is no cold-start prior — a new supplier with no history is NULL forever rather than starting at a
declared prior with a widening interval as evidence arrives.

**S2 — Matching score (the live one, in `decision_policy`).**
`score = 40·product_match + 20·brand_match + 15·project_type_match + 15·track_record + 10·size_fit`,
dispatched only when `score ≥ match_relevance_floor` (**35**), fan-out capped at `match_max_fanout` (**5**)
and `match_max_fanout_per_trade` (**3**), suppliers dropped after `matching_strike_limit` (**3**)
consecutive unanswered RFQs, `use_capability_matching = true`.
Inputs: `supplier_capabilities` (15,306), `lead_category` (18,539), `lead_subcategory` (25,438),
`category_keyword` (1,813), `subcategory_keyword` (6,489), `mdm_brands` (51), `supplier_score`.
**Measured today:** `inquiry_matches` **0 rows** — the matcher has never produced a match in production. The
weights exist as five `decision_policy` keys and **are described in no knowledge record**, so the seat that
owns supplier scoring cannot currently state its own model from stored knowledge.

**S3 — Cold-start prior with a shrinking interval.** For a supplier with `n` observations,
`score_reported = (n × observed + k × prior) / (n + k)` where `k` is the stored prior strength (a
pseudo-count) and `prior` is the category's own mean once one exists, else a declared constant.
Report a Wilson-style interval alongside; refuse to rank on the point estimate while the interval spans more
than a stored width.
**Unmeasured:** no prior, no `k`, no category mean — `quotes` is empty so no category has a mean.

**S4 — Capability corroboration.** A capability claim is `derived` (inferred from the lead's own text,
category or website) or `confirmed` (the supplier stated it in the portal, or a document evidences it).
`corroborated = derived ∧ (confirmed ∨ document_evidence ∨ ≥ 2 independent derivations)`.
Inputs: `supplier_capabilities` (15,306 derived), `supplier_capability_confirmation` (**empty**),
`leads.manufacturer_authorizations`, `iso_certifications`, `brands_carried`, `catalogue_pdfs`.
**Measured today:** 15,306 derived, **0 confirmed**. Every capability in the estate is an inference. A match
built on them is a match built on inference, and the buyer must never be told otherwise.

**S5 — Customer lifetime value.** `LTV = average_reveal_fee × reveals_per_customer_per_year × expected_years`,
where `average_reveal_fee = average_quote_value × 0.03`.
Inputs: `transactions`, `customers`, `inquiries`.
**Measured today:** `transactions` **0**, `customers` **1**, `inquiries` **0**, `customer_score` **0**.
Every term is undefined. `fn_customer_forecast(customer, horizon)` exists and has nothing to forecast from.
The correct output is a refusal naming all four tables.

**S6 — Churn risk.** `risk = w₁·days_since_last_activity/threshold + w₂·(1 − response_rate) + w₃·strike_count/3`.
Inputs: `leads.last_active` / `portal_updated_at`, `supplier_score`, `chat_strikes`, `rv_response_rate`.
**Partially available for suppliers, not at all for customers.** For suppliers the inputs exist in shape and
are empty in fact; for customers there is one row.

**S7 — Category liquidity and concentration.**
`liquidity = approved_suppliers_in_category / category_open_min_suppliers` (the floor is **10**, from
`pricing_config.category_open_min_suppliers`);
`concentration = HHI = Σ (share of quotes per supplier)²` — a category with HHI above a stored ceiling cannot
offer a meaningful blind comparison.
Inputs: `v_supply_gap`, `catalog_supplier_categories` (86), `lead_category`, `quotes`.
**Measured today:** 86 categories, **0 at the 10-supplier floor**, 3 with any approved supplier. Liquidity is
0.0–0.1 everywhere. HHI is undefined because no category has quotes. **This is the single most decision-
relevant number this seat owns and it says the marketplace cannot yet run a blind comparison anywhere.**

**S8 — Price position.** `price_index = supplier's mean quote ÷ category median quote`, reported only with
`n ≥ n_min` quotes in the category and only as a band (low / normal / high), never as a rank.
**Measured today:** `price_index` is populated on **0** of 20,465 `supplier_score` rows, because `quotes` is
empty.

### 3. Reasoning procedures

**Type 1 — "What is this supplier's reliability score?"**
1. Read `supplier_score` for the lead. Check `computed_at` against the refresh cadence — **today every row is
   from 2026-08-16 and is stale.**
2. If `reliability is null`, do **not** substitute 0. Read S1's own condition: null means no response history
   and no quotes. Emit `unscored — no evidence`, with the counts that made it null.
3. If non-null, check `n` (submitted + reveals). Below `n_min` → emit the score with S3's interval and the
   words "provisional".
4. Cross-check the components: response rate from `leads.rv_response_rate`, wins from `quotes`, verification
   from `leads.verified`, refunds from `rv_nonresponse_refunds`. If any component's source table is empty,
   name it.
5. Compose `supplier_intelligence` with every component printed, never the composite alone.
   **Today's honest output for any supplier:** `unscored — 2 of 20,465 suppliers carry a reliability value;
   quotes = 0 and reviews = 0, so the win-rate and quality terms have no input; scores last computed
   2026-08-16.`

**Type 4 — "Which suppliers for this RFQ?"**
1. Resolve the RFQ's category and subcategory from `category_keyword` / `subcategory_keyword` (lexical) and
   the trade from `taxonomy_trade` (40) / `mep_trade_pattern` (96).
2. Candidate set from `lead_category` / `supplier_capabilities` in the right emirate
   (`leads.service_emirates`).
3. Apply the hard gates first, in order: `approval_status = 'approved'` → `matching_blocked = false` →
   licence activity consistent (`leads.license_activity` vs `category_licence_activity`) → document expiry not
   passed → strike count < 3.
4. Score by S2. Drop below 35.
5. Cap at 5 overall, 3 per trade.
6. Rank by score, tie-break by S1 reliability, then by longest time since last invitation (to spread load).
7. **Stop:** if fewer than the floor of suppliers survive, refuse the match and open a supply-gap task rather
   than dispatching a thin set. A blind comparison of one quote is not a comparison.
   **Today:** step 3 leaves at most 3 candidates estate-wide across all 86 categories.

**Type 2 — "Is a null score unknown or bad?"** — always **unknown**. This is a one-step procedure and it
exists because the mistake is so easy: `coalesce(reliability, 0)` anywhere in a ranking would rank 20,463
suppliers as maximally unreliable. The seat's job is to make that impossible in every consumer of the score,
not to catch it afterwards.

**Type 10 — "Which categories are under-supplied?"**
1. Read `v_supply_gap` for all 86.
2. Compute S7 liquidity per category.
3. Cross with the market_analyst's MK4 demand index where it exists.
4. Rank by `demand × (1 − liquidity)` — the gap that costs the most.
5. Hand to `supply`; **this seat may not act on it.**

**Type 5 — "Is this capability claim corroborated?"**
1. Read the capability row and its derivation source.
2. Look for a confirmation row (`supplier_capability_confirmation` — empty today).
3. Look for document evidence (`manufacturer_authorizations`, `iso_certifications`, `catalogue_pdfs`,
   `brands_carried`).
4. Look for ≥ 2 independent derivations (e.g. the website text and the licence activity both imply it).
5. Verdict: `confirmed | corroborated | derived_only`. Anything `derived_only` is labelled as such wherever it
   is used, including in a match explanation.
   **Today: all 15,306 are `derived_only`.**

**Type 30 — "What is the price spread in this category?"**
1. Require `n ≥ n_min` quotes in the category from at least 3 distinct suppliers.
2. Compute min, median, max and `(max − min)/max` — the same shape `fn_marketplace_analytics()` already uses
   for `avg_savings_pct`.
3. **Refuse today:** 0 quotes exist. This is the number that proves the company's price-discovery claim, and
   it is currently unprovable — which the founder should hear plainly rather than as a gap in a table.

### 4. Judgement rules

- **SJ-1.** A null score is never coalesced to zero, in any query, ever. *Unmeasured is not unreliable.*
- **SJ-2.** A score below `n_min` observations is reported as provisional with its interval, never as a rank.
- **SJ-3.** A derived capability is labelled derived wherever it is used, including inside a match.
- **SJ-4.** This seat never confirms or suspends a supplier and never sets a price. It escalates.
  *All three are explicit forbidden decisions.*
- **SJ-5.** A supplier whose licence activity does not cover the category is not matched, whatever it scores.
  *The gate is before the score, not after it.*
- **SJ-6.** A supplier with an expired document is not matched, whatever it scores.
- **SJ-7.** A quality rating exists only for a verified supplier with a real post-job review. A Google Maps
  star rating is never presented as a QuotesDone quality rating. *Founder decision, 8 Aug 2026, and it is
  already enforced in `fn_supplier_score_refresh`.*
- **SJ-8.** Fewer than the floor of qualified suppliers → refuse the match and open a supply-gap task, **even
  though dispatching a thin set would make the fill-rate metric look better.** This is this seat's "do not do
  it even though it scores well" rule.
- **SJ-9.** A price position is a band, never a rank, and never below `n_min`.
- **SJ-10.** Never re-invite a lead marked `permanently_closed`, `bounced` or `banned`.
- **SJ-11.** Escalate to `intel_director` when the scoring weights would change; to `marketplace` and
  `trust_safety` on a suspected circumvention; to `supply` on a supply gap; to `legal` on a licence
  inconsistency in a regulated category.
- **SJ-12.** A score older than its refresh cadence is not used in a live match. *Today every score is three
  weeks old.*
- **SJ-13.** Never present a supplier count as coverage without saying how many are approved and unblocked.
  22,265 leads, 1 approved.

### 5. Technical knowledge

- **The supplier objects:** `leads` (about 150 columns — approval_status, verification_status,
  matching_blocked, matching_block_reason, licence fields, insurance and ISO expiry, capability_score,
  rv_reveals / rv_responded / rv_response_rate / rv_nonresponse_refunds, invite_status, lifecycle_stage,
  registration_status, subscription_paid_until, service_emirates, brands_carried,
  manufacturer_authorizations, machinery, team_size, engineers_count, warehouse_area, client_references,
  embedding_gte), `supplier_score`, `supplier_capabilities` (15,306), `supplier_capability_confirmation`
  (empty), `lead_category`, `lead_subcategory`, `lead_trade_map` (63), `catalog_supplier_categories` (86),
  `catalog_subcategories` (468), `category_licence_activity`, `taxonomy_trade` (40), `mep_trade_pattern` (96),
  `mdm_brands` (51), `screening_entry` (4,961).
- **The routines:** `fn_supplier_score_refresh()`, `fn_supplier_capability_score(leads)`,
  `fn_customer_supplier_score(customer, supplier)`, `fn_supplier_market(lead_id)`,
  `fn_supplier_knowledge_graph(lead_id)`, `fn_graph_supplier_market()`, `fn_customer_forecast(customer,
  horizon_days)`, `fn_category_specialist_scorecard(days)`, `fn_quote_category_score`,
  `fn_quote_structured_score`, `fn_rfq_score(inquiries)`.
- **The views:** `v_supply_gap`, `v_supplier_intelligence`, `v_supplier_alignment`, `v_supplier_load`,
  `v_supplier_pricing`, `v_supplier_doc_score`, `v_supplier_match_exclusions`, `v_supplier_coi`,
  `v_supplier_exception_board` / `_queue` / `_health` / `_outcomes`, `v_customer_ltv`, `v_customer_master`,
  `v_marketplace_liquidity`, `v_invite_funnel`, `v_invite_nonresponders`, `v_mkt_underpriced`,
  `v_mkt_response_by_category`, `v_mkt_brand_by_category`, `v_mkt_over_budget`.
- **The live decision constants** it must quote from `decision_policy`, never from memory: `score_w_product`
  40, `score_w_brand` 20, `score_w_track_record` 15, `score_w_project_type` 15, `score_w_size_fit` 10,
  `match_relevance_floor` 35, `match_max_fanout` 5, `match_max_fanout_per_trade` 3, `matching_strike_limit` 3,
  `use_capability_matching` true, `fraud_score_max` 0.7, `sensitive_categories`
  {fire, security, electrical, structural, gas, lifts, medical}.
- **The commercial constants** from `pricing_config`: reveal 3%, registration AED 1,000/year, first 1,000 free,
  category opens at 10 approved suppliers, refund window 5 working days with a 3-working-day chase, bank
  settlement 7–14 working days.
- **UAE supplier structure:** the emirate licence issuers and free zones; the sector regulators that gate the
  `sensitive_categories`; what a trade licence, an establishment card, a TRN and an ICV certificate each are
  and what a valid one looks like. **None of this is a stored record in this seat's scope today.**

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Procurement and supply | Supplier segmentation (Kraljic-style), pre-qualification, supplier performance measurement, whole-life cost | CIPS published open guidance and its syllabus outlines; UAE federal and emirate procurement rules (public) |
| Scoring and rating design | Weighted additive models, normalisation, cold-start priors, shrinkage estimators | NIST/SEMATECH e-Handbook; open statistics texts under permissive licences |
| Reliability and survival | Hazard rates, censored observations (a supplier who has never been asked is censored, not failed) | NIST e-Handbook, chapter 8 (Assessing Product Reliability) |
| Market concentration | HHI, concentration ratios | Competition-authority published methodology (open) |
| Two-sided liquidity | Fill rate, thickness, match quality | The 101 `ops-data_intel-deep-*` records ("Marketplace liquidity is the master metric, not GMV") already in `ops_knowledge` |
| Customer analytics | Cohort retention, LTV, churn hazard | Open marketing-science literature and NIST e-Handbook survival methods |
| Fraud and circumvention | Typologies for disintermediation in marketplaces | Published regulator and industry typology guidance (open) |
| UAE company verification | Trade licence structure, activity codes, free-zone vs mainland, TRN | Ministry of Economy National Economic Register; the emirate licensing authorities' own portals (**verify each**) |

**Certifications this seat holds:**

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | CAP (Certified Analytics Professional) | INFORMS | 70% | Business Problem Framing · Analytics Problem Framing · Data · Methodology Selection · Model Building · Deployment · Model Lifecycle Management |
| 2 | CIPS Level 4 Diploma in Procurement and Supply | CIPS | 50% | Scope and Influence of Procurement and Supply · Defining Business Needs · Commercial Contracting · Ethical and Responsible Sourcing · Commercial Negotiation · Supplier Relationships · Whole Life Asset Management |

**Syllabus areas it failed: does not exist** — no `certification_exam_result` row. The lexical exam measured
**10 correct of 30 (33.3%)**, 11 wrong, 1 partial, 8 not covered, confidence **0.42**, and **12 answers
filled** — the most fills of any seat in the department, last sat 2026-09-07 03:23 UTC.

### 7. Corporate knowledge

- **Its own KPI:** *"Supplier scoring coverage"* — suppliers carrying a reliability score ÷ all leads, target
  95%, **actual 0.01%** measured 2026-09-07 03:30 UTC. By the bi_analyst's tree this is class 3 (TOTAL
  CONVERSION FAILURE) with the cause being that `fn_supplier_score_refresh` **correctly** writes NULL when
  there is no evidence. The KPI as written can only be met by fabricating scores. **It should be re-defined
  as coverage among suppliers with any history**, and that redefinition belongs to `intel_director`.
- **The founder's rulings this seat operates inside:** anonymity is the product (suppliers quote blind);
  quality ratings are earned on the platform and never scraped (8 Aug 2026); a supplier who does not respond
  three times stops receiving RFQs (3 Aug 2026); the reveal is 3% and the anti-circumvention remedy is
  AED 15,000 or 3× the reveal fee; a category opens at 10 approved suppliers; a phone may confirm but never
  select — email is the identity.
- **The state of the supply side, which it must state accurately every time:** 22,265 leads; 19,896 with an
  email and **0 verified valid**; 171 ever invited; 10 bounced; **1 approved supplier**; 15,306 derived
  capabilities and 0 confirmed; 0 of 86 categories at the 10-supplier floor.
- **It has no workflows** (0 `employee_workflow` rows) — it is scored on an output contract with no wired
  process behind it.
- **Does not exist:** a cold-start prior; any fitted weight; a `supplier_capability_confirmation` row; a
  documented scoring runbook (the five weights live only as `decision_policy` keys); any customer analytics
  input beyond a single customer row; a circumvention-detection query.

### 8. One-year plan

**Objective.** Every supplier the marketplace shows a buyer is one the estate can justify in writing, and the
company knows which categories can actually run a blind comparison.

**Slice of the AED 1,000,000: AED 0 today, and the clearest causal path of the seven once demand starts.**
Revenue is `reveals × average quote × 3%`, and a reveal happens only when a buyer sees a comparison worth
paying for. That depends on match quality, which is this seat's model. But the chain has **zero** at every
link today: 0 inquiries, 0 matches, 0 quotes, 0 reveals. Any AED figure attributed to this seat in year one
would be invented.

**Metrics it owns:**
1. **Supplier scoring coverage** — 0.01% vs 95, and **not achievable as defined**; to be redefined as coverage
   among suppliers with history.
2. **New: categories at the liquidity floor** — categories with ≥ 10 approved suppliers. Baseline measured:
   **0 of 86**.
3. **New: capability corroboration rate** — capabilities that are confirmed or corroborated ÷ all.
   Baseline measured: **0 of 15,306**.

**Quarterly milestones.**
- **Q1.** Write the scoring model down as knowledge — inputs, the five weights and where they live, the null
  rule, the cold-start prior, the refresh cadence, and a worked example on the one approved supplier. Get
  `supplier_score` refreshing on a cadence again (last run 2026-08-16). Build the corroboration model S4 and
  start recording confirmations from the portal.
- **Q2.** S7 liquidity and concentration published weekly to `supply`, ranked by demand × gap. Add the
  cold-start prior and interval so a new supplier can be ranked at all.
- **Q3.** Once any quotes exist: price position S8 and the category spread — the number that proves price
  discovery. Fit the S2 weights against won/lost outcomes for the first time.
- **Q4.** Customer LTV and churn once more than one customer exists; circumvention-detection queries.

**Capacity check.** The modelling is arithmetic over tables that exist. The seat has **no workflows** and no
required inputs declared, which is a wiring problem `people_ops` and `intel_director` must fix before it can
be held to anything. The hard ceiling is that **six of its eight models divide by an empty table**, and the
seventh (S1) is only two rows deep.

**Dependencies.** `supply` to produce approved suppliers — the whole department's binding constraint;
`marketplace` for matches and quotes; `intel_director` to redefine the KPI; `knowledge_director` for the
scoring runbook's ingest route.

**Plainly: not achievable as currently defined, and the fix is a definition change, not effort.** What would
make it achievable is one category reaching 10 approved suppliers and producing quotes — at which point every
model here has an input and the seat becomes the most directly revenue-linked in the department.

### 9. What this seat cannot do without a model

- Reading a supplier's website or catalogue PDF and deciding what they actually do. Extraction of named
  entities against `mdm_brands` and `category_keyword` is deterministic; **judging capability from prose is
  not**, and this is precisely why all 15,306 capability rows are derived rather than confirmed.
- Deciding whether two company records are the same firm when names, licences and phones all differ slightly.
  Deterministic matching on licence number, domain and E.164 phone catches the easy cases and refuses the rest.
- Explaining *why* a supplier stopped responding. It can measure that they did.

---

## process_improvement_mgr — Process Improvement Manager

`org_role.role_id = process_improvement_manager` · authority `execute_low`, budget **AED 1,000** · manager
`intel_director` · owns *process defect diagnosis, improvement proposals with a named metric* · forbidden
*grading its own improvement, changing another department's method without its head* · outputs
`process_diagnosis`, `improvement_proposal` · required inputs `employee_task`, `rfq_handling` · escalates to
`chief_operating_officer`, `chief_of_staff`. Authority: `capability_exam` and `qa_gate` autonomous;
`knowledge_fill`, `knowledge_acquire`, `knowledge_fill_gap` advisory at a AED 1,000 threshold.
Its knowledge scope is the only one in the department that includes `customer_success`, `hr`, `knowledge` and
`people_ops` and **excludes** `analytics`, `data_intel` and `intelligence`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| 1 | Where is the cycle time in this workflow actually going? | diagnosis | per workflow, monthly | ops_director, department heads | effort goes to the fastest step |
| 2 | Which step is the bottleneck? | diagnosis | monthly | ops_director | the queue moves from one place to another and nothing improves |
| 3 | Is this a special cause or a common cause? | diagnosis | per excursion | own seat | a one-off is met with a process change; a systemic fault is met with a nudge |
| 4 | Is this handoff being accepted? | gate | continuously | ops_director | `phase_d_handoff_acceptance` has 0 rows against 159 contracts; work stalls invisibly between desks |
| 5 | Which step has no owner? | gate | monthly | people_ops, ops_director | a step nobody owns is a step nobody does |
| 6 | Is this queue backing up? | diagnosis | daily | ops_director | `dispatch_max_open_per_dept` is 250; back-pressure hides a stall |
| 7 | Is a task recurring because the fix did not hold? | diagnosis | weekly | own seat | the same defect is re-opened forever |
| 8 | What is the rework rate on this process? | diagnosis | monthly | quality owners | rework is counted as throughput |
| 9 | Should this step be automated, simplified, or removed? | allocation | per diagnosis | department heads | automation is built for a step that should not exist |
| 10 | Is this improvement proposal's metric the right one? | gate | per proposal | intel_director | the process improves and the metric does not move, or vice versa |
| 11 | Did the improvement actually work? | gate | per improvement | ops_director | its own forbidden decision — it may not grade itself |
| 12 | Is this waste, or necessary work? | craft | per diagnosis | own seat | a control is removed and a risk lands |
| 13 | What is the WIP limit for this lane? | craft | quarterly | ops_director | `max_open_tasks` is 50 for most seats and 6 for two; nobody has checked either |
| 14 | Is this failure a process defect or a knowledge defect? | allocation | per failure | knowledge_director | a training answer is given to a plumbing problem |
| 15 | Which dead-letter entries share a root cause? | diagnosis | weekly | it | 141 dead-letter rows treated one at a time |
| 16 | Is this cron doing work or just running? | diagnosis | weekly | analytics, it | a green cron that writes nothing |
| 17 | Is this workflow step's gate correct? | gate | per step | department heads | a founder gate on a routine step, or no gate on a money step |
| 18 | Which department's queue is the constraint on the revenue loop? | sequencing | monthly | ceo, ops_director | the whole company optimises a non-constraint |
| 19 | Is this SLA achievable given the measured cycle time? | gate | per SLA | department heads | an SLA is set that the process cannot meet |
| 20 | Should this process be standardised or left to judgement? | craft | per process | department heads | judgement is removed where it was the value |
| 21 | Is this exception the process or an exception to it? | diagnosis | per exception | own seat | the exception path becomes the main path unnoticed |
| 22 | What is the escape rate of defects past the QA gate? | diagnosis | monthly | qa owners | the gate reads 100% and defects still ship |
| 23 | Is a control mode change safe to make? | escalation | rare | ops_director | 3,594 `control_mode_audit` rows; a wrong change loosens a guard |
| 24 | Which review chains are rubber stamps? | diagnosis | quarterly | ops_director, people_ops | 7,984 review-chain rows with almost no rejections is not review |
| 25 | Is this task lane routing to the right department? | gate | weekly | ops_director | tasks pile up on a desk that cannot act |
| 26 | Is the recurrence cooldown suppressing a real problem? | gate | monthly | own seat | `event_recur_cooldown_days` is 7; a weekly-recurring fault is silenced |
| 27 | Which step consumes the most agent runs for the least effect? | diagnosis | monthly | it, cfo | 40,373 agent runs; cost with no output |
| 28 | Is this improvement worth its cost? | allocation | per proposal | ops_director | AED 1,000 authority spent on a step that saves nothing |
| 29 | Has this process ever been measured end to end? | gate | per diagnosis | own seat | a diagnosis of a process with no timestamps |
| 30 | Should a step be split or merged? | craft | per diagnosis | department heads | a merge collapses a handoff and the acceptance signal is lost |
| 31 | Is the QA gate measuring the right thing? | gate | quarterly | own seat | its own KPI reads 100% while defects reach production |
| 32 | Which error class is growing? | diagnosis | weekly | it | 937 error events; the growing class is the one to fix |
| 33 | Is a workflow's actor role resolvable to a live agent? | gate | monthly | people_ops | a step assigned to a parked seat never runs |

### 2. Domain logic

**P1 — Cycle time and its distribution.** Per workflow step:
`cycle_time = completed_at − started_at`; report **median and p90**, never the mean — a mean over a long-tailed
queue is misleading, and the estate's queues are long-tailed by construction.
Inputs: `workflow_step_run` (27,117), `workflow_run` (1,734), `org_tasks` (2,466),
`phase_c_workflow_step_run` (145), `phase_c_system_execution` (54,495), `phase_c_trace` (53,703),
`agent_runs` (40,373), `event_delivery` (4,202), `review_queue` (1,392).
**Available today.** This is the one model in this department with a genuinely large, populated input.

**P2 — Bottleneck identification (Theory of Constraints, arithmetic form).**
For each step, `utilisation = arrival_rate / service_rate` and `queue_length` from the open items in the lane.
The constraint is the step with the highest `utilisation` where downstream steps are starved.
Inputs: `workflow_step` (187), `workflow_step_run`, `org_tasks` by lane and status,
`dispatch_max_open_per_dept` (250), `max_open_tasks` per seat.
**Available today** for the internal workflows; not for the RFQ process, which has never run.

**P3 — Special vs common cause (control chart).** `UCL/LCL = mean ± 3σ` over the trailing k runs of the same
step; a point outside the limits, or 7 consecutive points on one side of the mean, is a special cause.
Inputs: `workflow_step_run` durations, `health_checks` (5,790), `edge_health_probe` (60,331).
**Available today.**

**P4 — Handoff acceptance.** `accepted = exists a step_run opened by the receiving actor after the handoff
event`. An unaccepted handoff older than its SLA is a stall.
Inputs: `phase_d_handoff_contract` (159), `phase_d_handoff_acceptance` (**0 rows**),
`phase_c_handoff_binding` (134), `phase_c_handoff_run` (7), `phase_b_handoff` (134),
`v_handoff_stalled`, `v_handoff_without_contract`.
**Measured today:** 159 handoff contracts and **0 acceptance rows**. Either no handoff has been accepted, or
acceptance is not being recorded. Distinguishing those two is exactly this seat's job and is its first
concrete piece of work.

**P5 — Rework and recurrence.**
`rework_rate = tasks reopened or superseded ÷ tasks closed`;
`recurrence = distinct (department, title) pairs closed and re-minted within `event_recur_cooldown_days` × 4`.
Inputs: `org_tasks`, `event_rollup` (2,197), `event_assessment` (3,095), `agent_remediation` (32),
`os_incidents` (57), `dead_letter` (141), `error_events` (937).

**P6 — Waste classification (Lean, as a lookup).** Map each observed delay to one of the eight wastes —
waiting, over-processing, defects, motion, inventory (queue depth), over-production, transport (handoffs),
unused talent — by a stored rule per evidence type: a gap between `completed_at` and the next `started_at` is
waiting; a re-open is a defect; a queue above its WIP limit is inventory; a handoff with no acceptance is
transport.
**This is a classification table, not a judgement**, and it does not exist today.

**P7 — Improvement value.** `value = (baseline_cycle_time − projected) × frequency × cost_per_hour`, against
the build cost; the proposal must name **one** metric that will move and the direction.
Inputs: P1 baseline, `ai_cost_log` (3,787) and `ai_spend_probe` (12,711) for cost, the seat's AED 1,000
authority as the ceiling on what it may spend alone.

**P8 — Gate escape rate.** `escape = defects found after the gate ÷ (defects found at the gate + after)`.
Inputs: `qa_results` (288), `os_incidents` (57), `error_events`, `dead_letter`, `red_episode` (57),
`challenge_record` (63), `vt_results` (52).
**Measured today:** this seat's KPI reads **100.00%** gate pass rate against a 95% target from
`qa_results where run_at > now() − interval '7 days'`. A 100% pass rate with a non-zero escape rate means the
gate is not gating. The escape rate is **not currently computed anywhere**, so the KPI is met and unfalsified.

### 3. Reasoning procedures

**Type 1 — "Where is the cycle time going?"**
1. Select the workflow and its steps from `workflow_step` (187 rows) and `org_workflow_step` (27).
2. Pull every run from `workflow_step_run` in the window.
3. Compute P1 per step: n, median, p90, and the share of total elapsed time.
4. Rank steps by share of total.
5. Split each step's time into **work** (actor active) and **wait** (between completion of the predecessor and
   start of this step) using the adjacent runs' timestamps.
6. Compose a `process_diagnosis`: the step with the largest wait share, the step with the largest work share,
   and n for each. Cite the run ids.
7. **Stop:** any step with fewer than a stored `n_min` runs is reported as "not enough runs to characterise",
   never as fast.

**Type 4 — "Is this handoff being accepted?"**
1. List the 159 `phase_d_handoff_contract` rows.
2. For each, look for an acceptance row (0 exist) **and** for the behavioural equivalent — a step run opened
   by the receiving actor after the handoff event.
3. If behavioural acceptance exists but no acceptance row does → **an instrument defect**: acceptance is
   happening and not being recorded.
4. If neither exists → **a process stall**: the work is sitting between two desks.
5. Report the split. These are different problems with different owners and the estate currently cannot tell
   them apart.

**Type 3 — "Special or common cause?"**
1. Build the control chart from the trailing k runs (P3).
2. A single point outside 3σ → special cause: investigate that run, do not change the process.
3. A run of 7 on one side, or a widening spread → common cause: the process is the problem.
4. **Never** respond to a single excursion with a process change. That is the classic over-correction and it
   makes variance worse.

**Type 11 — "Did the improvement work?"**
1. Take the pre-registered metric and baseline from the `improvement_proposal`.
2. Measure the same metric over an equal post window.
3. Apply P3 to ask whether the change is outside the pre-change control limits.
4. **Hand the result to `chief_operating_officer` for the verdict.** This seat may not grade its own
   improvement — its explicit forbidden decision. It produces the measurement; someone else calls it.

**Type 18 — "Which queue is the constraint on the revenue loop?"**
1. Enumerate the revenue-loop steps end to end: lead → invite → registration → approval → category liquidity →
   inquiry → match → quote → comparison → reveal → payment.
2. For each, count the population at that stage and the transition rate to the next.
3. The constraint is the first stage where the population is large and the transition rate is ~0.
   **Worked today:** 22,265 leads → 171 invited (0.8%) → **0 registered through the invite path** →
   1 approved supplier by another route → 0 of 86 categories at the 10-supplier floor → 0 inquiries →
   0 matches → 0 quotes → 0 reveals.
   **The constraint is the invite→registration transition**, and it is not in this department. Every
   downstream stage is starved, not slow. This seat's most valuable single output in year one is to say that
   clearly and keep saying it until the transition moves.

**Type 24 — "Which review chains are rubber stamps?"**
1. Per reviewer, compute `rejection_rate = request_revision ÷ decided` from `review_chain` (7,984 rows).
2. A reviewer with a large `decided` count and a rejection rate at or near zero is a rubber stamp.
3. Cross with the author: a reviewer who is also the author on any row is a self-review defect.
4. Report to `people_ops` and `ops_director`. **This seat diagnoses; it does not change another department's
   method without its head.**

### 4. Judgement rules

- **PJ-1.** Never respond to a single excursion with a process change. Establish common cause first.
- **PJ-2.** A step with fewer than `n_min` runs is uncharacterised, not fast.
- **PJ-3.** Report median and p90, never the mean, for any cycle time.
- **PJ-4.** Never grade your own improvement. *Explicit forbidden decision.*
- **PJ-5.** Never change another department's method without its head. *Explicit forbidden decision.*
- **PJ-6.** Do not remove a control to reduce cycle time. A control removed is a risk accepted, and accepting
  risk is not this seat's decision.
- **PJ-7.** Do not optimise a non-constraint. **Even when a non-constraint step is the easiest, most
  measurable win.** This is this seat's "do not do it even though it scores well" rule, and today it is
  load-bearing: every internal workflow this seat can measure is downstream of a transition that is at zero.
- **PJ-8.** An improvement proposal names exactly one metric and its direction before the change, and the
  measurement window is fixed before the change.
- **PJ-9.** A green cron that writes nothing is a defect, not a success.
- **PJ-10.** A 100% gate pass rate with an unmeasured escape rate is not evidence the gate works.
- **PJ-11.** A merge that collapses a handoff loses the acceptance signal; propose merges only where the
  handoff has never carried information.
- **PJ-12.** Escalate to `chief_operating_officer` when the constraint sits in another department, when a
  change would touch a money or safety gate, or when the improvement's cost exceeds AED 1,000.
- **PJ-13.** A process with no timestamps cannot be diagnosed. Instrument it first and say so.

### 5. Technical knowledge

- **The kernel's process model:** `workflow` / `workflow_step` (187) / `workflow_run` (1,734) /
  `workflow_step_run` (27,117); `org_workflow_ownership` (30), `org_workflow_step` (27),
  `employee_workflow` (112); `phase_b_workflow` (30) / `phase_b_workflow_step` (257) / `phase_b_handoff` (134);
  `phase_c_step_binding` (257), `phase_c_handoff_binding` (134), `phase_c_workflow_run` (139);
  `phase_d_handler_binding` (257), `phase_d_handoff_contract` (159), `phase_d_step_effect` (257),
  `phase_d_handoff_acceptance` (**0**); `fn_task_class` (71), `org_tasks` lanes, `decision_trace` (1,735).
- **The signals of a stalled process:** `dead_letter` (141), `error_events` (937), `os_incidents` (57),
  `review_queue` (1,392), `review_chain` (7,984), `event_delivery` (4,202), `event_rollup` (2,197),
  `agent_remediation` (32), `control_mode_audit` (3,594), `autonomy_control_audit` (3,885),
  `os_audit_log` (27,336).
- **The throttles it must know before proposing a change:** `dispatch_max_batch` 500,
  `dispatch_max_open_per_dept` 250, `event_recur_cooldown_days` 7, `cos_reflection_tasks_per_day` 500,
  `workflow_reflection_steps_per_day` 2,000, `org_agents.max_open_tasks` (50 for most seats).
- **The QA surface it is measured on:** `qa_results` (288), `fn_quality_metrics()`, `fn_eval_snapshot(days)`,
  `critical_capability` (16), `v_critical_capability_tests`, `red_episode` (57), `challenge_record` (63),
  `vt_results` (52), `scenario_library` (32), `phase_d_step_case_result` (1,799).
- **DMAIC as a stored template:** Define (the defect and its metric), Measure (P1/P3 baseline), Analyse
  (P2/P6), Improve (the proposal with one named metric), Control (the post-window measurement and who grades
  it). Each phase's outputs are named tables, not documents.
- **The estate's own process history:** `institutional_memory` (2,097), `os_runbooks` (181),
  `spec_backlog` (193), `continuity_plan` (13), `evolution_proposal` (98), `outcome_record` (134).

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Statistical process control | Control charts, run rules, capability indices, common vs special cause | NIST/SEMATECH e-Handbook chapter 6 (public domain) — the single best-fitting open source for this seat |
| Six Sigma / DMAIC | Define-Measure-Analyse-Improve-Control; measurement system analysis | ASQ published body-of-knowledge outlines (open); the standard texts are copyrighted and are **not** ingested |
| Lean | The eight wastes, value-stream mapping, flow and pull, takt time, WIP limits | Open Lean primers with a permissive licence; an authored summary mapping the wastes to this estate's queues |
| Theory of Constraints | Identify–exploit–subordinate–elevate; drum-buffer-rope | Published open summaries; the arithmetic in P2 is the whole of what is needed |
| Queueing theory | Little's Law (`WIP = throughput × cycle time`), utilisation vs wait, M/M/1 intuition | Open operations-research course material and NIST e-Handbook |
| Reliability engineering | MTBF, MTTR, failure classification | NIST e-Handbook chapter 8 |
| Project management | Scheduling, dependency management, change control | PMI's published PMBOK outline and process groups (the standard itself is paid; the outline is public) |
| Measurement system analysis | Gauge repeatability — does the instrument measure the process or the instrument? | NIST e-Handbook chapter 2 |

**Certifications this seat holds:**

| rank | certification | body | pass mark | syllabus areas |
|---|---|---|---|---|
| 1 | CSSBB (Six Sigma Black Belt) | ASQ | 73% | Organization-wide Planning and Deployment · Team Management · Define · Measure · Analyze · Improve · Control · Design for Six Sigma |
| 2 | PMP (Project Management Professional) | PMI | 61% | People · Process · Business Environment · Predictive Plan-Based Methodologies · Agile and Hybrid Approaches |

**Syllabus areas it failed: does not exist** — no `certification_exam_result` row. The lexical exam measured
**11 correct of 30 (36.7%)**, 8 wrong, 4 partial, 7 not covered, confidence 0.46, and **11 answers filled**,
last sat 2026-09-07 03:23 UTC. The 6 Sep audit's keyword census of this seat's reachable knowledge found
**"Six Sigma" 0 mentions** — the seat holds a Black Belt certification and none of the methodology behind it.
Every CSSBB area maps onto a model in §2: Measure → P1/P3, Analyse → P2/P6, Improve → P7, Control → P8.

### 7. Corporate knowledge

- **Its own KPI:** *"Process Improvement Manager — primary objective"*, metric *Quality gate pass rate before
  ship*, target 95%, **actual 100.00%** measured 2026-09-07 03:30 UTC over 7 days of `qa_results`. It is met.
  It is also, by PJ-10, not evidence of anything until the escape rate is measured — and the seat should say
  so rather than bank the green.
- **Its authority is real but small:** `execute_low` with AED 1,000; `qa_gate` and `capability_exam` run
  autonomously. Anything above AED 1,000 or touching another department's method goes to the COO.
- **Its knowledge scope excludes its own department's analytics records.** `fn_dept_scope` for this seat's
  scopes covers `customer_success`, `engineering`, `operations`, `procurement`, `hr`, `knowledge`,
  `people_ops` and the company layers — but **not** `analytics`, `data_intel` or `intelligence`. It therefore
  cannot reach the 101 deep records its own department holds, including the ones on measurement design. That
  is a scope defect for `knowledge_director` to fix.
- **The founder's operating doctrine it must apply:** roughly 95% deterministic code and 5% model; nothing
  routes to the founder except Stripe refunds; phase freezes are lifted; mirror gates are retired —
  production proves properties and a CSV never greens a check; never weaken a check to make a gate pass;
  if a real fix makes a headline fall, say so.
- **The lesson corpus** the estate has accumulated about its own process failures — guarded by a condition
  that cannot occur; a condition that cannot *not* fire; a guard that fires when the system works; an
  instrument measuring the wrong subject; a finished capability with no entry point; a harness that seeds an
  order reality cannot produce — lives in `institutional_memory` (2,097 rows) and the repo's session lessons.
  **This is the richest process-defect corpus in the company and it is not in this seat's reachable scope.**
- **Does not exist:** a waste-classification table; a DMAIC template as a stored artefact; cycle-time targets
  for any workflow; a gate escape-rate measurement; a WIP-limit review; any `improvement_proposal` artefact
  in the estate.

### 8. One-year plan

**Objective.** Name the constraint on the revenue loop every month, with arithmetic, and remove the process
defects that sit inside this company's own control.

**Slice of the AED 1,000,000: AED 0 directly, and one honest claim.** This seat cannot generate revenue. What
it can do is stop the company optimising the wrong thing — and measured today, **every workflow it can improve
is downstream of a transition sitting at zero.** Its year-one value is diagnostic clarity, and it should be
judged on that.

**Metrics it owns:**
1. **Quality gate pass rate** — 100.00% vs 95 (met, and uninformative until #2 exists).
2. **New: gate escape rate** — defects found after the gate ÷ all defects found. Baseline: does not exist.
3. **New: handoff acceptance rate** — accepted handoffs ÷ handoffs due. Baseline measured: **0 acceptance rows
   against 159 contracts**, cause unknown.
4. **New: median and p90 cycle time per revenue-loop step** — baseline computable today from 27,117
   `workflow_step_run` rows for internal steps; **undefined for every RFQ step**, which has never run.

**Quarterly milestones.**
- **Q1.** Resolve the handoff-acceptance question: instrument defect or real stall (P4). Build the P1 cycle-time
  baseline across all 187 workflow steps. Publish the first end-to-end revenue-loop constraint report
  (Type 18) and repeat it monthly without variation. Get `analytics`, `data_intel` and `intelligence` into
  this seat's knowledge scope.
- **Q2.** Gate escape rate (P8) so its own KPI becomes falsifiable. Waste-classification table (P6) and the
  DMAIC template as stored artefacts. Rubber-stamp review analysis (Type 24) handed to `people_ops`.
- **Q3.** WIP-limit review across the lanes; dead-letter and error-class clustering (P5) with the top three
  root causes fixed by their owners.
- **Q4.** Cycle-time targets per workflow, set from the measured p90 rather than from ambition; first
  improvement measured and graded **by the COO**, not by this seat.

**Capacity check.** P1, P2, P3, P5 and P8 are all computable today from tables with tens of thousands of rows
— this is the only seat in the department whose primary models have full inputs. `max_open_tasks` 50 against
9 deterministic runs a week is ample. **Achievable.**

**Dependencies.** `chief_operating_officer` grades every improvement (this seat may not).
`knowledge_director` for the scope fix that would let it reach its own department's records.
Department heads for any change to their methods. `it` for the cron and dead-letter fabric.

**Plainly: this seat's year-one slice is achievable and it is worth more than it looks**, because the single
most useful sentence the company can hear each month — *"the constraint is still invite→registration, here is
the arithmetic"* — is this seat's to produce, and nobody else's.

### 9. What this seat cannot do without a model

- Writing the improvement proposal's narrative for a department head who has not read the arithmetic. The
  diagnosis is deterministic; the persuasion is not.
- Recognising a process defect that leaves no timestamp — a step that is skipped without being recorded as
  skipped. It can only see what the fabric writes.
- Classifying a delay into one of the eight wastes when the evidence type is not in the stored rule table.
  New evidence types need a human to place them once.

---

## Department summary for the founder

**What this department is.** Seven seats whose whole function is to tell the company the truth about itself.
Measured on 7 September 2026, the truth is: **the instruments are mostly built and mostly reading zero,
because the business they measure has not started.** 0 inquiries, 0 quotes, 0 transactions, 0 matches,
0 reviews, 1 customer, 1 approved supplier, 0 of 86 categories at the 10-supplier floor.

**What each seat can honestly deliver in year one**

| Seat | Year-one slice of AED 1,000,000 | Achievable? |
|---|---|---|
| intel_director | AED 0 direct. Owns whether the AED 1M path is arithmetic or belief | Instrumentation half: yes. Revenue half: not until one demand loop exists |
| knowledge_director | AED 0 direct. Makes the other six trustworthy | Yes, and it is not on the revenue path this year |
| analytics | AED 0 direct. Makes the first real revenue number correct on day one | Yes — the highest-leverage non-revenue work in the department |
| bi_analyst | AED 0 direct | Honesty half yes; analysis half no, until a metric carries a dimension and a rate carries 30 observations |
| market_analyst | AED 0 direct; one measurable causal contribution through category selection | Source registry yes; demand index capped by what can be lawfully read with Apify paused |
| supplier_analyst | AED 0 today; the clearest causal path of the seven once demand starts | **Not achievable as its KPI is currently defined** — the fix is a definition change, not effort |
| process_improvement_mgr | AED 0 direct | Yes, and it owns the single most useful monthly sentence: where the constraint is |

**Sum: AED 0 of the AED 1,000,000 is attributable to this department in year one, and any figure that claimed
otherwise would be invented.** The department's slice is the *quality* of the number, not the number.

**The six things in this department that are wrong and are ours to fix**

1. `intel_director`'s KPI *"Categories with all eight knowledge modules"* compares a **count of failures**
   (2) against a **percentage target** (100). True coverage is 84 of 86. An instrument measuring the wrong
   subject, in the department that owns instruments.
2. `supplier_analyst`'s KPI *"Supplier scoring coverage"* (0.01% vs 95) can only be met by writing scores the
   evidence does not support. It must be redefined as coverage among suppliers with history.
3. `market_analyst`'s KPI *"Market signals captured"* (0 vs 20) has a table that has never held a row and no
   writer. It is the one zero in this department that is genuinely this department's to fix.
4. `fn_experiment_conclude` will crown a winner with **no significance test at all**, on arms as small as the
   stored floor. Two experiments have been "running" since 2026-07-06 with 1 assignment and 0 events between
   them. Both should be stopped as never-instrumented, not concluded.
5. **0 of 9,140 `ops_knowledge` rows are validated**, including the 101 deep records that are this
   department's best asset — and the exam that is supposed to test knowledge has written **56 of the seven
   seats' 225 answers back into their own `agent_knowledge`** (analytics 6, bi_analyst 3, intel_director 8,
   knowledge_director 9, market_analyst 7, process_improvement_mgr 11, supplier_analyst 12), many from wrong
   verdicts. The seats scored **65 correct of 225 (28.9%)**, last sat 2026-09-07 03:23 UTC.
6. `phase_d_handoff_acceptance` has **0 rows against 159 handoff contracts**. Either nothing is being accepted
   or acceptance is not recorded, and the estate cannot currently tell which.

**The one thing that is not ours.** Every other zero in this document is downstream of a single transition:
**171 suppliers invited, 0 registered through that path, 1 approved by another route.** Until that moves, this
department can build correct meters and cannot make them read.
