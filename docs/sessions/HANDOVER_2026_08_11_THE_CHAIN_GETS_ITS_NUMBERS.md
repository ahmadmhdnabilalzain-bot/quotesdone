# HAND-OVER — 2026-08-11 evening · the chain got its numbers

Session ran 17:47 → 19:20 UTC (Dubai 21:47 → 23:20). Branch `fix/the-chain-gets-its-numbers`,
5 commits, PR [#199](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/199).

**This is an honest hand-over, not a completion.** Items 1–4 of the ordered work landed and are
verified by execution on both projects. Item 5 — the remaining 171 ABSENT — was not started.

---

## 1. THE BRIEF'S DIAGNOSIS WAS WRONG AGAIN, IN THE SAME DIRECTION

Sixth and seventh instances of the pattern. **Re-measure before building what a brief proposes.**

| the brief said | measured on production before building |
|---|---|
| "Employee KPIs are effectively ZERO" | `employee_kpi` **124 rows**, 123 active, 94 with `measure_sql`, 95 distinct employees, and **0 active employees without a KPI** |
| "`agent_expectations` = 121 cron job names, employee KPIs ~ zero" | true about `agent_expectations`, but it is not the employee KPI table. `employee_kpi` is, and it exists |
| "NO LINK — management cannot translate goals into departmental objectives" | `department_objective` **66 rows covering 25 of 25 active departments**, 38 carrying a `goal_key`, **0 orphans** |
| "put your KPI + goal into `fn_agent_context`" | `fn_agent_context` **already emitted** `# YOUR KPIs — this is how your work is measured`, with target, unit, cadence and *"serves company goal X"* |
| "`org_tasks.objective_id` is a writer that was never finished — backfill it" | it is **FK'd to `org_objectives`, which holds 0 rows** and is the founder's own objective intake (`raw_input`, `created_by` default `'founder'`). NULL on all 839 because he has never entered one. Backfilling it with OS objective ids would violate the FK |

There is also a **whole learning loop** the brief did not mention: `fn_kpi_scoreboard()` executes every
KPI's measure live, and `fn_kpi_review()` runs on cron Mondays 04:00 turning every MISSED KPI into an
`org_tasks` row **and** an `outcome_record` with a re-measure date.

### What was actually wrong — one defect, at two levels

**A level that cannot hold its own number.**

- `department_objective` had **no `target_value` and no `measure_sql` column at all** → 66
  departmental objectives, 0 of them measurable by construction.
- `employee_kpi` had **no `actual_value` and no `measured_at`** → the number `fn_kpi_scoreboard`
  computed was thrown away every time. Employees saw a target, never their number, and no employee
  in the company had a trend.

`os_objective` already had `actual_value` + `measured_at` on cron. That pattern was copied **down**
two levels rather than anything being rebuilt.

---

## 2. WHAT LANDED, WITH THE MEASUREMENT

| | before | after |
|---|---|---|
| `department_objective` measurable | **0 of 66** (no column existed) | column added; **20 measured, 0 failed** |
| `employee_kpi` storing its actual | none — computed then discarded | **74 measured, 20 failed** |
| `org_tasks` naming an employee | **0** (owner was prose inside `detail`) | **142 across 40 employees** |
| active employees with no responsibilities | 14 | **0 of 93** |
| measurable company goals | 8 of 63 | **20 of 63** |
| departmental objectives created by routine | — | **17 created, 4 adopted**, idempotent, on cron |
| exec's *"Reach AED 1M annual revenue"* | `goal_key = autonomous_decision_rate` | `revenue_annual` |
| `os_objective` #42 *"Every company goal carries a live actual value"* | 7.94% | **23.81%** |
| `goal_period` rows carrying an actual | — | 47 across 15 goals |

### The AED 1M target now reaches an individual employee

Verified inside the real context `ap_specialist` receives —
`fn_agent_context_capped('ap_specialist', 9000, …)` = 9,010 chars:

```
"# YOUR NUMBER RIGHT NOW"              at offset 5,402
"Reach AED 1,000,000 annual revenue"   at offset 5,872
"LAYER 4 (EXTERNAL)"                   at offset 6,250   — not evicted
```

and the chain traces: `revenue_annual` (1,000,000) → finance objective measured at 0 → 37 employee
KPIs, 29 measured → 62 tasks owned by named employees.

### A check got HARDER because its old pass was false

`os_objective` #44 *"Every KPI measurable and measured"* read **0** and now reads **29**. The 0 was
not a lie — it was measured at 03:20 and 29 KPIs with no `measure_sql` were created at 08:00, five
hours later. It is honest now, and it says the company has **29 employee KPIs nobody can measure**.

### A security defect I introduced and caught in the same turn

`anon` could execute `fn_employee_scorecard` on production. **`apply_sql.mjs --promote` promotes a
routine by posting `pg_get_functiondef()` read back from staging, and that emits the CREATE and
nothing else — no GRANT, no REVOKE.** So the revoke ran on staging and was silently absent on
production, where a new signature is a fresh CREATE that Postgres grants to PUBLIC. The three
routines applied with `--ddl` were correctly locked, which is the contrast that identified it.
Fixed with `--ddl`; anon-executable SECURITY DEFINER back to **56**, its documented baseline.

**This is a standing trap in the tooling, not a one-off.** Any new routine promoted with `--promote`
and not `--ddl` reaches production granted to PUBLIC.

### A scale trap caught by measuring rather than reading

`leads.rv_response_rate` is a **0..1 fraction** (max 1.000 over the 3 rows with reveals) and the goal
`supplier_response_rate` targets **85 percent**. Stored raw it would have reported 0.67 against 85 and
marked a healthy 67% response rate as a catastrophic miss. Multiplied by 100.

---

## 3. WHAT IS NOT DONE — named exactly

- **Item 5 of the prompt, the remaining 171 ABSENT: NOT STARTED.** OCR + Drawing Intelligence,
  inbound WhatsApp that can act (design is in the 11 Aug hand-over §7 — needs `EdgeRuntime.waitUntil`
  and `MessageSid` idempotency), vision routing, the 13 uncovered exception scenarios, the 5 missing
  workflows, `fn_edit_inquiry` leaving quotes live after a post-quote requirements change
  (spec #7 L1351), cost per OS, Maturity Index, delete-proposer, remaining spec #3 UI gaps.
- **`model_policy_by_identity` → `routing_tier` on `org_agents`: not started.** It was sequenced
  behind §1–§4 by decision and §1–§4 consumed the session.
- **43 of 63 company goals still carry no measure.** Split in
  `scripts/sql/twelve_of_the_fifty_five_decorative_goals_can_be_measured.sql` into *"no instrument
  exists in this database"* (24 — measuring them is not a SQL task) and *"the numerator and
  denominator are a business decision"* (19). None was given invented SQL: the measure routines trap
  errors, so a query that succeeds and lies is undetectable, which makes a wrong measure strictly
  worse than no measure.
- **29 employee KPIs have no `measure_sql`**, all created 2026-08-11 08:00 UTC by something I did not
  trace. `os_objective` #44 now reports them honestly. Worth finding what wrote them.
- **`department_objective` still has no `superseded_by` workflow in use**, and 46 of 66 departmental
  objectives have no measure — only the 20 the decomposition routine could derive from a company goal.

---

## 4. END-OF-SESSION SWEEP

| check | result |
|---|---|
| `fn_os_portals_gates()` production | **23 / 23 met** |
| `fn_os_portals_gates()` staging | **23 / 23 met** |
| `project_parity.mjs` | **BOTH PROJECTS IN SYNC** — 197 edge fns, 418 tables, 850 functions, 155 triggers, 0 tables without RLS, 56 anon-executable SECURITY DEFINER |
| Supabase advisors, production | **0 ERROR**, 448 INFO, 166 WARN |
| GitHub Actions | all checks green on PR #199 — typecheck app, typecheck edge functions, migration lint, classification/pricing/refund |
| Vercel | production **READY**. One preview failed on the documented `next/font/google` `space_grotesk` flake; the three preceding commits on the same branch produced READY previews and the failing commit changed one `.sql` file. Re-triggered. |
| Row #3 scorer | **125 / 152** — see below, this is a real regression of 1 and it is not yet explained |

### The Row #3 number is DOWN one, and the diff is NOT reconstructible — state of knowledge

Baseline was **126/152**; two full runs tonight both returned **125/152**, with 125 MET + 27 NOT MET
accounting for all 152. **I cannot tell you which check moved, and here is exactly why:** the
previous session recorded only the *total* (`Row #3 scorer 126/152`), never the per-check verdict
list, and this scorer reads live data. There is nothing to diff against. Guessing which of the 27
was previously MET would be inventing a fact.

**What I did check.** The one NOT MET check that is directly about what I built tonight is
`employee-performance-trend` — *"Performance is shown as a trend, not a point value"*. Read its
implementation at `scripts/staging/os2_blueprint/layers_1_8.mjs:364`: it requires **more than one
performance observation per active employee within 90 days, with distinct timestamps, in a source a
UI component actually reads**. `employee_kpi.actual_value` is overwritten on each run, so it is a
point value by construction and cannot satisfy this — and it almost certainly did not satisfy it
before tonight either, since no per-employee history has ever existed. **So this is probably not the
regression, but I did not prove that.**

I deliberately did not chase it further, for a reason worth recording: making that check pass needs a
history table appended on each measure, and after one run it would still hold exactly one
observation per employee. Manufacturing a second would be fabricating data to turn a gate green.
Adding the new table to the scorer's own `TREND_SRC` list so it counts would be weakening the check.
**Neither is acceptable, so the check stays red and honest.**

The full verdict list is at
`…\scratchpad\row3_full.txt` (198 lines) and is the first per-check record that exists. **Save the
next run's list**, then a real diff becomes possible for the first time.

**The genuine build order this exposes:** `employee_kpi` needs an append-only history so performance
becomes a trend rather than a point. That is required by the standard itself — "is monitored against
them, learns from outcomes and failures, improves its methods" is unobservable without history — and
it will pass the check legitimately on its second cron run, not its first.

**Pack scorecard was NOT re-run on either project, and the stated reason matters.** It requires
`--packs=<extracted packs dir>` — the six `QuotesDone_*_v2026.07.31.zip` files from `~/Downloads`
extracted to a directory — and that directory does not exist in this working tree. It fails fast with
`--ref and --packs are required`. Extract the six zips and run it on **both** refs; the last recorded
values are INGESTED 100%, IN USE 37/37, RETRIEVABLE 46.6%. **I am not claiming those still hold.**

---

## 5. STATE AT HAND-OVER

```
clock                 2026-08-11 ~19:20 UTC (Dubai 23:20)
branch                fix/the-chain-gets-its-numbers, PR #199, not merged
Row #3                125/152 — DOWN 1 from 126, cause not yet identified
gates                 23/23 on BOTH projects
parity                BOTH PROJECTS IN SYNC (850 functions, 56 anon-exec SECURITY DEFINER)
advisors              0 ERROR
company_goals         63 · 20 measurable (was 8)
department_objective  66 · 20 measurable, 20 measured, 0 failed (was 0 measurable)
employee_kpi          124 · 94 measurable · 74 carrying a stored actual (was 0)
org_tasks             839 · 142 with an owning employee (was 0)
org_agents            93 active · 0 without responsibilities (was 14)
demand side           customers 0 · inquiries 0 · quotes 0 · transactions 0 — unchanged, and the
                      new goal measures now say so out loud instead of being silent
```

New routines, all on cron, all revoked from PUBLIC:
`fn_dept_objective_measure` (03:25 daily) · `fn_employee_kpi_measure` (03:30 daily) ·
`fn_goal_decompose` (03:10 Mondays, before the 04:00 KPI review) ·
`fn_employee_scorecard` (read at prompt time) · `fn_employee_responsibilities_backfill`.

`scripts/qsql.mjs` gained `--ref=` so staging can be read directly; it was production-only.
