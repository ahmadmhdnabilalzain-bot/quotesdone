# Phase C correction 4 — the event delivery backbone

**Migrations:** `phase_c_32_event_delivery_backbone.sql`, `phase_c_39_consumer_must_not_reemit.sql`,
`phase_c_41_outbox_carries_its_trace.sql`

## What the audit measured

`phase_c_event_delivery_attempt` had never held a row. Nothing anywhere called
`fn_phase_c_outbox_claim`, no cron job named any `phase_c` object, and the claim function only
marked rows `claimed` and returned them — it dispatched to nothing. One routine in the entire
database emitted anything at all. The queue had a producer and a lock, and no consumer and no clock.

## What was built

`public.fn_phase_c_outbox_deliver(p_limit, p_worker)`:

| Requirement | Implementation |
|---|---|
| Claim safely with row locking | `fn_phase_c_outbox_claim` — `for update skip locked` |
| Two workers cannot claim the same row | `skip locked` plus the `pending`/`retry_wait` → `claimed` status move inside the same statement |
| Record `phase_c_event_delivery_attempt` | one row per try, written **before** the consumer runs, with `worker_id` |
| Preserve first-attempt evidence | `outbox.first_failure = coalesce(first_failure, now())` — a retry cannot overwrite the diagnosis |
| Call the canonical consumer | `fn_phase_c_event_consume(outbox_id)` |
| Create/advance the expected task, workflow or state | `.started` → `fn_phase_c_event_ingress`; `.<step>.completed` → the successor step's owner gets a task through `phase_b_handoff` |
| Record result and result hash | `downstream_ref` and `result_hash = sha256(result::text)` |
| Delivered only after the consumer succeeds | the `delivered` write is in the success branch only |
| Retry only eligible infrastructure failures | SQLSTATE in `40001, 40P01, 55P03, 57014, 53100, 53200, 53300, 08000, 08003, 08006`; exponential backoff, max 5 |
| Dead-letter terminal failures | everything else, immediately |
| Idempotency keys | task keys `run:<run>:step:<step>`; outbox dedupe `ingress:<event>:<object>` / `step:<step_run>` |
| Carry command/event/workflow/trace identities | payload carries them; `fn_phase_c_outbox_emit` resolves `trace_id` from step run → run → command |
| Never interpret null as success | a consumer returning no row, or `handled is null`, is recorded as `'consumer returned no verdict'` and fails |

**Scheduler:** one new cron job, `phase_c_outbox_deliver_1min`, `* * * * *`, calling the function
in-database. No disabled business automation was reactivated — this job did not exist before and it
touches only the Phase C outbox.

## Two defects were introduced during this work, and both are recorded

**Ordering.** The worker went live on a one-minute cron *before* the migration that quarantined the
three pre-fix outbox rows. At 10:28 it delivered all three and opened three W01 workflow runs
accountable to the **CEO**, with tasks for the Chief of Staff, out of three marketing commands. The
increment was rolled back: runs and tasks cancelled with the reason recorded on the row, not
deleted. The consumer now **refuses** any event whose payload names a command that selected a
different workflow, so the order of two migrations can never decide that again.

**Self-feeding queue.** `fn_phase_c_event_ingress` emits, because it is the producer path. Called
from the consumer it re-emitted its own input — outbox rows 239, 240, 241. Dedupe stopped it
becoming a loop, but a queue that feeds itself is not a queue. The consumer now passes
`emit => false`; the producer keeps its emit. Those three rows are superseded with the reason on
them, retained as evidence.

## Measured after

```
outbox emitted     12      claimed 12      delivery attempts 12
delivered          12 ok    dead-letter 0   retry_wait 0
outbox by status   delivered 6, superseded 6
outbox rows without a trace                0 of 12
outbox rows stuck pending over an hour     0
```
