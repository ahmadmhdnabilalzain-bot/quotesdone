---
name: a-rehearsal-proves-creation-not-execution
description: "The aborted-transaction rehearsal passed 58/58 invariants and still missed five defects, one of which made every canonical step advance impossible — a rehearsal creates routines and counts rows, it never runs them."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ace6f8ec-4a15-4994-b9f6-37f766585534
  modified: 2026-08-15T11:09:21.874Z
---

Phase C's migrations were rehearsed exactly as the protocol says: the exact committed bytes, one
implicit transaction, a trailing `raise` that reads the post-change counts first, production
fingerprint byte-identical either side of the abort. It reported **58/58 invariants held** and
passed.

Five real defects survived it. The worst: `fn_phase_c_step_advance` was reading
`phase_b_workflow_step.founder_gate` and passing it to the gate evaluator as a gate id. It is not
one — all 257 steps carry it and there are 19 distinct values, **all of them prose sentences**
("Pricing and commercial model changes remain founder-reserved."). Every advance failed closed on
an unknown gate, so **no canonical step could ever have moved**. Another: a plpgsql `SELECT INTO`
that matched no rows nulled `attempt_no`, so the *first* advance of any step hit a NOT NULL
violation.

**Why the rehearsal cannot see this class.** It creates routines, loads rows and counts them. It
never advances a step, opens a handoff, cancels a command or settles a delivery. Deploying a
routine is not running it, and `create or replace function` succeeding says nothing about what the
body does when called.

**How to apply:** after a rehearsal passes, write a check that EXECUTES each new write path once —
in an aborted transaction, asserting the returned payload, not just the absence of an error. Four
of Phase C's six defects were found that way, and in each case a guard I had written refused a
write I had written. The first instinct — that the guard was too strict — was wrong every time.

Related: [[harness-seeds-an-order-reality-cannot-produce]],
[[finished-capability-with-no-entry-point]], [[zero-cannot-tell-a-dead-guard-from-an-idle-system]].
