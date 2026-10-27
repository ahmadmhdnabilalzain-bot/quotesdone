---
name: the-outbox-had-no-heartbeat
description: Queued mail only left the estate during an outage; a pending row looks identical to a stuck one
metadata:
  type: project
---

Until 9 Sep 2026 the only `send_outbox` call in `resilience_ping` sat inside the
scheduler-is-down branch, under `if (healthy) return`. On a working day the 15-minute heartbeat
never drained the mail queue — a notification left only if its creator pushed it itself. Fixed by
`outboxTick()` running before the healthy early-return.

**Why:** a stuck row sits at `status='pending'` with `last_error` NULL, identical to a freshly
queued row, so the data never shows it. Mail that did go out fast (avg 1.7 min) went out because
its creator pushed it — which disguises the gap until something queues without pushing.

**How to apply:** when a queue has a shared drain, put the drain on the thing with a heartbeat, not
in each writer — the N+1th writer forgets. Guard it with BOTH a symptom test (nothing pending >30
min) and a mechanism test (the drain is called before the early return): the symptom passes on a
quiet estate, and quiet is the normal case. Check:
`scripts/checks/the_outbox_is_drained_by_something_with_a_heartbeat.test.mjs`.
Related: [[a-status-column-is-not-a-delivery-record]], [[finished-capability-with-no-entry-point]].
