# Phase C execution kernel — builder closure, 17 Aug 2026

Measured engineering completion only. No independent audit was run, no certification, no Phase D.
Every number was read out of production `htdblwldjkcgjvmqkbeh` in the session that produced it.

---

## SOURCE INVENTORY — met

| | |
|---|---|
| discovered sources | **67** |
| active | **54** |
| inactive | **13** |
| NEW_WORK_REQUEST | **28** |
| EXISTING_WORKFLOW_SIGNAL | **14** |
| READ_ONLY_MONITOR | **22** |
| RETIRE_OR_HISTORICAL | **3** |
| **active bypassing kernel** | **0** |
| **active with no adapter/disposition** | **0** |

67 is the measured inventory and supersedes the earlier estimate of 52. Nothing was manipulated to
reach either number — the register is the strict superset of every population definition this
estate supports, and `fn_kernel_cutover_measure` recomputes it from the catalogue on every call.

`fn_kernel_cutover_measure`: **0 failing of 9**, with no expected numerator anywhere in the
function. Verdicts: **CUT_OVER 32, READ_ONLY 19, RETIRED_OR_INACTIVE 16**.

Every source names, in `disposition_evidence`, the routine that discharges its disposition — and
the measurement **verifies** it: the named routine must exist and its deployed body must call one
of the three kernel doors. A registry-only claim counts as bypassing however the status column
reads. Coverage claims with nothing behind them: **0**.

`docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv` — 67 rows, every column §1 requires
including `final_evidence`.

### Two of K10's mappings were wrong, and wiring them as recorded would have manufactured runs

- `edge:inbound_email` was mapped to `customer.inquiry_submitted → W05`. It handles **supplier**
  correspondence: it matches or creates a `leads` row with `business_role = 'supplier'`. Routed to
  W05 it would have opened a customer-inquiry run for every supplier email the company receives.
  Corrected to W09, cut over on `inbound_messages WHERE created_new_lead` — the trigger reads the
  decision the function already made.
- `edge:inquiry_intake` creates a **draft**, not an inquiry. `customer_api` promotes a draft marked
  `ready` into `public.inquiries` and marks it `consumed`; that insert already reaches the kernel.
  Emitting here as well would open two W05 runs per customer request — and `inquiry:{inquiry_id}`
  cannot resolve from a draft, so every submission would have been refused anyway.

### Three sources create no business work at all, measured against the deployed source

`edge:attach_photos` writes **no table**. `edge:supplier_onboard`'s only write is one
`agent_actions` row, `status 'logged'`, in a try/catch whose own comment reads *"telemetry is not
the product"*. `edge:resend_inbound` books expenses and writes none of the eight protected tables —
not a bypass, but it **owes a Phase B workflow**, which is more useful than routing a receipt to
W07 as a customer document.

---

## GOAL CASCADE — met, resolved under §3 option B

| | |
|---|---|
| final classification | **D RETIRE_OR_HISTORICAL** |
| final handler | business side effect **disabled**; behaviour recorded as owed |
| incorrect W02 target-miss starts | **0** |

`trg_goal_cascade` fires on `old.active is true and new.active is false` — a goal being **retired**,
which is not a missed target. Option A was rejected because nothing owns goal retirement: W01 starts
from a founder mandate and no run is ever opened for a goal. Routing it to W02 would open a
corrective-management run every time the founder tidies up a goal he no longer wants.

Only the `org_tasks` re-plan **insert** was the bypass. Objective supersession is the goal's own
record staying consistent, and `fn_emit_event` does not write `phase_c_event_outbox` (measured).
That one statement is disabled and left in the body **commented**, so a reader sees what was removed
rather than inferring it from a gap. `org_tasks` held zero such rows, so nothing that works today
stopped. The owed behaviour is in `phase_b_phase_c_wiring_gap`.

---

## KERNEL WRITE CONTROL — met, and one defect of mine found by proving it

| | |
|---|---|
| accepted direct writes outside kernel | **0** |
| accepted canonical kernel writes | **run created, 1 step run, 1 task** |

`scripts/checks/kernel_write_guard_both_directions.test.mjs` — **7 of 7**, each case under
`set local role`, inside transactions that always abort:

```
anon direct write ............... refused (permission denied for table)
authenticated direct write ...... refused (permission denied for table)
service_role direct write ....... refused by the guard, call stack in the error
service_role + a stated reason .. refused
canonical kernel write .......... accepted: run=473 step_runs=1 tasks=1
audited maintenance door ........ permitted for the owner, audit rows=1
probe rows surviving ............ 0
```

**The fourth line said ACCEPTED until K37.** `fn_kernel_write_guard` was SECURITY DEFINER, so
`current_user` inside it was always the owner and the maintenance door's owner check compared the
owner against itself. Any Edge Function holding the service key could write
`phase_c_workflow_run`, `phase_c_task`, the trigger inbox or the founder's refund ledger by adding
one `set local kernel.maintenance_reason = 'anything'`. The guard is now SECURITY INVOKER; the one
privileged act moved into a helper called only after the owner check passes.

Testing only as `postgres` — which owns the tables — would have proved the guard against the one
identity it is least meant to stop, and would have passed.

---

## LEGACY RETIREMENT — met

| | |
|---|---|
| old workflow-start callers | **0** |
| old step-progression callers | **0** |
| old task-creation callers | **0** |
| old outbox-worker callers | **0** |
| bypass grants | **0** |

`fn_kernel_retired_path_state` 0 failing of 5; `fn_kernel_retired_grant_state` 0 failing of 3.

All eight retired paths were executable by `service_role` — the role every Edge Function holds.
Checked first (zero database callers beyond the kernel's own; nothing in `supabase/functions` or
`src` names any of them), then revoked from `public, anon, authenticated, service_role`.

One was not merely untidy. **`fn_phase_c_outbox_settle` was recorded READ_ONLY_HISTORICAL and was
still UPDATING `phase_c_event_outbox`.** The guard suite had been finding it sideways for weeks —
two cases failing with `invalid input syntax for type timestamp with time zone`, which is a routine
that *ran and got as far as writing*, not one that refused. Its body now refuses, which is what its
disposition already claimed.

---

## COMMAND CENTER — met

Founder command path canonical; same-thread clarification caller present; task readback complete;
general founder approval paths **0**; refund-only approval path **present**.
`fn_kernel_founder_approval_state`: 0 failing of 5.

## FOUNDER ALERTS — met

| | |
|---|---|
| informational critical alerts | **1** (`notifications.type = 'agent_escalation'`) |
| non-refund approval requests | **0** (`founder_approval_request` is empty) |
| routine work blocked on founder | **0** (`org_tasks.needs_founder` open: 0) |

The K21 page path writes a `notifications` row and emits a W29 incident to the kernel. It creates no
`founder_approval_request`, sets no `needs_founder`, and blocks nothing. Only
`fn_founder_command_submit` inserts an approval request, and that path is refund-only by check.

---

## WORKFLOW — met

workflows without closure path **0 of 30**; unresolved successor owners **0**; overlay-owned tasks
**0**; step owners unresolved **0**; cycles **0**.

## TRACE — met, history reported separately

active state-changing components without trace instrumentation **0**; new required executions
without trace **0**; current active orphan traces **0**.
`fn_kernel_system_trace_state` 0 of 13; `fn_kernel_historical_register_state` 0 of 9.

Preserved historical exceptions, never presented as compliance: STATE_TRACE_MISMATCH **22**,
ORPHAN_TRACE **7**, DUPLICATE_EFFECT **6**, VALID_HISTORICAL_RECORD **3**, retrofit entries **31**.

## SOURCE OF TRUTH — met

| | |
|---|---|
| repository → production drift | **0** |
| production → repository drift | **0** |
| conflicting current definitions | **0** |
| uncommitted application DDL | **0** |

`sql_files_match_live`: **520 routines, 0 drifted, 0 missing**. PR #428 was merged to main before
any new change was deployed. `scripts/sql/the_founder_has_a_name.sql` had been applied to production
in an earlier session and never committed — it is now committed as the record of a change that
landed.

## GUARDS — met

**injected defects refused: 55/55**; stale message assertions **0**; row counts unchanged after
every aborted injection.

The brief's premise was only partly right — the nine were four different things:

- **3** genuinely stale messages. Now assert **SQLSTATE + the raising guard**: `28000` +
  `fn_phase_c_require_founder`, `23514` + `fn_phase_c_refund_decision_guard`, `23514` +
  `fn_kernel_workflow_run_trace_guard`.
- **2** tested a path K13 **retired**. Refusing every caller is stricter than refusing the wrong
  employee; they now assert the retirement.
- **2** encoded a **pre-kernel expectation**: a founder command created 3 tasks, and
  `fn_kernel_workflow_start` creates exactly **one** per step run.
- **2** were `fn_phase_c_outbox_settle`, fixed by fixing it.

The VALUE_CASE and SEQ_CASE matchers also had to learn that a case may assert a returned value **or
a refusal** — the guards stopped answering and started refusing, which is the direction you want.

## COST — met

OpenRouter HTTP requests **0**; paid inference requests **0**; paid inference attempts **0**; paid
inference cost **USD 0.00**; no provider fallback key. `llm_calls` this session: **0**. All 8
provider routes held open-circuit.

## BASELINES — met

Phase A drift **0**; effective Phase B drift after PBCR-001 **0**.

---

## Deferred, per §9 — not Phase C blockers

- **Pack scorecard** — `DEFERRED_TO_KNOWLEDGE_PHASE`. Not run; no provider credits consumed.
- **Row #3 backlog** — belongs to its owning UI/operations workstream. The five items that could
  block Phase C were checked and none does: founder command submission, same-thread clarification,
  cancellation, task readback and refund-only approval are all covered by
  `fn_kernel_founder_approval_state` (0 of 5) and the Command Center readback. The general scorer
  was not re-run, and nothing here rests on it.

---

## Verdict

Every required result in §10 is met and measured.

`PHASE_C_EXECUTION_KERNEL_READY_FOR_ONE_FINAL_ACCEPTANCE`
