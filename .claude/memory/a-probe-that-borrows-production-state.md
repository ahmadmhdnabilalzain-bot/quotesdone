---
name: a-probe-that-borrows-production-state
description: "A scenario probe that reads production's current state (an open stand-down, a due backlog) instead of creating it inside the aborted transaction proves nothing once that state changes; and a temp table ON COMMIT DROP makes a routine one-call-per-transaction"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T23:08:05.898Z
---

Two connectivity probes (org_connectivity_scenarios.test.mjs) called fn_promotion_review /
fn_outcome_evaluate expecting PAUSED_BY_FOUNDER_STANDDOWN, then deleted company_stand_down and
called again expecting grades. Both passed for weeks — because the founder's 2 Sep stand-down was
open and the daily cron had left due outcomes. The day he resumed, the parity job went red with
`undefined` and NOT_MEASURED_DURING_HOLD (fn_promotion_review returns that for 30 days after
max(resumed_at), by design).

**Why:** the probe was borrowing production's state as its fixture. A mechanism test must build
the state it asserts on — insert its own company_stand_down row, its own due outcome_record —
inside the aborted transaction, so the assertion is about the code and not about the calendar.
Cousin of [[an-identity-is-never-a-fixture]] and [[harness-seeds-an-order-reality-cannot-produce]].

The second call also exposed a latent defect: fn_outcome_evaluate created
`create temporary table _due_group on commit drop` with no guard, so any second call in one
transaction raised 42P07. An early return (the stand-down) had hidden it. A routine with an
unguarded temp table is a one-call-per-transaction routine; `drop table if exists` first
(fn_outcome_evaluate_can_run_twice_in_one_transaction.sql, 4 Sep 2026).

**How to apply:** when a probe's first read is `fn_x()->>'status'` against live rows it did not
write, rewrite it to insert those rows first. When a probe calls a routine twice in one
transaction, expect temp-table and advisory-lock collisions and read the routine for them.
