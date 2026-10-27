---
name: linking-column-written-after-the-read
description: The row exists but the column that joins it is stamped later than the read — every after-the-fact probe resolves it perfectly, so the defect survives testing.
metadata:
  type: project
---

Three instances in one increment (20 Aug 2026), all the same shape: **the row is there, and the
column you are joining on is written after the moment you read it.**

`fn_kernel_trigger_submit` inserts the `kernel_trigger_inbox` row, calls `fn_kernel_workflow_start`,
and stamps `run_id` and `business_object_id` onto that row only AFTER the call returns. Anything
dispatched from inside `workflow_start` — which is where a run's FIRST step opens — sees neither.
Matching on `run_id` failed; matching on `business_object_id` failed; both resolved correctly when
called by hand a moment later.

**Diagnostic:** if a resolver works in a probe and fails in production, do not look at the resolver.
Draw the write order of the transaction and ask which columns exist at the instant of the read.

What is available early is whatever the caller already passed. Here `fn_kernel_workflow_start`
receives `source_ref = 'trigger_inbox:<inbox_id>'` and writes it onto `phase_c_task` before opening
the step — so the inbox id was in hand the whole time.

Related: [[harness-seeds-an-order-reality-cannot-produce]], [[a-rehearsal-proves-creation-not-execution]].
