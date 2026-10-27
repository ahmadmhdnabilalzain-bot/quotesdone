---
name: a-killed-check-leaks-its-fixtures
description: "A check that uses withRun or run.mjs, killed by a shell timeout, leaves its ZZ DEMO rows; give it the time it needs and purge by exact tag."
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T20:20:00.000Z
---

27 Oct 2026 (it_engineer, PR "A harness run that is ended early still leaves no demo row behind"): 10 `withRun`
runs since 26 Oct 19:47Z (`a_supplier_who_ignores_holds_is_warned_then_held`, "probe 857.2") and 2
`scripts/e2e/run.mjs` runs left a ZZ DEMO lead or customer behind. The tell: the run's `rehearsal_window` has
`ended_at >= expires_at`, i.e. it was closed by the 10-minute expiry sweep and **by no process**, so the process
died before its `finally`. The holds check needs **271 s**; run with the Bash tool's default 2-minute timeout, it
is killed mid-run, and a SIGKILL is caught by nothing in-process.

- **Give such a check its time.** Pass a `timeout` of 600000 or run it in the background.
- **What was fixed:** the exit handlers (SIGTERM, SIGINT, crash) now tear the run down before closing its window,
  and `withRun` runs `sweepStaleRuns({ limit: 3 })` at start, as `run.mjs` already did. A run whose every window
  ended over 60 minutes ago is torn down by its exact tag; `founderdemo` is never swept.
- **To remove one leftover by hand:** `node scripts/e2e/run.mjs --purge-tag <tag>` (the harness's own teardown,
  tag-scoped; refuses `founderdemo`). Never `purge_demo_data.mjs --apply` for this: its dry run includes the standing
  founderdemo customers.
- `QD_NO_STALE_SWEEP=1` makes a `withRun` touch only its own tag (used to prove the SIGTERM path without sweeping
  other sessions' leftovers).
