# V3 REMEDIATION — STAGE 8: REVENUE OBJECTIVE AND KPI CASCADE

**Scope:** `scripts/sql/v3_repair_08_revenue_cascade.sql`. Every figure below comes from a query run
against staging `pglpqrhvozwepymcuunn` on 14 Aug 2026 or a file read on this branch.

**Nothing here is certified.** Internal work certifies no role, department or category. The result of
record is `V3-COR-0A782DA90B10` at 56.97%, with 0 of 96 roles, 0 of 24 departments and 0 of 86
categories certified; only an independent evaluator can change that.

---

## 1. The company objective, as it actually sits in the database

`select * from company_goals where key='revenue_annual'` returns one active row:

| field | value |
|---|---|
| goal | Reach AED 1,000,000 annual revenue |
| metric | Recognised revenue in trailing 12 months |
| target_value / unit | 1000000 / AED |
| period / horizon / direction | annual / year_1 / at_least |
| owner_dept | finance |
| deadline | **2027-08-31** |
| measure_sql | `sum(coalesce(t.reveal_fee, t.app_fee, 0)) from transactions t where t.revealed_at > now() - interval '365 days' and t.refund_confirmed_at is null` |

The `deadline` column did not exist before this stage. It was set from wording already carried
verbatim in `org_departments.north_star` (exec and growth both say 31 August 2027), not invented.

`select fn_revenue_trajectory()` executes that measure live and returns:

```
actual_value 0 · gap_to_target 1000000 · days_remaining 382
required_per_month 79685.86 · required_per_day 2617.80 · deadline_passed false
```

That is the number every department objective now has to reconcile to.

---

## 2. The chain, run end to end

**Defect.** Before this file ran, `department_objective` held 66 active rows: 37 carried a
`goal_key`, **0 carried a target_value, 0 carried a measure_sql, 0 were measured**. Every department
objective was a sentence. An agent asked to link a decision to its department objective could only
restate prose, because there was no number underneath it.

**Mechanism.** `fn_goal_decompose()` — the routine that hands a company goal's target and measure
down to the owning department — already existed and had never been called. Finished capability, no
entry point.

**Fix.** `fn_cascade_refresh()` gives it one and then runs the two measurement sweeps.

**Evidence, measured now:** 91 active department objectives, 62 with a `goal_key`, 30 with a
`target_value`, 31 with a `measure_sql`, **27 measured**, 5 on `revenue_annual`, across 10 canonical
departments. From zero measured to 27. Re-running `fn_cascade_refresh()` in an aborted transaction
reports it would create 4 more and adopt 1, and that **32 company_goals still have no measure_sql at
all** — those cannot be handed down to anyone.

### Finance — the chain is complete

`fn_revenue_cascade('finance')`: 8 objectives, 7 linked to a goal, 4 on the revenue target, 4
measured; 9 role KPIs, 7 measured, 7 connected to the revenue target.

- Company objective → AED 1,000,000 by 2027-08-31, actual 0, AED 79,685.86/month required.
- Department objective → "Protect cash flow", `goal_key=revenue_annual`, target 1000000 AED,
  actual 0, attainment 0.0%.
- Role KPI → `cfo` / "Revenue against plan", class **revenue**, target 1000000, actual 0, 0.0%.
- Task expected effect → `fn_task_commercial_effect` (§4).
- Management response → `v_commercial_effect_due` + `fn_binding_constraint`.

### Customer Success — the chain stops at the department

`fn_revenue_cascade('customer_success')`: 7 objectives, 6 linked, **0 on the revenue target**, 2
measured; 8 role KPIs, 6 measured, **0 connected to the revenue target**. Every objective reconciles
to `customer_satisfaction`, `customers_registered` or `customers_active` — best measured being
"5,000 registered customers" at 20 (0.4%) and "1,500 monthly active customers" at 4 (0.3%). Nothing
in this department's model says how a registered customer becomes AED. It is the lowest-scoring
department in the certification (8.38%) and its cascade stops one level short of money: a structural
fact, not a prompt problem.

### QA & Testing — reconciles upward, never to revenue

`fn_revenue_cascade('qa_testing')`: 10 objectives, 9 linked, **0 on the revenue target**, 4
measured; 6 role KPIs, 3 measured, **0 on revenue**. It carries useful numbers — uptime target 99.95
measured at 80.00, AI availability 99.95 at 93.93, API response target 400ms at 1325ms — and none
resolves to a commercial consequence.

---

## 3. Coverage, including the bad news

`v_revenue_cascade_coverage`, one row per certification department, resolved through
`org_department_alias`:

| reconciliation_status | packaged (of 24) | canonical (of 10) |
|---|---|---|
| reconciled_and_measurable | 15 | 6 |
| reconciled_not_measurable | 5 | 2 |
| objectives_but_none_linked_to_a_company_goal | 4 | 2 |
| no_objective_at_all | **0** | **0** |

**Reaching the revenue target: 13 of 24 packaged, 6 of 10 canonical.** Only **4 packaged / 2
canonical** departments own an objective whose `goal_key` is `revenue_annual` — exec (1) and finance
(4). The other 11 packaged departments reach revenue only through a role KPI, or not at all.

Role KPIs: **122 active, 77 measured (63%), 93 name a company goal, 37 name `revenue_annual`, and 0
carry a declared `kpi_class`** — every class below is inferred.

A caveat the numbers hide: 24 packaged departments map onto 10 canonical `dept_key`s, so
`marketplace` alone answers for five of them and its 24 objectives are counted five times in the
packaged column. Read the canonical column for the real spread.

---

## 4. Activity versus business result — `fn_metric_class`

`fn_metric_class(label, metric, unit)` is deterministic and keyword-based, and returns
`unclassified` rather than guessing. Run over all 122 active KPIs:

| class | n | example (verbatim) |
|---|---|---|
| quality_metric | 36 | "Accountant — primary objective" |
| **unclassified** | **35** | "Categories at the 10-supplier target" |
| leading_indicator | 29 | "Alerts raised that reach the founder" |
| activity | 9 | "Reveal invoices without a payment record" |
| risk | 8 | "Contact-detail leakage in anonymous quotes" |
| cost | 2 | "Cost per reasoning call" (metric: AED per agent_reasoning call) |
| conversion | 2 | "Invite to approval conversion" |
| **revenue** | **1** | "Revenue against plan" |

That is the honest picture of the activity-vs-business-result distinction: **one KPI in 122 is a
revenue metric.** Five (revenue + conversion + cost) are commercial. Forty-four (activity +
unclassified) are not stated as business results at all.

The classifier is wrong on real rows, systematically:

- "Agent run reliability" (metric *"Scheduled agent runs completing without error"*) → `activity`;
  `runs` fires the count branch before `reliability` reaches quality. It is a quality metric.
- "Reveal invoices without a payment record" (metric *"count"*) → `activity`. It is a risk count.
- "Suppliers gone quiet" (metric *"approved suppliers with no response in 60 days"*) → `activity`.
  It is a leading indicator.
- "Categories with a viable pool" → `conversion`, only because its metric text contains "5%
  conversion". It is coverage.
- "Dues recovered" (metric *"Overdue supplier dues recovered within 30 days"*) → `unclassified`,
  despite being the clearest cash-collection KPI in finance.

`employee_kpi.kpi_class` is a declared override and readers prefer declared over inferred, so each is
a one-row fix. Nobody has set one. **0 of 122.**

---

## 5. Unmeasured must not score as satisfied — probed, not assumed

This repo shipped `least(100, NULL) = 100`, which scored 56 unmeasured goals as perfect and put 97.7%
attainment in the founder's email on a zero-revenue day. `select least(100, null::numeric)` still
returns **100** here. The question is whether the new code can reach that shape.

**Source check.** Of the nine cascade functions, `fn_metric_class`, `fn_revenue_trajectory`,
`fn_revenue_cascade`, `fn_cascade_refresh`, `fn_task_commercial_effect`, `fn_goal_decompose`,
`fn_dept_objective_measure` and `fn_employee_kpi_measure` contain **no `least()` and no
`greatest()`** (`pg_proc.prosrc ~* '\mleast\s*\('`).

**Behaviour check — aborted-transaction probe.** Seeded one department objective and one role KPI in
finance with `target_value` set and no measurement at all, called `fn_revenue_cascade('finance')`,
then raised to roll back:

```
OBJECTIVE  measured=false  attainment=<null>  reason="no measure_sql recorded for this objective"
KPI        measured=false  attainment=<null>  class=unclassified
COUNTS     objectives 8→9, objectives_measured 4 (unchanged)
           role_kpis  9→10, role_kpis_measured 7 (unchanged)
```

Adding an unmeasured item raises the denominator and never the numerator. There is no composite score
anywhere in `fn_revenue_cascade` — it returns counts, deliberately.

**Trajectory probe.** With `revenue_annual.measure_sql` nulled inside an aborted transaction,
`fn_revenue_trajectory()` returned `measured=false, actual_value=null, gap_to_target=null,
required_per_month=null`, carrying the reason rather than a comfortable number.

**One `greatest()` remains, and it is a real defect.** `fn_binding_constraint` computes its window as
`greatest(p_days, 1)`. `greatest(NULL, 1) = 1`. Measured:

| call | first-stage denominator | reported `window_days` |
|---|---|---|
| `fn_binding_constraint(90)` | 11 | 90 |
| `fn_binding_constraint(1)` | 0 | 1 |
| `fn_binding_constraint(null)` | **0** | **null** |

A null argument silently computes a one-day window and labels it `null`: an instrument reporting on a
subject other than the one it names. It does not fabricate attainment — zero denominators report
`no_demand`, not 0%. The tool schema constrains `p_days` to ≥1 and the SQL default is 90, so this
only fires on an explicit null. **Not fixed in this stage.**

**Neighbouring instruments, checked because they sit on the same path:** `fn_goal_attainment` guards
`when actual_value is null then null` *before* its `least()`, and separates `goals_measured` from
`goals_total`. `fn_kpi_scoreboard` scores **0 of 45** unmeasured KPIs; forcing its `percent_max`
branch with a null actual in an aborted probe returned `attainment=null, verdict='NO DATA'`. Both are
safe. **49 public functions still contain `least()`. I checked four. The other 45 are unverified.**

---

## 6. Binding constraint and task expected effect

`fn_binding_constraint(90)`, measured live:

| stage | denominator | numerator | pass-through | state |
|---|---|---|---|---|
| visitors_to_registration | — | — | — | **not_instrumented** |
| registration_to_inquiry | 20 | 11 | 55.0% | measured |
| inquiry_to_quote | 11 | 8 | 72.7% | measured |
| **quote_to_paid_reveal** | 8 | 1 | **12.5%** | measured |

Binding stage: `quote_to_paid_reveal` at 12.5%, over 3 ranked stages with 1 excluded and named.
Confirmed suppliers: 50. The excluded stage carries its reason rather than a zero — an unmeasured
stage could easily be the real constraint and must not be silently ruled out.

`task_commercial_effect` closes the loop. A check constraint allows exactly two shapes: a complete
claim, or an explicit opt-out with a reason. Probed end to end and rolled back:

```
partial claim        → ok=false, error=incomplete
complete claim       → ok=true, recorded=commercial_claim
opt-out              → ok=true, recorded=no_commercial_effect
v_commercial_effect_due (overdue, unmeasured)  → 1 row
after measured_outcome_value + management_response → 0 rows
```

**The bad news: `task_commercial_effect` holds 0 rows against 786 `org_tasks`.** The last two links
of the chain — expected effect and management response — are deployed and empty. `agent_tool_call`
shows `record_commercial_effect` has been called **0 times**.

---

## 7. Entry points, and why 14.76% is a model-behaviour gap

Three tools are registered and active in `agent_tool`: `revenue_cascade` (rpc → `fn_revenue_cascade`,
read, `degrade_with_caveat`), `binding_constraint`, and `record_commercial_effect` (write,
`fail_closed`). `fn_agent_tools` offers all three to every agent sampled (cfo, qa_manager, followup,
marketing, cs_support — 9 tools each), and they genuinely execute: `agent_tool_call` records
`revenue_cascade` run twice by `cfo` (ok, 6,419 and 10,302 result bytes, 339 and 572 ms) and
`binding_constraint` three times by `bi_analyst` and `qa_manager` (ok, 2,046 bytes, 227–280 ms).

That is the schema half. It does not move CMP-BZ-01 on its own, and here is the measurement showing
why. `fn_agent_context_v3('cs_support', …)` does carry `revenue_annual` in its `company_objective`
block — but only `target: 1000000`. **No actual, no gap, no days remaining.** The agent is shown a
target, not a position, and a target with no gap is not something a local decision can be linked to.
`fn_revenue_trajectory` carries the gap; the context assembler does not call it.

That block is also 1,757 characters of a 289,392-character assembled context — **0.6%**. The
`deterministic_rules` block is 235,328 characters, **81%**, and it is invariant to the budget:
identical at `budget_chars` 2,000, 12,000 and 60,000 (totals 281,771 / 286,474 / 330,046). The stated
budget does not govern the largest block in the context. That is the same defect the handoff records
as `KNOWLEDGE_NOT_RETRIEVED` on 1,706 questions, and it sits directly on top of the revenue linkage.

**What would actually move 14.76%,** in order:

1. Put the *gap* in the context, not the target: call `fn_revenue_trajectory()` from
   `fn_agent_context_v3` so every role sees "AED 0 of 1,000,000, 382 days, AED 79,686/month
   required".
2. Fix the `deterministic_rules` budget. While 81% of the context is unbudgeted boilerplate, no
   knowledge or objective change is testable.
3. Give Customer Success, QA & Testing, Legal and Trust & Safety an objective on `revenue_annual`,
   or a recorded statement that they serve it only indirectly. 8 of 10 canonical departments have
   neither.
4. Enforce the link in the answer contract, and set `kpi_class` on the 35 unclassified KPIs so
   "which metric does this move" has an answer.

## 8. Still broken or unverified

- `fn_binding_constraint(null)` computes a 1-day window and labels it `null`. Not fixed.
- `task_commercial_effect`: 0 rows, 0 tool calls. Schema only.
- 32 `company_goals` have no `measure_sql` and cannot be decomposed to anyone.
- 45 of 122 role KPIs are unmeasured; 29 measure attempts fail on each refresh.
- 35 of 122 KPIs classify as `unclassified`; several others classify wrongly. 0 declared overrides.
- 45 of 49 `least()`-using functions were not checked.
- **Stage 8 has no regression coverage.** `scripts/checks/v3_remediation_regression.mjs` contains two
  structural revenue checks (lines 215–223), one of which asserts `with_obj > 0` — it passes if one
  of ten departments has any objective — plus a regex on reply text (line 351). Nothing in that file
  calls `fn_revenue_cascade`, `fn_metric_class`, `fn_revenue_trajectory`, `fn_binding_constraint` or
  `fn_task_commercial_effect`. A repo-wide search for the three tool_ids across `.ts`, `.mjs` and
  `.sql` returns exactly one file: `scripts/sql/v3_repair_08_revenue_cascade.sql`.
- Measured on staging only. Not verified on production.
