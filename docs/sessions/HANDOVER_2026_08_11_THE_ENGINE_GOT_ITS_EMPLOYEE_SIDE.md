# HAND-OVER — 2026-08-11 late · the engine got its employee side

Session ran 21:28 → 23:0x UTC (Dubai 01:28 → 03:0x on the 12th). **[PR #220](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/220) merged to `main`, six commits.**

> **Clock note.** The DB clock said **2026-08-11 21:28 UTC** when this session opened, and the git
> commits from the *previous* session are stamped `2026-08-12 01:25 +0400`. Both are the same
> instant. The brief's "STATE AS OF 2026-08-12 ~21:20 UTC" is a Dubai/UTC slip — it was
> 2026-08-12 01:20 **Dubai**. Every date in this document is UTC.

---

## 1. THE ONE THING TO READ IF YOU READ NOTHING ELSE

**The workflow engine now runs itself.** At session start: 195 runs in flight, 195 ready steps,
**zero executable**, 5 runs completed in the engine's lifetime. At hand-over:

```
workflow_run     5 done / 195 running  →  103 done / 97 running / 7 failed
workflow_step    143 done              →  147+ done, and climbing on a 10-minute cron
ready and dispatchable   0             →  71, draining ~2 every ten minutes
actor names resolving to nobody  33 of 66  →  1 of 66  ("domain specialist")
unfinished steps addressed to nobody  2,164  →  1
```

`metric_lifecycle` is walking on its own — `intel_director` performs step 2 ("Instrument it with a
measure that runs"), then `forecast_analyst` performs step 3 ("Measure on cadence and record the
actual"), each producing a 3,700–4,700 character deliverable with a real closing OUTCOME line.

---

## 2. WHERE THE BRIEF'S PLAN DIED ON MEASUREMENT — THREE TIMES

**Re-measure before building what a brief proposes.** This is now eleven such cases across two
sessions.

| the brief said | measured |
|---|---|
| "`org_tasks.assigned_agent` is the natural landing place" for dispatched steps | **It is a fork bomb.** 124 of the 195 ready steps are `employee_task`/`owner`, and `workflow.trigger_event` for `employee_task` is `'task.assigned'`, **live**. One org_task per step starts another 17-step run per step: 124 × 17 = 2,108 tasks on the first pass. Worse, **96 of those 124 runs own an org_task that is already `done`** and 28 one `in_progress` — the work was performed by `cos_execute` and reviewed by `fn_task_review`, and only the `workflow_run` was never told. Dispatching would have commissioned finished work. |
| "the gateway must return the `ai_cost_log` row id for the confidence to attach to the right call" | **Not needed, and there is no concurrency hazard to design around.** `llm.ts` sends `confidence: def.confidence` — a *static* value bound when `makeLlm` is constructed, which is exactly why the only two emitters always reported 1.0000. `ai_gateway` separately calls `selfReportedConfidence(out)` on the model's real output and passes it to `fn_llm_log` **in the same insert, after the call**. |
| "`employee_kpi_history` began producing a second observation from 12 Aug, so the data side is solved" | **Scheduled, not solved.** At 22:15 UTC the table held 123 rows across 95 employees on exactly **one** `measured_on`. Zero of 93 active employees had two. `fn_employee_kpi_measure` runs at 03:30 UTC. |

---

## 3. WHAT LANDED, WITH THE MEASUREMENT

### 3.1 The employee-side dispatcher (the founder's item #1)

`workflow_dispatch` — a new edge function, on a 10-minute cron offset from the executor-side sweep.
Same shape as `action_worker`, which solved the identical problem one queue over: claim atomically →
the employee answers with its own `fn_agent_context` → **assert the deliverable** (cos_execute's
`NOT_WORK` regex verbatim) → `fn_workflow_step_done`.

It refuses, in `fn_workflow_step_claim` rather than in the caller, so the refusal is a property of
the queue: `employee_task` runs, `gate='founder'` (all four — Stripe refund, invoice payment,
campaign publish, complaint remedy), and any step a real executor can run.

**The fifth identity vocabulary, fixed.** `workflow_step.actor_role` holds 66 distinct values across
three namespaces at once — agent keys, job **titles**, and run-relative **positions**. Five
employees appear twice under two spellings (`compliance_mgr` AND `Compliance Manager`, `brand_mgr`
AND `Brand Manager`, `qa_manager` AND `Quality Assurance Manager`, `financial_analyst` AND
`Financial Analyst`, `risk_governance_mgr` AND `Risk & Governance Manager`). Fixed at the resolver
(a title arm) and at the **write boundary** in `fn_workflow_start`; the raw string survives in
`input.addressed_as` so no reassignment is silent.

`employee_task` follows its own task instead (`fn_workflow_run_follow_task`, a trigger — fourteen
routines write `org_tasks`). **96 runs closed.** Their unfinished steps are `'skipped'` carrying the
task id and status, **not `'done'`** — the company performs that loop as one act and may not claim
seventeen observations it never made.

### 3.2 A ceiling two functions had been writing under

`ai_gateway` routes on `fn_task_class`; a function with no row there defaults to `general_drafting`
— haiku, **900 tokens** — and `min(caller, policy)` makes a `SONNET_FIRST` ladder at `max: 1400`
irrelevant.

- **`action_worker` had no row.** 229 model calls in 14 days, **133 of them returned
  `output_tokens` exactly 900.** 58% of every determination it has settled an inbox item with was
  cut off mid-sentence, and its `MIN_CHARS=400` assertion could not see it because 900 tokens is
  ~3,000 characters.
- **`workflow_dispatch` had no row** — my own defect, caught on its first production call.

The gateway had been saying so in its own log, every call, unread:
`"[UNMAPPED function ... defaulted to general_drafting] | TRUNCATED: the model stopped at the
900-token ceiling"`. Both now carry an `agent_reasoning` row. Verified on the same step:
**900 → 5,437 output tokens, haiku → sonnet-5, `agent_key` null → `intel_director`.**

The one step I settled on a truncated deliverable is **reopened**, not left. That was a false
success and it was mine.

**Capped at 24 delivered steps per UTC day.** The honest fix costs 0.217 AED/step against 0.0221;
uncapped at 288 steps/day that is 62 AED against a whole-company **143.75 AED per thirty days**,
pointing straight against the concentration `fn_spend_concentration_check` filed as `org_tasks` 1309.

**What it actually cost.** This whole session spent **3.11 AED** across 39 model calls, of which the
dispatcher is **2.11 AED across 15 steps** (0.141 AED/step in practice, below the 0.217 first
measurement). The 30-day company total moved 143.75 → 148.61 AED. The cap holds the dispatcher at
roughly 3–5 AED/day once the 71-step backlog is draining at full rate.

**Staging costs nothing.** The cron is on both projects (so parity stays IN SYNC, and its sibling
`workflow_step_sweep_10min` is also active there), but staging's `ready_dispatchable` is 0 and it has
made **zero** dispatch model calls. If staging ever accumulates in-flight runs the 24/day cap bounds
it there too.

### 3.3 Model cascading, unblocked (item #3)

Two narrow gaps, not the one the brief named:

- **Nobody could report a confidence.** `selfReportedConfidence` required the *whole* reply to be a
  JSON document. It now also reads the last balanced `{...}` — exactly where `agent_brain` has
  always put its `@@ACTIONS@@` tail. Candidate starts are tried nearest-first with `JSON.parse` as
  the validator; a greedy `/\{[\s\S]*\}/` is what **not** to do.
- **Nobody was asked.** `agent_brain`'s `@@ACTIONS@@` contract now requires `confidence` with the
  scale spelled out, and says out loud that a confidence which is always high tells the company
  nothing. `workflow_dispatch` asks for the same.

**The first real confidences this company has recorded: 0.40, 0.45, 0.55.** Six of them, three
distinct values, from `intel_director` and `forecast_analyst`. Not the 1.000 constant.

**The prior.** `p_confidence` is *this* call's confidence and cannot exist before the call — that
shape is why both arms of `fn_ai_route` were dead. `fn_ai_confidence_prior` gives a caller supplying
nothing the agent's own median for that task class over 14 days, and **returns null unless there are
at least 5 observations AND they vary**. The variance guard is the important half: a model reporting
the same number every time would otherwise downgrade itself on its own unvarying optimism.

Verified by aborted-transaction probe, no rows left behind:

```
no history          → sonnet-5 (large), unchanged
6 varying, med .965 → ~claude-haiku-latest, DOWNGRADED
                      why: "own median over 6 calls on agent_reasoning, spread 0.0232"
6 identical at 1.0  → sonnet-5, NOT downgraded (variance guard)
3 varying           → sonnet-5, NOT downgraded (sample guard)
```

`fn_ai_route` was **transformed from the live production definition, not retyped** — the diff
against `pg_get_functiondef` is three hunks and nothing else.

**And then the guard caught a real one, within the hour.** Two employees now have five or more
confidences on production:

```
intel_director  n=6  mean 0.458  stddev 0.0801  → prior {n:6, prior:0.45, spread:0.0801}, LIVE in fn_ai_route
ai_trainer      n=6  mean 1.000  stddev 0       → prior NULL, refused
```

`ai_trainer` emits exactly 1.0000 every time — the founder's own named defect, sitting in production
right now. The variance guard refuses it on both `agent_reasoning` and its own `json_extraction`
class. `intel_director`'s prior is real and feeding the router, which correctly declines to act on
it: 0.45 is neither ≥ 0.95 (downgrade) nor on a `small` tier (escalate). **The cascade is armed,
running on real evidence, and correctly doing nothing yet.**

### 3.4 Goals and KPIs (item #2)

Eight measures, each **executed on production before being stored**. Six of the eight report a MISS
on their first measurement, which is the point — a goal with no measure cannot be missed.

```
knowledge_accuracy      55.80  against 98    MISSED, badly
api_response              316  against 400   met
backup_success          85.56  against 100   MISSED
critical_incidents         16  against 0     MISSED
workflow_automation     96.32  against 98    MISSED, narrowly
kpi 112 variance explained  62.12  against 90   MISSED
kpi 122 demand with no supply  0  against 0    met — and it means "no demand yet"
kpi 123 supplier response   66.67  against 60   met
```

Two vocabulary traps caught by measuring rather than reading: `os_incidents.severity` has never held
the string `'critical'` (high is the worst class this company records — a literal
`severity='critical'` returns 0 forever and reads as a clean record); and `leads.rv_response_rate` is
a 0–1 fraction against a 60 **percent** target, the same ×100 trap as the company goal.

Goals measurable **24 → 29** of 63. KPIs **104 → 107** of 123. All 107 verified to execute without
error under an aborted-transaction probe.

### 3.5 Performance as a trend (item #4)

The check's source was `employee_kpi.created_at` — **the date somebody wrote a KPI definition**. A
second row means a second KPI was defined, not a second observation, and counting it could only push
the check towards a false MET. Three parts shipped: `fn_ws_agent_ops` gains `kpi_trend` (attainment
averaged across the employee's KPIs per day, so the series is "how this person performed"),
`AgentDrawer` draws it with `MiniLine` and its empty state says *which* of the two reasons applies
rather than drawing a flat line through one point, and the scorer reads `employee_kpi_history`.

**This makes the check harder and it is still red tonight**, correctly. It turns MET on its own after
the 03:30 UTC cron writes day two, on real measurements, with nothing backdated.

### 3.6 The five delete proposals (item #5) — two were miscounted

| | decision |
|---|---|
| **2743 "33 orphan expectations"** | **The true count is 2.** 31 were the detector's own blind spot: alias-resolvable employees (`chief_of_staff` → `brief`, 396 runs in 26 days) and 105 rows with `kind='code'`, which `agent_runs` uses deliberately. Both surviving rows sit at `max_silence_hours = 999999`, so neither raises the alarm the proposal describes. **Detector fixed, data kept** — deleting on the bad count would have removed 31 live watches. |
| **2741 "96 superseded policy rows"** | **KEEP.** They are the pack's **target org chart** — department, title, manager and authority_tier for 96 roles. `routing_tier` superseded their *model* choice, not their org design, and `fn_ai_route` reads only `scope='current_agent'`. |
| **2742 / 2744** | **KEEP WITH A STATED REASON**, stored on new `company_goals.no_measure_reason` and `employee_kpi.no_measure_reason`. Silent goals **31 → 0**, silent KPIs **16 → 0**. Both counts now exclude rows carrying a reason, so writing one closes the proposal and deleting one reopens it. |
| **2745 `marketing_copy`** | **KEEP the employee, RETIRE its KPI.** 42 `org_tasks` had been raised for a KPI missed by somebody who is not employed. |

**And a decision now holds.** The un-guarded proposer reopened three of the five within *seconds* of
them being answered. Reopening now requires the count to have **grown** past what was accepted.
Verified: re-running against all five decided categories opens nothing.

### 3.7 The manual

Six active cron jobs were undocumented — **five from the previous session and one mine tonight**.
All six registered with what they actually do. Drift is now 0 in both directions and
`s38-manual-always-current` meets all three of its legs on its own evidence.

---

## 4. WHAT I MEASURED AND DELIBERATELY DID NOT BUILD

Recorded so the next session does not re-derive it or, worse, build it.

- **`explain-knowledge-used` needs no work.** 425 of 468 is a stale-window artefact: **420 of 420
  decisions since 6 Aug cite their knowledge.** All 43 uncited are `kind='action_gate'` from 4–6 Aug
  and age out of the rolling 7-day window by **13 Aug**. The writer was fixed by an earlier session.
- **`s32-reputation-six-dimensions` cannot be closed honestly today, and the blocker is not a
  missing routine.** Of 93 active employees: 93 have KPI history, 40 have tasks, 29 have
  `agent_actions`, 23 have reviews, **14 have runs, 14 have cost, 13 have exams**. Filling all six
  axes for all 93 means inventing numbers for 53–80 employees per axis. One axis — *decision
  quality* — has **no column at all**. The real blocker is that most of the org chart has never been
  given work, which is exactly what the dispatcher starts to change.
- **`s36-recommendation-seven-fields`** is a universal over 1,280 historical `agent_actions` rows.
  Only new rows can carry alternatives/assumptions/cost, so the earliest honest green is 30 days
  after the contract changes. Worth doing; not closable tonight.
- **`what-if-confidence-score`** — 3 of 6 simulations lack a confidence, but both simulators emit
  the key, so it self-heals as old rows leave the window.

---

## 5. THE ROW #3 NUMBER — 125 → 126, AND THE FIRST ATTRIBUTABLE MOVE

Run to completion **three times** tonight. Two verdict lists saved, and the diff between them is the
first attributable Row #3 change this codebase has produced.

```
run 1 (22:0x)  125/152 — per-check list BYTE-IDENTICAL to the previous session's
run 2 (23:0x)  126/152

diff run 1 → run 2:
  + MET      s38-manual-always-current
  - MISSING  s38-manual-always-current
  (nothing else moved, in either direction)
```

The 126 is **one check, one cause, proven by diff** — registering the six cron jobs. The earlier
byte-identical list matters just as much: it says plainly that the workflow engine, the router and
the goal chain do not touch the executive UI measures, so nothing in this session's headline work
was quietly scoring itself.

Saved: [`ROW3_VERDICTS_2026_08_11_LATE.txt`](ROW3_VERDICTS_2026_08_11_LATE.txt) (125) and
[`ROW3_VERDICTS_2026_08_11_FINAL.txt`](ROW3_VERDICTS_2026_08_11_FINAL.txt) (126).
**Save the next run's list too — that is the only thing that makes a diff possible.**

---

## 6. END-OF-SESSION SWEEP

| check | result |
|---|---|
| `fn_os_portals_gates()` production | **23 / 23 met** |
| `fn_os_portals_gates()` staging | **23 / 23 met** |
| `project_parity.mjs` | **BOTH PROJECTS IN SYNC** — 198 edge fns, 420 tables, 862 functions, 156 triggers, **0 tables without RLS**, **56 anon-executable SECURITY DEFINER (unchanged — every new SECURITY DEFINER was revoked from PUBLIC)** |
| Supabase advisors, production | **0 ERROR** security (167 WARN), **0 ERROR** performance (14 WARN) |
| `sql_files_match_live.test.mjs` | **drift 0**, at the floor |
| GitHub Actions | green on every commit — classification/pricing/refund, migration lint, app typecheck, edge typecheck, Vercel |
| Vercel | production READY; all five preview deployments READY |
| **Pack scorecard — production** | **INGESTED 100%, IN USE 37/37, RETRIEVABLE 49.4%** (was 46.6%) |
| **Pack scorecard — staging** | **INGESTED 100%, IN USE 37/37, RETRIEVABLE 42.6%** |

**The pack scorecard ran for the first time in three sessions.** It needs `--packs=<extracted dir>`;
the six `QuotesDone_*_v2026.07.31.zip` files are all present in `~/Downloads` and extract cleanly to
596 files. Extract them to a scratch directory and pass that — there is no reason for this to be
skipped again.

---

## 6b. AFTER THE FIRST HAND-OVER — [PR #221](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/221)

I stopped too early and the founder said so. Three more things landed, and two of them were **defects
I had introduced hours earlier**.

**Staging stops driving production.** The four crons in §7 are unscheduled on staging and added to
`staging_cron_exclusions.json` with the measurement as the reason. Measured before removing anything:
not doubling data (`health_checks` takes 5/hour regardless of two invokers firing 8×/2h each) and
costing no model spend (zero `ai_cost_log` rows in 7 days) — but definitely arriving, 97 and 96
successful invocations, every one HTTP 200. Parity holds at prod 172 / staging 55, 117 excluded.
**`qd_guard` refused my first attempt** because the production ref appeared in my comments; it was
right and I complied rather than working around it.

**The root cause is escalated, not guessed at:** `cred_cron_monitoring`, `cred_cron_agents` and
`inbound_secret` are **byte-identical on both projects** — same md5, same length. Anything holding
staging's `app_secrets` can invoke any production edge function with internal authority. Rotating
them touches all 172 active jobs and whether the sharing is deliberate is a fact you hold.

**The process did not accumulate — my defect.** The dispatcher passed each employee the run's trigger
context and nothing else, so `forecast_analyst` answered step 3 with no sight of what
`intel_director` concluded in step 2. Six independent essays about one metric is not a process. Fixed
at the **claim**, so it applies to every consumer of the queue: the last three finished steps travel
with it, conclusion only. Verified by probe — claiming `strategic_review` step 3 for `brief` now
returns step 1's real finding, *"…are missing and are being raised as a gap rather than assumed."*

**Nothing read the deliverables — also my defect, and instance #5 of this estate's recurring root
cause.** Sixteen deliverables of 3,700–4,700 characters, and the only routines touching
`workflow_step_run.output` were the two that write it. `fn_ws_company_os` gains `process_work`;
`OsxShell` draws it as *"What the company's processes produced"* with the confidence toned and each
row saying out loud that the mode is **advisory — a determination, not a side effect**.

**Verified after:** the three newest deliverables all build on their predecessors.
`strategic_review` step 5 by `brief` — *"Two re-plan work threads (category-liquidity remediation
owned by Supplier Ops, P1-backlog/refund-gate review owned by Ops/Support) and one
objective-supersession recommendation…"* — is genuinely cascading from the step-4 decision, with
named owners. That is a company running its own process, not six essays.

---

## 7. ONE THING I FOUND AND DID NOT FIX

**FIXED IN §6b — kept here for the record.** Four active cron jobs on STAGING post to PRODUCTION URLs. Staging has 58 active jobs and 4 of
them contain the literal production ref `htdblwldjkcgjvmqkbeh` — `ai_health_15min` is one. So a
staging cron is invoking production edge functions every fifteen minutes.

I did not fix it because I have not measured what those four do or whether it is deliberate, and
changing production-facing schedules on a guess is worse than the drift. **My own new cron builds
its URL from `app_secrets.project_ref` at run time** precisely so it could not become the fifth.

---

## 8. STATE AT HAND-OVER

```
clock                 2026-08-11 ~23:0x UTC (Dubai 03:0x on the 12th)
main                  PR #220 merged, six commits
Row #3                126/152 — up one, attributable by diff to s38-manual-always-current
gates                 23/23 on BOTH projects
parity                BOTH PROJECTS IN SYNC (862 functions, 156 triggers, 56 anon-exec SECDEF)
advisors              0 ERROR on security AND performance
scripts/sql drift     0, ratchet at the floor
workflow_run          103 done · 97 running · 7 failed   (was 5 · 195 · 7)
workflow actors       1 of 66 catalogue names unresolvable · 1 live step addressed to nobody
company_goals         63 · 29 measurable (was 24) · 0 silent (no measure AND no reason)
employee_kpi          123 · 107 measurable (was 104) · 0 silent
employee_kpi_history  ONE measured_on so far — day two lands 2026-08-12 03:30 UTC
ai_cost_log           confidence live and DISCRIMINATING: 0.40 / 0.45 / 0.55
delete proposals      8 rows, all 8 decided; re-running the proposer opens nothing
demand side           customers 0 · inquiries 0 · quotes 0 · transactions 0 — unchanged
```

New this session: `workflow_dispatch` (edge, cron 10-min) · `fn_workflow_actor_resolve` ·
`fn_workflow_step_claim` · `fn_workflow_step_release` · `fn_workflow_run_follow_task` (+ trigger) ·
`fn_workflow_actor_coverage` · `fn_ai_confidence_prior` · columns `company_goals.no_measure_reason`
and `employee_kpi.no_measure_reason`. Every new SECURITY DEFINER revoked from PUBLIC in the same
migration and promoted with `--ddl`.

---

## 9. WHAT I WOULD DO NEXT

1. **Confirm the two checks that turn green on their own** — `employee-performance-trend` after the
   03:30 UTC cron, `explain-knowledge-used` after 13 Aug. Neither needs code.
2. **The recommendation output contract** (`s36`, `explain-alternatives-considered`) — alternatives,
   assumptions, risks, cost, expected impact. Same shape as tonight's confidence work; the green is
   30 days out but the capability is immediate.
3. **Watch the dispatcher's confidences accumulate.** Once any employee has 5 varying observations on
   a task class, `fn_ai_route` starts cascading for real — and nothing has to be built for that.
4. **The four staging crons pointing at production** (§7).
5. Still the founder's calls, unchanged: **resuming supplier invites** (list verification costs
   money) and **the spend split** (`org_tasks` 1309).
