# Phase C — Workflow, Task, Event and Handoff Runtime

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026.

## The component inventory

**1,799 runtime components**, every one classified, every active state-changing one owned.

| type | count | state-changing |
| --- | --- | --- |
| database function/procedure | 1,000 | 407 |
| cron job | 205 | 205 |
| edge function | 202 | 155 |
| database trigger | 189 | 189 |
| state table | 100 | 100 |
| event subscription | 60 | 60 |
| frontend route | 24 | 1 |
| runtime workflow definition | 19 | 19 |

Phase B inventoried 719 of these. The 1,000 database routines are new: Phase B never looked at
them, and they are where the accountability gap actually lived.

| | |
| --- | --- |
| active state-changing components | **1,117** |
| …without an accountable canonical role | **0** |
| …without a canonical system actor | **0** |
| …without a workflow or justified system scope | **0** |
| unclassified components | **0** |
| generic name used as final owner | **0** |
| distinct accountable owners | 52 |

`SYSTEM_SCOPE` (634) and `OUT_OF_SCOPE` (165) are the two **explicit** non-workflow scopes. Both
are stated values, never blanks — the master spec allows "workflow/step **or explicit justified
system scope**", and a blank would not be either.

## Classification

| verdict | count | what it means here |
| --- | --- | --- |
| `CANONICAL_KEEP` | 782 | reachable, owned, no change needed |
| `WIRE_TO_CANONICAL` | 705 | active and state-changing; now bound to a canonical owner and trace policy |
| `NO_CALLER_UNCLASSIFIED` | 286 | nothing in the estate names it |
| `INACTIVE_HISTORICAL` | 18 | switched off, had run before |
| `CANONICAL_BETTER_KEEP` | 7 | a working state machine with run history; the canonical registry maps onto it |
| `REPAIR_BEFORE_REACTIVATION` | 1 | switched off and never ran; unproven |

### The 286 with no caller, and the number that was wrong

The first pass reported **426**. The caller test looked for triggers, cron commands and other
routine bodies — and not for the PostgREST `.rpc('fn_x')` form, which `os_api` alone uses for about
sixty routines. With that form measured the honest figure is 286: **208 database routines** and
**78 edge functions** that nothing in repo, database, cron, another routine or the frontend names.

The same distinction is kept for edge functions and it is why this number differs from Phase B's
64. Three facts are held separately rather than collapsed:

| entry | meaning |
| --- | --- |
| `internal_caller` | something in repo, database or cron invokes it |
| `external_product_entry` | no internal caller, but it is a webhook / OAuth callback / public surface **and** reachable without a JWT |
| `unauthenticated_only` | reachable without a JWT, but no caller and no product surface |
| `none` | no caller and JWT-gated: nothing can reach it today |

"Reachable without a JWT" is **not** the same fact as "is a product entry surface", and treating
them as one is how a count of orphans becomes whatever you want it to be.

None of the 286 is deleted. Each carries an accountable owner and a trace policy; wiring or
retirement is a Phase D decision with the evidence now attached.

### Inactive is not dead

19 components are switched off. **18 had run before** — one 21,563 times — and all 18 stopped on
the same date, 2026-08-02. That is a deliberate deactivation, and Phase C does not undo it:
`INACTIVE_HISTORICAL`, activation state recorded, unchanged. The one job that was switched off
having never run is `REPAIR_BEFORE_REACTIVATION` — unproven, not rubble.

**No activation state was changed by Phase C.** cron jobs 205, active 186 — before and after.

## The workflow runtime

`fn_phase_c_workflow_start(workflow_id, business_object_id, ctx) -> run_id`

- Refuses an unknown workflow (`fail closed`).
- Refuses a workflow whose frozen owner does not resolve to an active canonical role.
- **Idempotent**: the same `(workflow, object, version)` returns the existing run. Measured:
  `true|runs=1`.
- The state machine is read from `phase_b_workflow_state` / `phase_b_workflow_transition` — the
  frozen Phase B model, not a Phase C copy — and `z20_phase_c_workflow_state_guard` refuses a
  transition that is not in it. Injected and refused: `queued → completed`.

### The step advance, and the defect that made it impossible

`fn_phase_c_step_advance(run_id, step_id, actor, body)` is the single door a step moves through.
It resolves the actor, evaluates the gates, checks authority, validates the output, writes the step
run and seals a trace — refusing at the first failure with protected state unchanged.

The first version read `phase_b_workflow_step.founder_gate` and passed it to the gate evaluator as
a gate id. **It is not a gate id.** Measured: all 257 steps carry a `founder_gate` and there are
**19 distinct values, all of them sentences** — "Formal Phase A organizational change requires
founder approval.", "Pricing and commercial model changes remain founder-reserved." So every
advance failed closed on an unknown gate, and no canonical step could ever have moved.

The gate was doing exactly what it should; it was being asked the wrong question. Gates attach by
**scope**: `phase_b_gate.workflow_scope` is `ALL` or a `;`-separated list of workflow ids.
`fn_phase_c_gates_for_step` resolves that, and the founder boundary sentence goes into the trace
where it belongs, enforced through the authority class rather than looked up as an identifier.

This is worth stating plainly because of *how* it was found: the aborted-transaction rehearsal
passed 58/58 invariants and did not see it. A rehearsal creates routines and counts rows. It never
advances a step. **Deploying a routine is not running it.**

### Retry preserves the first failure

A retry opens a **new** step run pointing at the **first** attempt — not the previous one, the
first — so a chain of retries all reference the original failure. Measured:
`attempts=1,2 | first_preserved=true | rows=2`.

A second defect lived here. `v_attempt bigint := 1;` followed by `select … into v_prev, v_attempt`
looks safe and is not: a plpgsql `SELECT INTO` that matches **no rows nulls every target** rather
than leaving the initialiser. On the first attempt at any step `attempt_no` was null and the insert
failed on NOT NULL. The first advance of any step was impossible. The attempt number is now derived
after the lookup instead of mutating a value the lookup may have wiped.

## The task engine

`public.phase_c_task` carries every field master spec §3.4 requires — source, command, workflow,
step, accountable role, manager, department, objective, required inputs, requested output,
acceptance criteria, closure criteria, priority, due date, SLA, dependency, reviewer requirement,
authority class, idempotency key, state, blocker, blocker owner, trace.

`org_tasks` (1,050 rows) is untouched and keeps serving the legacy queue. This is the canonical
task, and it is the one with an owner that must resolve.

Enforced at write time by `z20_phase_c_task_state_guard`:

- an owner that is not an active canonical role → refused;
- an overlay as owner → refused (`z10_phase_c_overlay_not_accountable`);
- a reviewer that is the same **effective** identity as the owner → refused, aliases resolved
  first;
- a transition outside the 11-state / 22-transition model → refused;
- `blocked` with no named blocker → refused.

## The event outbox

**There was no outbox table of any kind before Phase C.** This is new construction, not
reconciliation.

`public.phase_c_event_outbox` — business state and its event are written in the **same
transaction**; delivery is separate, asynchronous and idempotent.

| delivery state | |
| --- | --- |
| `pending` `claimed` `delivered` `retry_wait` `dead_letter` `cancelled` `superseded` | all seven from the contract |

- **Dedupe**: unique index on `(event_id, dedupe_value)`. A duplicate emit returns the **existing**
  row id, never a second one. Measured: `true`.
- **A null downstream record is not success.** `fn_phase_c_outbox_settle` called with `ok=true` and
  an empty downstream ref returns `retry_wait`, not `delivered`, and says why. Measured and
  asserted.
- **The first failure survives a later success**: `first_failure` is written once and never
  overwritten.
- **Dead letter** after 5 attempts, with exponential backoff between retries.
- Every attempt is recorded in `phase_c_event_delivery_attempt`, so eventual success and
  first-attempt success are separate facts.

347 events are bound; each names its producer, consumer, dedupe key, delivery worker, delivery
audit writer and dead-letter path.

## The handoff runtime

161 handoffs bound. `fn_phase_c_handoff_open` / `fn_phase_c_handoff_decide`.

- **The sender stays accountable until the receiver accepts.** A row that flips ownership at OPEN
  is refused by `z30_phase_c_handoff_sender_retains`. Measured across a real accept:
  `before=chief_of_staff → after=strategy_director`.
- **An incomplete packet does not become the receiver's problem.** The packet validator names the
  exact missing items and the handoff is not opened. Measured:
  `false | object_version, output, evidence_refs, requested_action`.
- **A rejection must be specific.** A CHECK refuses `rejected` without a reason, the missing items
  and a return owner. Measured: `true | owner=chief_of_staff | reason=specification absent`.
- **The SLA is parsed properly.** `phase_b_sla_policy.target` is prose — "1 minute", "4 business
  hours", "30 minutes when customer inputs are complete". Taking the digits alone would turn "1
  minute" into one hour. The unit is parsed with the quantity.
- `fn_phase_c_handoff_overdue()` lists open handoffs past due, with hours late, and it feeds the
  founder inbox.

## Step binding: what is connected and what is deferred

| | |
| --- | --- |
| steps bound or classified | **257 / 257** |
| `CONNECTED` — a measured component implements the step's business action | 120 |
| `DEFERRED_RUNTIME_IMPLEMENTATION` | 137 |

A deferral is only acceptable with all four of the master prompt's conditions, and a CHECK
constraint refuses one without them:

1. an **accountable owner** — the frozen Phase B role;
2. a **safe entry boundary** — `fn_phase_c_step_advance`, which refuses an out-of-order or
   unauthorised advance;
3. **no active bypass** — nothing else writes `phase_c_workflow_step_run`;
4. the **exact missing implementation** — the business handler that produces the step's output.

The three workflows with every step deferred are **W03** (customer acquisition, 9/9), **W08**
(supplier-safe payload, 8/8), **W21** (strategic partnership, 8/8) and **W22** (product delivery,
7/7). W21 is the one Phase B recorded as having no runtime implementation at all; it now has a
canonical boundary and an owner, and its business handlers are Phase D.

## `CANONICAL_BETTER_KEEP`

Seven runtime workflow definitions have real run history and are kept as the better
implementation, with the canonical registry mapping onto them rather than a duplicate engine being
built beside them: `customer_registration`, `employee_task`, `improvement_lifecycle`,
`knowledge_lifecycle`, `metric_lifecycle`, `strategic_review`, `supplier_onboarding`.

12 of the 19 runtime workflow definitions still have zero runs, including `rfq_handling` — 18
steps, all gated, 20 assigned employees, 0 runs. Phase C gives them an accountable owner and a
canonical boundary. **It does not claim they work.** First execution is Phase D.
