---
name: deactivation-is-not-death
description: "Before calling anything dead code, count its prior runs — 18 cron jobs looked dead and had run up to 21,563 times before being switched off on one date."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: da613f58-5cf3-4795-ab24-f89cb598e1b2
  modified: 2026-08-15T08:24:29.590Z
---

15 Aug 2026, classifying 719 current execution paths for Phase B. Nineteen cron jobs were
`active = false`. The obvious verdict was `DEAD_CODE`.

Measured before writing it: eighteen of the nineteen had run before — `site_autodeploy` **21,563
times**, `auto_deploy` 10,782 — and every one of the eighteen stopped on the **same date,
2026-08-02**. That is not code that never worked. That is a deliberate switch-off, all at once,
by someone. Only `supplier_exception_sweep_daily` (0 runs, ever) was genuinely unproven.

**Why:** `active = false` is the state of a job that was turned off AND the state of a job that
never worked, and the flag alone cannot separate them. Calling the first one dead invites the next
phase to delete working machinery — and the same-date cluster is the tell that a human did it on
purpose, so deleting it silently reverses a decision.

**How to apply:** never classify from a status flag alone. Add `select count(*), max(start_time)
from cron.job_run_details where jobid = …` (or the equivalent durable record) and split the
population three ways: never ran → unproven; ran then stopped → **deactivated**, with the date and
the run count in the note; running → live. If several stopped on one date, say so — that is
someone's decision, and Phase C's job is to ask whether to resume it, not to tidy it away.

Same shape as [[zero-cannot-tell-a-dead-guard-from-an-idle-system]] and
[[a-check-held-open-by-pre-fix-rows]]: the number in front of you is not the history behind it.
