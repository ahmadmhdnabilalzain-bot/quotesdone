# Phase C — final independent re-acceptance audit, after the correction work

**Date:** 2026-08-16 · window 18:27–19:05 UTC · project `htdblwldjkcgjvmqkbeh` (the one project)
**Mode:** audit only. Nothing was fixed, redesigned or repaired. Phase A and Phase B untouched.
**Enforced throughout:** `NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`.
**Paid inference in the window:** 0 attempts, USD 0.00 — measured on both ledgers.
**Inputs treated as claims, not proof:** `docs/phase-c-correction/*` and PRs #425, #426, #427.
Every result below was re-measured against live production and the repository.

---

# PHASE_C_FINAL_ACCEPTANCE_FAIL

---

## Result by gate

| # | Original failed gate | Verdict |
|---|---|---|
| 1 | Component classification | **FAIL** |
| 2 | Real authenticated founder-command path | **FAIL** |
| 3 | Founder-command event / workflow identity | **PASS** |
| 4 | Autonomous event ingress | **FAIL** |
| 5 | Multi-department autonomous routing | **FAIL** |
| 6 | Event outbox claim and delivery | **FAIL** |
| 7 | Event-binding connected/deferred status | **FAIL** |
| 8 | Trace requirements and coverage | **FAIL** |
| 9 | Clarification reply and cancellation | **FAIL** |
| 10 | Refund-only founder approval | **FAIL** |
| 11 | Zero-cost provider guard | **FAIL** |
| 12 | Repository / live schema parity | **FAIL** |

| Adversarial check | Verdict |
|---|---|
| A — founder event eventual delivery | **FAIL** |
| B — deferred component exposure | **FAIL** |
| C — open trace coverage | **FAIL** |
| D — outbox row reconciliation | **FAIL** |
| E — event termination | **FAIL** |
| F — founder operating model | **FAIL** |
| G — zero-cost mode | **FAIL** |
| H — parity | **FAIL** |

One of the twelve original gates now passes. `fn_phase_c_invariants()` reports **71 of 71 green**
over every finding in this document.

---

## What genuinely improved

Stated first, because the correction did real work and this report should not bury it.

- **`EV-W01-STARTED` is gone.** A live authenticated command routed to W20 now emits
  `EV-W20-STARTED` to `marketing_director`. Verified on a fresh command (252) and by driving
  `fn_phase_c_lifecycle_event` across the registry. Gate 3 passes.
- **The autonomous entry point now delivers work.** `fn_phase_c_event_ingress` creates a run, a step
  run, an accountable task, traces and an outbox record in one transaction, or raises.
- **A delivery worker exists and runs.** Cron `phase_c_outbox_deliver_1min` claimed and delivered
  this audit's canary event within 27 seconds.
- **Empty-output completion is refused.** The canary's output hash is a real hash, not the SHA-256
  of the empty string.
- **The `classification = ''` invariants were genuinely corrected and genuinely fire.** Forced in an
  aborted transaction: `unclassified_components` moved 0 → 1, `unclassified_edge_functions` 0 → 1.
- **The deactivation of 221 components did not green anything by shrinking a population.** Tested
  counterfactually: with the `activation_state` filter deleted from all seven checks that read it,
  every one still returns 0.
- **The zero-cost invariant is now anchored to a stored constant and sums both ledgers.** The prior
  floating-window defect is gone.
- **30 of 30 scheduled `ai_health` runs since the correction recorded the skip** and none took the
  provider path.
- **Phase A drift 0, Phase B drift 0, Phase C drift 0, reporting-map drift 0.**
- **No instrument was weakened.** `export_from_either_source_is_identical.mjs` is byte-identical to
  the version that failed the previous audit. The three test-script changes are correct repairs: an
  absolute `count(*) = 0` became a real before/after delta, and an ownership case was moved off a
  step where the order check answered first.

---

## THE FAILURES

Ordered by consequence. None was fixed.

---

### FAIL 1 — The Command Center answers an unauthenticated request as the founder

Measured directly, twice, with no bearer token and then with **no headers at all**:

```
POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api  {action:'founder_command_inbox'}
→ HTTP 200   {"ok":true,"user":"build-mode@quotesdone.local", "counts":{"commands":8,"open_tasks":20,…}}
```

`fn_os_open_access()` returns **true**. `build-mode@quotesdone.local` is an **active** row in
`phase_c_founder_identity`, and `os_api` assigns it as `p_founder_identity` whenever no bearer token
resolves. The founder-identity allow-list that `os_api` names as the control for `founder_gated`
actions therefore admits anonymous callers as a registered founder.

Two commands in the table were created this way; one created four real tasks.

Compounding it: of the three `founder_gated` actions, **two never check the identity at all**.
`fn_founder_command_clarify` and `fn_founder_command_control` take no identity argument, `os_api`
passes none, and neither routine references `phase_c_founder_identity` — and `clarify` creates tasks
and emits the workflow start event. `fn_control_mode_require` is also globally disarmed
(`fn_phase1_disarmed()` = true), so the classification changes nothing at runtime today: 1,566
audit rows read `action_allowed_phase1_disarmed`, and the `founder_gated` branch has executed once
in the table's history.

Gate 2 asks for a **real authenticated** founder-command path. A real authenticated path exists — a
genuine session was minted for `management@quotesdone.com` and used for the canary. It is not the
**only** path.

**Affected:** `public.phase_c_founder_identity` (row `build-mode@quotesdone.local`),
`supabase/functions/os_api/index.ts` (BUILD_IDENTITY), `public.fn_founder_command_clarify`,
`public.fn_founder_command_control`, `public.fn_control_mode_require`.

---

### FAIL 2 — The self-feeding queue was not fixed. The fix is in the repository and is not on production

`fn_phase_c_event_consume` passes `'emit', false` into `p_ctx` (line 39). The **live**
`fn_phase_c_event_ingress` never reads it — `prosrc ~ '''emit'''` returns **false**; the string does
not occur in the body:

```
73:   -- (f) the durable event record.  Same transaction as the business state, by construction.
74:   v_outbox := public.fn_phase_c_outbox_emit(
75:     p_event_id, coalesce(p_ctx->>'producer', e.emitted_by),
```

`scripts/sql/phase_c_39_consumer_must_not_reemit.sql` **does** carry the fix —
`v_emit := coalesce((p_ctx->>'emit')::boolean, true)` at line 40, `if v_emit then` at line 91.
Production is running the body from `scripts/sql/phase_c_31_autonomous_entry_creates_work.sql`,
whose emit at line 161 is unguarded.

Even if it were live it could not work as written: lines 85–88 of the same routine raise `23502`
unless `v_outbox` is non-null, so suppressing the emit trips the routine's own completeness
assertion.

**Observed three times, all after the fix was claimed:**

| input | consumed | emitted | dedupe of the emission |
|---|---|---|---|
| 245 `EV-W20-STARTED` | 10:37:08 | **250 `EV-W20-STARTED`** | `ingress:EV-W20-STARTED:outbox:245` |
| 246 `EV-W20-STARTED` | 10:37:08 | **251 `EV-W20-STARTED`** | `ingress:EV-W20-STARTED:outbox:246` |
| 316 `EV-W20-STARTED` | 18:36:00 | **317 `EV-W20-STARTED`** | this audit's canary |

Reproduced independently in an aborted transaction on a different workflow: seeded one
`EV-W22-STARTED`, consumed it, rows for that event+object went **1 → 2**.

**Deduplication conceals the loop rather than preventing it.** The second generation carries a
*different* dedupe value from the first, so `duplicate_outbox_dedupe_values` = 0 can never see it.
The cycle stops at depth 2 only because `ingress:<event>:<object>` collides with itself on the third
pass. No invariant of the 71 tests consumer self-emission.

**Affected:** `public.fn_phase_c_event_ingress`, `public.fn_phase_c_event_consume`,
`scripts/sql/phase_c_39_consumer_must_not_reemit.sql` (not deployed), outbox 250, 251, 317.

---

### FAIL 3 — Repository / live parity reports zero drift over a correction that is not on production

This is FAIL 2's instrument, and it is a separate defect.

| Check | Result |
|---|---|
| `scripts/checks/sql_files_match_live.test.mjs` | 439 routines, **0 not present, 0 drifted** |
| `scripts/checks/export_from_either_source_is_identical.mjs` | **exit 0**, identical |
| `node scripts/verify_deploy_parity.mjs --all` | pass |

`phase_c_31` and `phase_c_39` **both define `fn_phase_c_event_ingress`** and were committed in the
same commit `8eebbec`, git commit time `2026-08-16T15:11:30+04:00`. `sql_files_match_live` resolves
each routine to the *newest file by git commit time*; on a tie it selected `phase_c_31`, so it
compares production against the **unfixed** definition and certifies it. The repository holds two
conflicting definitions of one routine, production carries the older one, and the gate named
repository/live parity reports 0.

Three further parity findings, each measured:

- **`org_phase_baseline` has no write-time guard**, and Phase A's row was re-recorded *from live* on
  16 Aug using the same expressions `fn_phase_a_baseline_drift()` compares — so several of its
  "0 rows" subjects cannot report drift by construction.
- **27 live routines have no `CREATE` statement anywhere in the committed repository.** All three of
  gate 12's instruments measure file→live; none measures live→file.
- **An untracked working-tree file has already been applied to production**: a live schema column and
  three `app_secrets` keys exist with no committed DDL, and the regenerated `full_schema.sql`
  absorbed them rather than flagging them.
- The CI drift check the correction cites as its durable guard is **schedule-only, cannot gate a
  pull request, and its two most recent recorded runs both FAILED**. No CI run has confirmed the fix.

---

### FAIL 4 — The delivery backbone's entire failure branch is unreachable dead code

`fn_phase_c_outbox_deliver` raises **SQLSTATE 42804** before it can record anything on the failure
path. Proven by execution in an aborted transaction: the consumer for outbox 195 correctly returned
`handled=false`, and the worker then raised
*"COALESCE types text and timestamp with time zone cannot be matched"*.

Cause, confirmed against `information_schema.columns`:

| column | type | nullable |
|---|---|---|
| `first_failure` | **text** | NOT NULL, default `''` |
| `next_attempt_at` | timestamptz | **NOT NULL** |

The body writes `first_failure = coalesce(first_failure, now())` — text against timestamptz, and
vacuous anyway since the column is NOT NULL, so the diagnosis can never be written. Fixing the
42804 only exposes the second fault: the dead-letter path writes `next_attempt_at = null` into a
NOT NULL column → **23502**.

Therefore `retry_wait = 0`, `dead_letter = 0`, `attempts > 1 = 0`, `retryable is not null = 0` and
`first_failure non-empty = 0 of 14` are **pinned at zero by construction, not produced by a healthy
queue**. The document's "dead-letter 0, retry_wait 0" is a green number measuring something other
than its name. `retry_erased_the_first_failure` filters on `attempts > 1` — a population that is
empty and cannot grow.

**No test covers it.** `fn_phase_c_outbox_deliver` appears nowhere in `scripts/checks`. The
injected-defect suite exercises `fn_phase_c_outbox_settle` instead — a routine nothing in the
database calls.

---

### FAIL 5 — Nothing closes a workflow, and 66 steps report success while stopping mid-workflow

- **No routine in the database can close or advance a workflow run.** Completing every step of a
  workflow, including its declared closure step, leaves `phase_c_workflow_run.state = 'queued'` and
  `closed_at = null`. All 8 live runs are `queued` or `cancelled`; none has ever completed.
- **`terminal_step` fires on 66 steps that are not terminal.** `fn_phase_c_event_consume` derives
  successors only from `phase_b_handoff`. A step whose `next_step_if_pass` names a real step but
  which has no handoff edge returns `handled=true, downstream_ref='terminal_step:<step>'` with no
  error — the chain stops mid-workflow and reports success.
- **Error and empty return the same value**: "no successors exist" and "successors exist but none of
  their owners resolves" both produce `handled=true, reason=null`.
- **There is no external event source.** Nothing outside the founder's typed command, the ingress's
  own echo, and a manual SQL call can put an event into `phase_c_event_outbox`. "Autonomous event
  ingress" has no autonomous input.
- **The handoff object is never created by the autonomous path.** No routine and no application file
  calls `fn_phase_c_handoff_open` or `fn_phase_c_handoff_decide`, so SLA `due_at`, packet
  validation, rejection specificity and the `accountable_until_accept` transfer never run outside a
  hand-written statement. Gate 5's multi-department result rests on a hand-driven call.
- Six of the eight live runs carry `business_object_id = 'outbox:<id>'` — the path names its
  business object after its own plumbing, because the command router's payload has none.

---

### FAIL 6 — CHECK A: one founder command, two accountable tasks, one self-loop, and a cancelled command whose work is still queued

A genuine session was minted for `management@quotesdone.com`
(sub `1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14`). `POST {action:'founder_command'}` → **HTTP 200**,
command **252**.

**Counts immediately after submission:**

```
messages +1  commands +1  plans +1  tasks +4  traces +5  outbox +1  audit +1
approvals 0  runs 0  step_runs 0  attempts 0  llm_attempts 0  cost 0  notifications 0
```

**Counts after the one-minute outbox worker ran:**

```
tasks +1  runs +1  step_runs +1  traces +3  outbox +1  attempts +2  audit +1
approvals 0  notifications 0  founder_alerts 0  llm_attempts 0  cost 0  ai_cost_log 0
```

| Requirement | Result |
|---|---|
| one command | PASS — 252 |
| one command plan | PASS |
| expected initial task count | PASS — 4 (tasks 922–925) |
| one canonical workflow run | PASS — run 136 only |
| **no second task set after the worker runs** | **FAIL** — task **926** at 18:36:00 |
| no duplicate workflow run | PASS |
| no duplicate notification | PASS — both counters +0 |
| **no event self-loop** | **FAIL** — outbox 317 = `EV-W20-STARTED` again |
| correct workflow and accountable role | PASS — W20 / `marketing_director` / owner `chief_of_staff` |
| **complete root and child traces** | **FAIL** — see FAIL 7 |
| readback through the Command Center | PARTIAL — 200 on all three; task 926 absent |

**The duplicate effect.** Command 252 produced task **922** (`cmd:252:primary`,
`marketing_director`) at 18:35:33 and, one minute later through its own event, task **926**
(`run:136:step:W20-S01`, `marketing_director`) at 18:36:00. `founder_command_thread(252)` returns
922–925 and **does not mention 926**, because 926 carries `command_id = null`. The founder's thread
cannot see the work his command created. Already in production three times: 227 → 785–788 + 794;
223 → 789–792 + 795; 252 → 922–925 + 926.

**Cancellation does not propagate.** `founder_command` **227** is `cancelled`
(`closed_at 10:50:13`) and its four command tasks are cancelled. Its derived run **96** is still
`queued` and its task **794** (`marketing_director`) is still `queued`. By contrast command 222 did
propagate. The compensation reaches the command plan and stops at the event boundary.

Idempotency held: replaying the identical request with the same key returned command 252,
`duplicate: true`, zero delta on every counter.

---

### FAIL 7 — CHECK C: seven open step runs have no trace, and the invariant counts only the completed one

`phase_c_workflow_step_run` holds 8 rows. **Seven are `active` and all seven have `trace_id = NULL`**
(35, 36, 37, 38, 41, 42, 54) — including step run 54, created during this audit at 18:36:00, so the
producer is still emitting trace-less step runs. `TRACE-STEP` policy: `trace_required = YES`,
`completed_without_trace_allowed = NO`.

The corrected invariant reads `completed_step_runs_without_trace = "0 of 1", ok`. A denominator was
added; the population filter `where state = 'completed'` was not removed, so the seven failing rows
are outside the only check that could see them.

**There is no trace guard on `phase_c_workflow_step_run` at all** — zero non-internal triggers.
Proven: a step run was inserted `active` with `trace_id = NULL` and driven to `completed` with no
refusal.

Check C's required numbers, measured:

| Required | Measured |
|---|---|
| trace-required objects with no trace = 0 | tasks 0 of 32, runs 0 of 8, outbox 0 of 14, **step runs 7** |
| **open trace-required objects with no active trace = 0** | **7** |
| **completed trace-required objects with incomplete trace = 0** | **12** |

The twelve: 8 cancelled tasks (643–646, 756–759) and 1 accepted handoff whose traces are still
`open`, and 3 cancelled workflow runs (91, 92, 93) whose traces still say `queued`. No invariant
checks that a run or handoff agrees with its trace — `commands_ahead_of_their_trace` exists only for
`founder_command`.

Four further trace defects, each measured:

- **Ten `TRACE-TASK` rows name no task.** `task_id = NULL`, `subject_ref` set to an idempotency-key
  string. `a00_phase_c_task_trace_guard` is BEFORE INSERT, so it writes its trace before the insert
  is refused by the key collision. Trace 827 was created this way during this audit.
- **Seven traces report `status = 'sealed'` while `sealed_at` is NULL**, and
  `fn_phase_c_trace_append_only` reads `sealed_at` — so evidence presented as sealed is rewritable
  in place. Proven by an aborted-transaction update.
- **An untraced `founder_command` can be INSERTED at any late state**: the guard is BEFORE UPDATE
  only, and `commands_ahead_of_their_trace` uses an inner join that drops NULL `trace_id`. A command
  inserted at `tasks_created` with `trace_id = NULL` was accepted and was invisible to both checks.
- **`TRACE-SYSTEM-EXECUTION` was not weakened, and has never been satisfied.** 656 components are
  scoped to it, 609 state-changing, `trace_required = YES`. Traces ever written under it: **0**.
  182 scheduled executions in the last two hours produced none. No invariant measures it.
- Nine task traces were back-filled 100–1,467 seconds after their task **without** the
  `retrofitted` label, so they read as contemporaneous while the 8 honest retrofits are labelled.
- `superseded_by` is NULL on all 66 traces — the supersede mechanism has never fired — leaving 14
  open task traces that no object points at and no code path can close.

---

### FAIL 8 — CONNECTED is still a claim. The derivation reads no runtime table

`fn_phase_c_event_binding_status` is a **registry-name predicate wearing a runtime-evidence name**:

- `prosrc like '%from public.phase_c_event_outbox%'` → **false**
- `prosrc like '%from public.phase_c_event_delivery_attempt%'` → **false**

…yet every CONNECTED branch returns an evidence string ending *"evidence
phase_c_event_delivery_attempt"* — citing two tables the function never queries.

- **283 of the 287 rows it labels CONNECTED have never been emitted.** Only 4 distinct event ids
  appear in `phase_c_event_outbox`.
- The `.started` branch is **a condition that cannot NOT return CONNECTED**: it assigns
  `v_has_producer := true; v_has_consumer := true` as constants and never reads either variable.
- **96 of the 257 CONNECTED step bindings are terminal steps with zero `phase_b_handoff` rows**, so
  the evidence string "hands the successor step to its accountable owner through `phase_b_handoff`"
  describes a handoff that cannot occur. Proven by execution: `W08-S04` returned `handled=true`,
  `downstream_ref='terminal_step:W08-S04'`, tasks created **0**.
- **All 137 steps in `PHASE_C_DEFERRED_PHASE_D_REGISTER.csv` have their `*.completed` event stored
  as CONNECTED** — the same vocabulary carrying opposite verdicts at step level and event level,
  with nothing keeping the two registers in step.

The guard trigger does refuse a hand-written value, and the stored values do match the derivation.
Both are true and neither rescues the gate: the derivation itself is the defect.

---

### FAIL 9 — CHECK B: components the registry calls "deployed and unreachable" are reachable, and two are live

For the 221 `DEFERRED_RUNTIME_IMPLEMENTATION` components, assigned by measurement rather than by the
registry:

| Bucket | Count |
|---|---|
| unreachable and safely deferred | see note |
| callable but access-controlled | see note |
| publicly / authenticated reachable | **≥ 15** |
| **unexpectedly active** | **≥ 2, both state-changing** |

**Unexpectedly active — each a failure on its own:**

- **`fn_enforce_rls_on_new_tables`** is marked inactive with "no trigger". It is a live, **ENABLED
  event trigger that fires on every DDL statement in the database** and mutates state. Proven by
  execution.
- **`pdpl_request`** is deployed with `verify_jwt = false`, has **no authentication of any kind**,
  holds the service-role key, and **INSERTs a row and fires a founder alert for any anonymous caller
  on the internet** — while the registry calls it inactive and safely deferred.

**Reachable, contradicting the registry:**

- 12 edge functions are recorded as "deployed and unreachable" while the *same rows* record them as
  reachable over HTTP without a JWT; 6 of the 12 change state, including `refund_flow`,
  `pdpl_request` and `qa_api`.
- Three deferred functions return HTTP 200 to a fully anonymous caller holding only the public anon
  key; two are SECURITY DEFINER and return real business data, the third enumerates 40 internal
  function names.
- The `external_entry` column measures the wrong subject: all 206 deferred database rows assert
  `external_entry = 'no'` while **106 carry an EXECUTE grant to `anon`** and are on the PostgREST
  RPC surface.
- Two "inactive, no caller" functions are compiled into live views and execute on every SELECT.
- `hook_password_verification_attempt` holds a GRANT EXECUTE to `supabase_auth_admin`, which exists
  for exactly one purpose.

**And the count is overstated:** 91 of the 206 deferred database functions — 41% — are pgvector and
pg_trgm extension internals that were never QuotesDone components. The evidence for
`edge:kb_corpus_import` reads "no caller in repo, database or cron" while three checked-in scripts
POST to its production URL; the sweep did not cover `scripts/**`. The classification is not
reproducible: the generator its own header cites does not exist in the repository.

---

### FAIL 10 — CHECK F: there IS a general founder approval inbox, and a founder refund decision is not immutable

- **A general founder approval inbox exists and is browser-reachable, carrying 10 non-refund kinds.**
  The claims "there is NO general founder approval inbox" and "only a specific refund decision
  reaches him" are both contradicted.
- **A recorded founder refund decision is neither immutable nor undeletable.** The approval side is
  enforced — a non-refund founder approval is refused `23514`, a refund decision by a non-founder is
  refused `28000`, executor = reconciler is refused `23514`, all confirmed by forcing each guard to
  refuse and to accept. The immutability side does not exist.
- The estate's own instrument, `v_phase_c_what_reaches_the_founder`, names itself the census of what
  reaches the founder and **omits the founder queue entirely**, so it reports 0 non-refund founder
  items while a 10-kind non-refund queue is wired to the dashboard.
- `fn_founder_command_clarify` routes `REFUND_APPROVAL` and creates tasks but, unlike
  `fn_founder_command_submit`, never inserts the `founder_approval_request` row — a refund reached
  through a clarification has no approval request for a decision to reference.

---

### FAIL 11 — CHECK G: `ai_gateway` fails OPEN when it cannot read its gate

Everything the correction claims about `ai_health`, `resend_inbound` and `cost_snapshot` is
confirmed on the deployed bodies. What is not confirmed is the sentence *"all four treat a gate they
cannot read as closed."*

**`ai_gateway` — the estate's largest door to OpenRouter — fails open on the deployed code.**

Two further **deployed** doors to paid inference providers consult no gate at all; "a repo-wide
search finds no fifth" holds only if "paid provider" is narrowed to `openrouter.ai`.

`openrouter_routes_open` reports GREEN in both states that mean the founder's hold is gone — an
empty route table, and `open_until` set to NULL, which is literally the release command written in
`opened_reason`. A hold row exists for `model_id = 'none'` that `fn_llm_preflight` can never honour.

**The zero-cost outcome itself held throughout this audit**, measured on both ledgers from the PR
#426 merge (11:11 UTC) to 19:05 UTC:

| Measure | Value |
|---|---|
| OpenRouter HTTP requests | **0** |
| paid inference attempts (`llm_attempt`) | **0** |
| paid inference cost | **USD 0.00** / AED 0.00 |
| `ai_cost_log` rows | **0** |
| scheduled `ai_health` runs recording `skipped_due_to_zero_cost_mode` | **30 of 30** |
| `llm_route_health` | all routes held to 2126-08-15; founder's hold intact |

Cron 102 `ai_health_15min` remains **active** and ran 8 times in the last two hours, every one
logging *"ai_health made NO request to any paid provider"*. The gate fails on the code path, not on
the outcome.

---

### FAIL 12 — CHECK E and gate 9: the clarification the founder cannot answer

- **`founderCommandClarify` has zero callers.** The RPC and the `os_api` action exist and work; there
  is no control in the OS that reaches them. Typing the answer into the console creates a **second
  command**, defeating the "one command id kept" property the RPC does honour.
- **The clarification path has a 4-outcome allow-list while the registry has 11 outcomes**, so 9 of
  27 rules can never be resolved by answering — the founder is asked the same question forever for
  work the submit path routes without hesitation.
- `clarification_required_has_an_exit` measures the transition table, not whether the founder can
  traverse the exit. It is green while there is no control to answer and while 9 of 27 rules loop.

`clarification_required → cancelled` was genuinely added and cancellation genuinely works.

---

### FAIL 13 — Two of the four `unclassified_*` invariants still carry the exact defect the correction was written to fix, and the same migration made them permanently unfireable

`unclassified_db_functions_and_triggers` and `unclassified_cron_jobs` still test
`classification = ''` (live `fn_phase_c_invariants` lines 203–210). `phase_c_35` added
`phase_c_component_classification_ck`, whose 17-literal allow-list **does not include the empty
string** — proven by an aborted-transaction probe that was refused by the constraint.

`classification = ''` is now unsatisfiable. Both checks report 0 forever and can never fire.

Two more, each proven by aborted transaction:

- An **active** deployed database function carrying `NO_CALLER_UNCLASSIFIED` breaks **zero**
  invariants — the corrected `unclassified_components` carries a `mutates_state` term the
  edge-function version does not.
- Flipping a no-caller state-changing component back to `active` fails **zero** invariants. The
  document's rule *"an active state-changing component with no caller evidence may not remain
  active"* is prose, not a guard.

The measurement generator `scripts/phase_c/final_measurements.mjs:39` still counts
`classification = ''`, so regenerating the acceptance evidence would print `unclassified: 0`
regardless of what the table holds.

---

## The one gate that passes, and why it survives scrutiny

**Gate 3 — founder-command event/workflow identity.** The hard-coded `EV-W01-STARTED` / `ceo`
literal is gone from `fn_founder_command_submit`. Resolution is data-driven: driven across the
registry, W20 → `EV-W20-STARTED` → `marketing_director`, W05 → `EV-W05-STARTED` →
`rfq_qualification_manager`, and an unregistered workflow produces **no** event rather than a
plausible one. No workflow's start event routes to the CEO. Confirmed on a live authenticated HTTPS
request in this audit.

One correction to the correction's own account, stated because it matters for the next reader:
`phase_c_workflow_binding` **has no `start_event` column** and `phase_c_event_binding` **has no
`accountable_role_id` column`. Resolution actually reads `public.phase_b_event`, and the outbox
column named `accountable_role_id` is filled from that event's `primary_consumer_role_id` — the
accountable and the consumer are the same value by construction, not two independent facts. The
behaviour is right; the documented mechanism is not the one in the code.

---

## What this audit changed in production

Disclosed in full. The instruction permitted safe canary records.

| Object | State now |
|---|---|
| `founder_command_message` / `founder_command` **252** | `tasks_created`, open, root trace 812 |
| `phase_c_task` **922, 923, 924, 925** | `queued` — the command's four plan tasks |
| `phase_c_event_outbox` **316** | `delivered` — `EV-W20-STARTED`, W20, `marketing_director` |
| `phase_c_event_outbox` **317** | `delivered` — the self-emission described in FAIL 2 |
| `phase_c_workflow_run` **136** | `queued`, W20, `marketing_director` |
| `phase_c_workflow_step_run` **54** | `active`, `trace_id NULL` |
| `phase_c_task` **926** | `queued`, `marketing_director` — the duplicate effect in FAIL 6 |
| `phase_c_trace` **812–818, 827** | 812 root, 813–816 children, 817 run, 818 task, 827 orphan |
| `phase_c_event_delivery_attempt` **66, 67** | both `ok` |

Nothing was cancelled or cleaned up, because doing so would have altered the evidence and would have
been a fix. Everything else in this audit ran inside transactions ending in `raise exception` and
left no rows; rollback was re-verified after each. No Phase A object, Phase B object, workflow
ownership, reporting line, role responsibility, overlay authority or founder boundary was modified —
`fn_phase_a_baseline_drift()`, `fn_phase_b_baseline_drift()`, `fn_phase_c_baseline_drift()` and
`fn_phase_c_reporting_map_drift()` all returned **0 rows** after the work.

---

## Boundaries of this audit

Said plainly, so no reader takes a wider claim than the evidence supports.

- Everything above was measured against live `htdblwldjkcgjvmqkbeh` on 2026-08-16 between 18:27 and
  19:05 UTC. Nothing was inferred from a document.
- The unauthenticated-reachability finding (FAIL 1) was proven on a **read** action
  (`founder_command_inbox`, HTTP 200 as `build-mode@quotesdone.local` with no headers). I did **not**
  submit an unauthenticated founder command; the write path's use of the same identity was
  established by reading `os_api`'s deployed source, not by executing it.
- Bucket totals in FAIL 9 are lower bounds. Every component named individually was proven reachable
  by measurement; the four-bucket split for all 221 is in the agent record, and the two
  "unexpectedly active" and 15 "publicly reachable" were each verified directly.
- `TRACE-SYSTEM-EXECUTION` coverage was established by showing the policy requires a trace, that 656
  components are scoped to it, and that the table has held zero rows under it for its whole life.
  Every scheduled execution was not enumerated against every component id.
- Gate 12's PASS on the three named instruments is real; the FAIL is that the instruments do not
  cover the drift that exists. I did not attempt a full live→file reconciliation of all 439 routines.
- Zero paid inference: measured on `llm_attempt` and `ai_cost_log`, both zero for the window. No
  edge function performing inference was invoked by this audit.

---

# PHASE_C_FINAL_ACCEPTANCE_FAIL

Failed gates: **1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12.** Passing: **3**.
Failed adversarial checks: **A, B, C, D, E, F, G, H.**

Phase D was not begun. No finding was corrected.
