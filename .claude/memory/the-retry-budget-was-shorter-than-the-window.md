---
name: the-retry-budget-was-shorter-than-the-window
description: "Management-API 429s that look like product failures — serialise the suite first, then check whether the retry budget is shorter than the throttle window before believing any red."
metadata: 
  node_type: memory
  type: project
  originSessionId: d089c73b-6b45-4e66-aa23-4b1eefd1aff0
  modified: 2026-08-17T21:49:39.465Z
---

17 Aug 2026, measured across three full runs of `npm test` against `htdblwldjkcgjvmqkbeh`:

- **19 failures, 10 of them `429 ThrottlerException`** — a *different* ten each run, so the failing
  set was non-deterministic and none of the ten was a product defect.
- `run.mjs` spawned one `node --test` with the default one-worker-per-CPU. Adding
  `--test-concurrency=1` took it to **9 failures, 1 of them 429**.
- The last one was not concurrency. `workflow_ownership_alignment.test.mjs` already retried five
  times at `1500 * 2**n` = 1.5+3+6+12+24 = **46.5s**, and the measured failure took **47.5s**: it
  spent every attempt and the window still had not opened. Eight attempts capped at 20s (~102s)
  cleared it. **Final: 287 tests, 279 pass, 8 fail, 0 429s.**

The cap matters as much as the count — unbounded doubling reaches four minutes on one query and
reads as a hang, which is a worse failure than the one being fixed.

**Why:** four separate files already carried their own 429 retry and failed anyway. That is the
signal that the problem is above the retry loop, not inside it.

**How to apply:** on a red suite full of production assertions, before diagnosing anything —
`grep -c ThrottlerException`. If it is non-zero, the failing set is noise until the suite is
serialised. Then compare each surviving 429's wall-clock against its own retry budget; if they
match, the budget is the defect. Extends [[production-429-during-the-end-of-session-sweep]], which
said re-run the file alone — that works, but it hides the fact that the budget itself is undersized.

Related: [[a-check-held-open-by-pre-fix-rows]], [[group-per-class-not-in-aggregate]].
