# Phase C — Idempotency, Retry, Compensation and Output Validation

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026. Every claim below has an injected case behind it
in `scripts/checks/phase_c_guards_reject_injected_defects.test.mjs`.

## Every state-changing entry point has an explicit idempotency scope

| entry point | scope | enforced by |
| --- | --- | --- |
| founder command | client idempotency key | `founder_command_message_idem_uk` |
| task creation | `cmd:<id>:primary` / `cmd:<id>:child:<owner>` / `task:<md5>` | `phase_c_task_idem_uk` |
| workflow start | `workflow:object:version` | `phase_c_workflow_run_dedupe_uk` |
| step advance | `<frozen idempotency_scope>|run|step|attempt` | `phase_c_step_run_idem_uk` |
| event emit | `(event_id, dedupe_value)` | `phase_c_event_outbox_dedupe_uk` |

Component-level strategies are recorded for all 1,799 inventoried components in
`PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv` — schedule tick for cron, request+business key for edge
functions, row+operation for triggers, transaction+argument hash for routines.

## A duplicate returns the same thing, never a second one

| case | result |
| --- | --- |
| same founder command submitted twice with one key | **same command id**, **1** message row, **3** tasks |
| same workflow started twice for one object | **same run id**, **1** run |
| same event emitted twice with one dedupe value | **same outbox id** |
| same task idempotency key inserted twice | refused by unique index |
| same client key on a second message | refused by unique index |

`fn_phase_c_outbox_emit` uses `on conflict do nothing` and then **reads the existing row back**. It
does not return null on the duplicate path — returning null there would make "already emitted"
indistinguishable from "failed to emit", and a caller would have to guess.

## A retry preserves the first attempt

Measured on a real step, twice advanced:

```
attempts=1,2 | first_preserved=true | rows=2
```

Two rows, not one updated row. The second points at the **first** attempt — not the immediately
previous one — so a chain of retries all reference the original failure rather than forming a
linked list that has to be walked.

`phase_c_step_run_live_uk` is a **partial** unique index: one live attempt per `(run, step)`,
excluding `completed`, `cancelled`, `failed`, `superseded` and `skipped`. So a retry after a
failure is allowed and a second concurrent live attempt is not.

### The bug that made the first attempt impossible

```sql
v_attempt bigint := 1;
...
select step_run_id, attempt_no into v_prev, v_attempt from ... limit 1;
```

A plpgsql `SELECT INTO` matching **no rows nulls every target** rather than leaving the
initialiser. On the first attempt at any step `attempt_no` became null and the insert failed on
NOT NULL. The attempt number is now derived after the lookup instead of mutating a value the
lookup may have wiped.

This is the same family as "error and empty must not return the same value", in its plpgsql form:
after `SELECT INTO`, *no rows* and *a null value* are indistinguishable unless you check `FOUND` or
coalesce afterwards.

## Delivery: the first failure survives

`phase_c_event_outbox` carries `first_failure` **and** `last_error`. `first_failure` is written once
and never overwritten, so a later success does not erase the fact that the first attempt failed.
Eventual success and first-attempt success are separate facts, and
`phase_c_event_delivery_attempt` holds one row per try.

Backoff is exponential (`2^attempts` minutes, capped), and after five attempts the row goes to
`dead_letter` rather than retrying forever.

### A null downstream record is not success

`fn_phase_c_outbox_settle(outbox_id, ok := true, downstream_ref := '', error := '')` returns
**`retry_wait`**, not `delivered`, and writes the reason:

> *delivery reported ok with no downstream record; not counted as delivered*

Measured. And asserted as an invariant across the whole table:
`delivered_without_downstream_record = 0` — a row may only be `delivered` when a delivery attempt
exists that is `ok` **and** carries a non-empty downstream reference.

That is the concrete form of the contract's rule: *a notification, webhook or task-delivery attempt
is not counted as successful unless the downstream record exists.*

## Compensation and cancellation

- Cancelling a command closes each child task **individually, with its own trace**, recording who
  cancelled it. A bulk `UPDATE` did this silently before and the trace invariant caught it at 4.
- Superseding links `superseded_by` on the command and marks child tasks `superseded`, not
  `cancelled` — the two are different histories and the state model keeps them different.
- A cancellation the state model does not permit is **refused with the reason**, not forced:
  `transition_not_permitted` naming the from-state.
- `org_action_executor` already carries `compensation_action_class`, `reversible`, `risk_tier`,
  `max_attempts`, `timeout_seconds` and `backoff` for 59 action classes. Those are reconciled into
  `PHASE_C_EXECUTOR_ACCOUNTABILITY.csv` (1,176 rows) with the canonical owner attached, and the
  rows where `compensation_action_class` is absent read `none_declared` rather than being left
  blank.

## Output validation

`fn_phase_c_output_validate(contract, output) -> (valid, reason)`, called by
`fn_phase_c_step_advance` before any state is written.

Refused, each with an injected fixture:

| fixture | reason |
| --- | --- |
| `null` | null output is not a successful result |
| a JSON array or scalar | output is `array`, expected an object |
| `{"status":"ok"}` | required fields missing [output] |
| `{"truncated": true, …}` | explicit truncation marker |
| `{"stop_reason":"length", …}` | output-limit marker |
| `{"incomplete": true, …}` | incomplete continuation state |
| output ending in `...` beyond 16 chars | unresolved continuation marker |
| `{"status":"maybe", …}` | status not in the allowed set |

A truncated or invalid consequential output is `failed_incomplete`: **it creates no side effect**.
`fn_phase_c_step_advance` returns the refusal before it writes the step run, so protected business
state is unchanged.

Tested with deterministic fixtures only. No model call is required to prove any of this, which is
the point of the contract requiring it that way.

## Invalid transitions

| model | states | transitions | guard |
| --- | --- | --- | --- |
| workflow | 14 (frozen Phase B) | 35 (frozen Phase B) | `z20_phase_c_workflow_state_guard` |
| task | 11 | 22 | `z20_phase_c_task_state_guard` |
| command | 13 | 24 | `z20_founder_command_state_guard` |

The workflow model is **read from the Phase B tables**, not copied into Phase C, so it cannot drift
from what the founder approved even by accident.

All three injected and refused: `queued → completed` on a workflow run, `queued → completed` on a
task, `tasks_created → received` on a command.

## Duplicate side effects

The invariants that count them, all returning zero on production:

| invariant | value |
| --- | --- |
| duplicate command from same idempotency key | **0** |
| duplicate task idempotency keys | **0** |
| duplicate outbox dedupe values | **0** |
| retry erased the first failure | **0** |
| delivered without downstream record | **0** |
| invalid workflow transitions accepted | **0** (guard) |
| invalid task transitions accepted | **0** (guard) |
