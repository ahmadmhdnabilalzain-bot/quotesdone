---
name: connected-is-a-claim-not-a-measurement
description: "347 event bindings all read connection_status=CONNECTED while one routine emitted and nothing ever consumed — a status column is an assertion someone typed, so count the callers instead."
metadata: 
  node_type: memory
  type: project
  originSessionId: 9f1a5f09-0430-4380-80c9-8676a24ac346
  modified: 2026-08-16T10:00:49.396Z
---

16 Aug 2026, Phase C final audit. `public.phase_c_event_binding` — 347 rows, **every one**
`connection_status = 'CONNECTED'`, each naming an `outbox_writer` and `fn_phase_c_outbox_claim` as its
`delivery_worker`. What was actually true:

- routines calling `fn_phase_c_outbox_emit`: **1** (`fn_founder_command_submit`, with a hard-coded event id)
- rows ever written to `phase_c_event_outbox`: **3**, all still `pending`, `attempts = 0`
- rows ever in `phase_c_event_delivery_attempt`: **0**
- cron jobs naming any `phase_c` object: **0**
- `phase_c_workflow_run` / `step_run` / `handoff_run` before the audit: **0 / 0 / 0**

The step-binding registry was honest in the same database — 137 of 257 read
`DEFERRED_RUNTIME_IMPLEMENTATION`, each with owner, gap and Phase D action. So the vocabulary exists; the event
registry just wasn't held to it.

**Why:** a `connection_status` column is prose someone wrote at build time. It survives unchanged while the
thing it describes is never built, and it reads exactly like evidence on a dashboard.

**How to apply:** never accept a status column as the answer to "is this wired?". Four queries settle it —
who calls the producer (`pg_proc.prosrc ilike '%<emit_fn>%'`), how many rows the queue holds and in what
status, whether the consumer table has ever held a row, and whether any `cron.job` names it. If the consumer
table is empty and no scheduler names the worker, the status is a claim. Sibling of
[[finished-capability-with-no-entry-point]] and [[guarded-by-a-condition-that-cannot-occur]]; the numbers that
certified it clean are [[zero-cannot-tell-a-dead-guard-from-an-idle-system]].
