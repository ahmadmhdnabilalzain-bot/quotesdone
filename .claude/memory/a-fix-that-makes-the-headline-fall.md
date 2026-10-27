---
name: a-fix-that-makes-the-headline-fall
description: "When a real fix makes the number worse, the measurement path assumes the old failure — check that before doubting the fix."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: aa55e49d-4ddb-44db-87b4-c412a7a8e170
  modified: 2026-08-22T18:46:43.406Z
---

22 Aug 2026. F36 let five capability steps execute for the first time, and the estate-wide EXECUTED
count went **down**, 45 → 36. The fix was right. `fn_phase_d_handler_execute` hands its completed
step to the frozen kernel, which closes the step run and moves the run to `waiting_handoff`; the
driver then called `fn_kernel_step_complete` on the step just closed, was correctly refused
`k3_run_not_active`, and treated that as the end of the drive. Every handler success cost the
remainder of its workflow — so the better Phase D got, the worse the headline looked.

**Why:** the driver was written when no step ever succeeded, so "the handler completed this step"
was a state it had never seen and had no branch for. Any harness built during a period of total
failure encodes that failure as its normal path.

**How to apply:** when a fix you believe in moves a metric the wrong way, do not revert it and do
not argue with it — read the collection path for a branch that only ever ran in the failing case.
Ask: *has this instrument ever observed success?* Related: [[guarded-by-a-condition-that-cannot-occur]],
[[instruments-report-on-the-wrong-subject]], [[zero-cannot-tell-a-dead-guard-from-an-idle-system]].
