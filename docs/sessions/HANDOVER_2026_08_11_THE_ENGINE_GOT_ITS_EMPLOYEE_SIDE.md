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

---

## 10. A DEFECT THE ENGINE MADE VISIBLE ON ITS FIRST NIGHT — NOT MINE, NOT FIXED

`workflow_run` went 7 failed → 8 during the session. That is the engine working: before tonight a
run whose step failed sat `running` forever. Now it reaches a terminal state and `failed_workflows`
can see it.

**The failure is worth its own look.** All three failed `exec_review` steps carry the identical
signature in `workflow_step_run.output`:

```
Timeout of 140000 ms reached. Total time: 140002 ms
  (DNS time: 140002 ms, TCP/SSL handshake time: 0.000000 ms, HTTP Request/Response time: 0.000000 ms)
```

DNS accounts for the entire 140 seconds; the handshake and the HTTP exchange never happened. The
step is `strategic_review` step 4 — *"Decide and record rationale"*, actor `ceo`, gate `authority` —
routed to `exec_agents` by the **executor-side** sweep, not by the dispatcher I built.

Occurrences: **2026-08-11 04:09 and 04:24 (both `cpo`), and 22:54 (`ceo`)**. The first two predate
this session, so this is not something tonight introduced — it is something tonight made visible.

**I did not diagnose it further and I am not guessing at the cause.** Two readings are open and I
have not distinguished them: pg_net mis-attributing a connect/read timeout to DNS (its timing
breakdown is unreliable on timeout), or `exec_agents` genuinely exceeding 140s. Against the first:
every `net.http_post` this session made to the same host resolved and returned 200. Against the
second: a 0.000000 ms handshake means no connection was ever established, which is not what a slow
function looks like.

**Where to start:** `exec_agents`' own runtime on a successful `exec_review`, and whether
`org_action_executor.timeout_seconds` for `exec_review` is below what the function actually needs.
Three identical failures on one action class is a pattern, not an incident.

---

## 11. MORNING OF 12 AUG — THE DECISION STEP, AND WHY THE AI LAYER WENT QUIET

Four more PRs: [#224](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/224),
[#225](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/225),
[#226](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/226).

**`employee-performance-trend` went MET on its own**, exactly as predicted: the 03:30 UTC cron wrote
day two into `employee_kpi_history`, and the check reads *"94 of 93 active employee(s) have more
than one performance observation in 90d in a REACHABLE source."* Nothing backdated.

**The engine's own decision step had been timing out 25 times in 40.** `strategic_review` step 4
dispatches `exec_review`, which ran **all six officers sequentially in one request** — 4.9 model
calls per invocation, up to 17, summing to 289.8s at worst against a 140s executor timeout, with
`max_attempts: 1` so each timeout permanently failed the run. Now `Promise.allSettled`: wall time is
the slowest officer, not the sum. Verified — `run_all` returns 200 where it used to time out.

**Three readings I had to discard getting there**, all recorded in the SQL file: pg_net attributes
the whole elapsed time to DNS on timeout (not a DNS problem); `exec_agents` is not slow (344 calls,
median 16.4s, max 31.5s); and `action_execution.finished_at - started_at` is the invoker's
dispatch-then-collect cycle, not runtime.

### THE ONE THING THAT NEEDS YOU

**OpenRouter is out of credits for the expensive tier, and it is gating work right now.** I know
your standing rule is not to report the balance. This is not a balance report — it is that the
company's reasoning layer is currently failing:

```
ALL MODELS FAILED after the full ladder:
{"message":"Insufficient credits...","code":402,"metadata":{"limit_source":"openrouter_credits"}}
ladder: ["anthropic/claude-sonnet-5","anthropic/claude-opus-4.8"]
```

`~anthropic/claude-haiku-latest` (63/68) and gemini (11/11) still run; sonnet-5 and opus-4.8 are
refused. So the cheap paths work and every **employee reasoning** path — `agent_brain`,
`action_worker`, `workflow_dispatch`, `exec_agents` — does not.

**It found this because of a fix made in the same hour.** A failed call used to log `ok=false`, zero
tokens and the ordinary routing rationale — *that* it failed, never *why*. The reason existed in
`lastErr`, was returned in the HTTP body, and was thrown away. It is now written to `ai_cost_log`.

**And it corrected me.** I claimed in #224 that the fallback ladder "has never engaged", on the
evidence that no row in 24h carries `fell back from`. That string is only written when a fallback
**succeeds**, so an all-models-failed ladder is indistinguishable from one never tried. The response
body shows both models were tried and both refused. **The ladder works; my measurement did not
support the claim.**

### AND A MESS I MADE AND CLEANED UP

Probing the timeout fix during that outage wrote **seven empty officer reports**, which knocked
`exec-intel-quantified-recommendation` from MET to MISSING — correctly, because they displaced the
last real reports. Deleted on a narrow guard; the `agent_runs` rows exec_agents wrote for each
(`status='error'`, with the reason) are kept, because those are the honest record. Verified after:
7 of 7 officers carry 3–12 recommendations again.

### THE NUMBER, FULLY ATTRIBUTABLE

```
125  start of session
+1   s38-manual-always-current      six cron jobs registered
+1   employee-performance-trend     the 03:30 cron, on real data
-1   s33-replay-six-tracks          date rollover: no outcome_record row for 11 Aug. NOT mine.
126  now, confirmed by three saved verdict lists and two clean diffs
```

The dispatcher meanwhile hit its ceiling honestly: **24/24 steps delivered today, capped, 49 still
ready, zero steps stuck running** — it spent its budget on real work before the credits ran out, and
the release path left nothing wedged.

---

## 12. AFTER THE RECHARGE — TWO MORE UNREACHABLE PATHS, AND A MEASURED STOP LINE

[#228](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/228),
[#229](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/229).

**An empty officer report is not a report.** `exec_agents` inserted an `exec_reports` row even when
it reached no model, so the outage produced seven rows saying "AI synthesis unavailable" — and
because the check reads the *newest* report per officer, they displaced six officers' real ones. It
now files nothing and records the failure in `agent_runs` with its reason. Verified on both paths:
nothing filed during the outage, `{"report_id":296,"filed":true,"recommendations":3}` after it.

**`cos_execute`'s stale reclaim could only run when the queue was empty.** `if (batch.length <
MAX_TASKS)` gave stale work the slots the assigned queue left over — and with **340 tasks in
`assigned`**, the FIFO head fills both slots every run. The branch had never once executed. **48
tasks sat `in_progress` for up to six days**, none at MAX_ATTEMPTS. Now a reserved slot, oldest
first, mirroring the fairness block directly above it. Verified: task 49, untouched since
2026-08-06, came back `done` at 07:55 while the same run still delivered a task from the assigned
queue.

### THAT IS FIVE INSTANCES OF ONE DEFECT IN ONE SESSION

A recovery path that is correct, deployed, and reachable only under a condition that never holds:
the parked workflow steps, `fn_ai_route`'s confidence arms, `exec_review`'s 140s timeout,
`cos_execute`'s stale reclaim, and `fn_delete_proposer` reopening decisions it had just been given.
**The 25 existing watcher functions miss all of them, because nothing failed** — the runner ran,
succeeded, and did nothing. Do not add a 26th generic watcher; measure the specific queue. The
question that finds them is *"has this path ever actually executed?"*

### THREE MEASUREMENT ERRORS OF MY OWN, CORRECTED NOT SHIPPED

- *"cos_execute has not run in 6 hours."* It logs its per-run row as `agent='chief_of_staff'`. It
  had run 12 times in 12 hours. `agent_runs.agent` is a JOB name and this one function uses two.
- *"outcome_record has 0 observed — the learning loop never closes."* 17 of 66 are observed **and**
  closed, and `due_now_unobserved` is **0**. Every outcome past its due date has been measured.
- *"The fallback ladder has never engaged"* (§11) — corrected there.

### WHERE ROW #3 STOPS BEING WORTH CHASING, WITH THE MEASUREMENT

Four reds probed this morning; **none is honestly closable**, and each for a different reason:

| check | why not |
|---|---|
| `s32-reputation-six-dimensions` | of 93 active employees only **14 have runs, 14 have cost, 13 have exams**. Six axes × 93 means inventing 53–80 numbers per axis. One axis has no column at all. |
| `s36-recommendation-seven-fields` | the population is **`it/incident` 487 and `onboarding/licence_expiring` 150** — machine-generated alerts, not deliberations. "Alternatives considered" for an expiring licence is fabrication. |
| `explain-alternatives-considered` | `challenge_record` holds 39 rows with alternatives and **no join key** to a surfaced action. Matching on prose would mis-attribute. |
| `s24-board-before-major-decisions` | the one unadvised decision is #42, *"Which agent owns signage work"* — a routine `route_category` call. The check reads every `decision_record` as major. It ages out of the window on **5 Sept**. |

The honest position: the remaining reds are mostly checks whose population does not match their
requirement, or which need demand, or a fixture set that has to be built. **Building the fixture set
for 101/102/103/114 is the one that is real work rather than a blocked measurement** — that is where
the next session should go if it wants Row #3 to move.

---

## 13. THE BOQ FIXTURE — FEASIBILITY ESTABLISHED, DELIBERATELY NOT STARTED

KPI 103 (`boq_analyst`, "BOQ lines extracted correctly", target 95%) and KPI 114
(`ai_qa_specialist`, "RFQ qualification accuracy", target 90%) are the only two of the four
"needs a fixture" KPIs that genuinely need one — their metric text says *"against the fixture set"*
and *"against the holdout set"* in those words. 101 and 102 were mis-reasoned and are corrected in
[#231](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/231).

**103 is feasible now, and here is everything the next session needs so it can be done in one pass.**

*Both drawing files still exist in storage* — checked against `storage.objects`, not assumed:

```
documents 4   drawing-files/drawings/27cbbc0a…/1781800750308_floorplan.jpg        present
documents 10  drawing-files/drawings/c5e47f2d…/1784145964068_villa_floorplan.png  present
```

*The ground truth does not require my judgement.* Each drawing states its own schedule, so the
fixture asserts "did the pipeline extract what the drawing says", which is arithmetic, not a
quantity-surveying opinion:

```
documents 10  LIVING/DINING 5.0×4.5 · BEDROOM1 4.0×3.5 · KITCHEN 3.5×3.0 · BEDROOM2 4.0×3.0
              BATHROOM 2.5×2.0  → 64 sqm of rooms, stated built-up area 78 sqm
              DOOR SCHEDULE D1 ×5 flush wooden 900mm · WINDOW SCHEDULE W1 ×4 sliding 1500×1200
              Floor 600×600 porcelain throughout · walls gypsum painted · gypsum false ceiling
documents 4   LIVING/DINING 5.0×6.0 = 30 sqm · BEDROOM 3×3 = 9 · BATH 3×3 = 9 → 48 sqm
```

**It is three pieces, not one**, which is why it is not started here rather than half-started:

1. a fixture table holding drawing → expected lines;
2. a **runner** — `measure_sql` cannot invoke `drawing_boq`, because that is an HTTP call; something
   has to execute the pipeline against the fixtures on a cadence and store the actual;
3. the measure comparing stored actual to expected.

Landing (1) without (2) produces a fixture table nothing reads — the exact defect this session spent
its time removing, five times over. Do it in one pass or not at all.

**114 needs a holdout set of qualified RFQs and there are 0 inquiries**, so unlike 103 it is blocked
on demand as well as on the set. 103 is the one that can be built today.

---

## 14. THE FIXTURE GOT BUILT, IN ONE PASS

§13 said the BoQ fixture was three pieces and should be done in one pass or not at all. It was done
in one pass: [#233](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/233),
[#234](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/234).

**`drawing_boq` had no way to be wrong.** A protected capability, wired into five functions, and
nothing had ever checked whether its output was correct. All three pieces shipped: `boq_fixture` /
`boq_fixture_run`, the **runner** `boq_fixture_check` (reads each drawing out of storage and posts
it to `drawing_boq` exactly as a real caller would, stubbing nothing), and `fn_boq_fixture_score`
holding the grading rule in SQL where it can be argued with.

**KPI 103 = 100.00 against a target of 95**, with the detail stored per run: doors 5=5, windows 4=4,
areas 78=78 and 48=48. **A NULL expectation is not scored** — drawing 4 prints no door schedule, and
counting that as a miss would punish the pipeline for the drawing's silence.

**100% here is a thin instrument and should not be oversold.** Two drawings, four checks. It proves
the pipeline reads a printed schedule correctly; it does not prove general BoQ accuracy, and the
number will mean more as fixtures are added than it does today.

**The first grading run failed and was right to.** `drawing_boq` nests its analysis at `j.boq` with
line items at `j.boq.boq`, and my unwrap expected the array one level up. It recorded `ok=false` and
the KPI kept its previous value rather than reading 0% — the behaviour that separates "not measured"
from "the employee scored zero", tested by accident on its first run.

**The engine also got a screen.** 238 runs and the only surface was a count tile. `workflow_state`
now carries runs by status, steps delivered by an employee, and the 25 longest-waiting in-flight
steps with the *resolved* employee each waits on. The oldest reads **144 hours — six days — waiting
on `intel_director`**. That was true before and nobody could see it. (My first version put `limit
25` on the aggregate query, which limits the aggregated row and not the rows fed into `jsonb_agg`;
caught by checking the output, not the code.)

### FULL SWEEP AFTER SIX EDGE DEPLOYS AND EIGHT SQL FILES

| check | result |
|---|---|
| Row #3 | **126/152, verdict list BYTE-IDENTICAL to the prior run — zero regressions** |
| `fn_os_portals_gates()` | **23/23 production, 23/23 staging** |
| `project_parity.mjs` | **BOTH PROJECTS IN SYNC** |
| anon-executable SECURITY DEFINER | **56** — unchanged baseline; every new routine revoked from PUBLIC |
| undocumented cron | **0** — the new weekly BoQ job is registered |
| `sql_files_match_live` | **drift 0**, at the floor |
| pack scorecard, production | INGESTED 100%, IN USE 37/37, **RETRIEVABLE 52.3%** (was 49.4% earlier tonight) |
| model failures, last 20 min | **0** |
| stuck workflow steps | **0** |

KPIs measurable **104 → 108** of 122 across the session. Goals **24 → 29** of 63.

### WHAT I DID NOT DO, AND WHY

**I did not raise the dispatcher's 24/day cap**, even after the recharge. 107 steps are ready and it
will take four to five days at that rate. The cap exists because of a measured spend concentration —
85.4% of model spend to `leadership`, 0.04% to `marketplace`, against revenue of 0 — and that split
is **your** open decision on `org_tasks` 1309. Raising the internal-reasoning throttle before you
rule on it would be me deciding the thing you reserved. One `CREATE OR REPLACE` changes it.

**I did not build the AI side panel.** It is less absent than spec #3 implies — a Secretary chat
surface and a per-entity `askAI` already exist in the shell. Making it a persistent panel on every
screen is a real change to the main shell, and at this point in the session I could not visually
verify it well enough to ship it safely.
