---
name: a-denominator-does-not-fix-a-population
description: "Re-expressing a zero-over-zero check as numerator/denominator does nothing if the population filter still excludes the failing rows — completed_step_runs_without_trace read \"0 of 1\" over 8 step runs, 7 of them untraced."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 953dddc0-0434-4402-8342-dd32e9bf3929
  modified: 2026-08-16T18:58:18.177Z
---

The Phase C correction fixed four trace invariants that were zero-over-zero by adding a denominator.
`completed_step_runs_without_trace` then read **"0 of 1", ok** — while
`phase_c_workflow_step_run` held **8** rows, **7** of them `active` with `trace_id NULL`. The
predicate still carried `where state = 'completed'`, so the seven failing rows were never in the
denominator either.

**Why:** a denominator proves the check *has* input; it says nothing about whether the input is the
population the gate names. Open objects are the ones most likely to be missing evidence, and a
"completed only" filter is exactly the filter that hides them.

**How to apply:** when a check reports `0 of N`, ask what the **total** row count of that table is
and why N is smaller. If N ≠ total, the difference is the untested population — name it out loud.
Same session: the founder-command trace guard was BEFORE UPDATE only, so an INSERT at a late state
with a null trace was accepted and invisible to both command trace checks; and
`commands_ahead_of_their_trace` used an inner join, which drops the null-trace rows it exists to
find. Guard direction and join type are population filters too.

Related: [[instruments-report-on-the-wrong-subject]], [[absent-input-scores-as-satisfied]],
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]], [[checks-can-measure-row-age-not-mechanism]].
