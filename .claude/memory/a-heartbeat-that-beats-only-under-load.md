---
name: a-heartbeat-that-beats-only-under-load
description: Skipping a periodic call when there is no work destroys the cadence a silence detector needs
metadata:
  type: reference
---

`outboxTick` in `resilience_ping` counted the queue and returned early when nothing was pending.
`fn_it_detect`'s `run_silent` learns each subject's cadence from `agent_runs` (it merges `fn:x` and
`x`), so a `send_outbox` that is only CALLED when there is mail has no cadence, and a quiet queue
became indistinguishable from a dead sender. It paged the founder three times in four hours.

**Why:** the loop is self-feeding — quiet queue → no call → detector fires → the ALERT itself
queues a notification → the next tick finds it pending → the sender runs → the finding resolves →
quiet again → it fires again. The only thing keeping the sender alive was the alarm about it.

**How to apply:** a periodic worker whose silence is monitored must be invoked on the schedule, not
on demand. A no-op invocation is cheap; a cadence that only exists under load is not a cadence.
Guard it in the check by asserting there is no `return` before the call. Do NOT fix this by
loosening the detector — the detector was right, the caller was wrong.
Family: [[a-guard-that-fires-when-the-system-works]], [[the-outbox-had-no-heartbeat]],
[[a-watcher-reading-a-name-nothing-writes]].
