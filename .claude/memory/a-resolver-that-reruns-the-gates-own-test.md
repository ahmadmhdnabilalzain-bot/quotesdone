---
name: a-resolver-that-reruns-the-gates-own-test
description: "A resolver that re-runs a gate's test and blanks the value turns a judgeable fact into an absent one, and makes the answer depend on when it is called."
metadata: 
  node_type: memory
  type: project
  originSessionId: de3a8ccf-f85f-43d1-bedc-d402901ec8ac
  modified: 2026-08-20T16:47:12.178Z
---

`fn_phase_d_step_context` resolved `to_state` from the step's own frozen
`phase_b_workflow_step.success_workflow_state`, then re-ran GATE-006's test on it and set it to NULL
when the test failed. Two consequences, and the second is the dangerous one.

**The answer depended on WHEN the function was called.** The dispatch runs inside
`fn_kernel_open_step`, and a step opened out of a handoff is dispatched while its run is still in
`waiting_handoff` — the state it is leaving. So the guard asked whether the run could go
`waiting_handoff -> waiting_handoff`, which the frozen model rightly refuses, and nulled the key.
Called against the same step run a moment after the accept returned, the identical function resolved
it. Measured 2026-08-20: W01-S04/S05/S06 recorded `to_state` in `phase_d_dispatch.unresolved_keys`
while a direct call resolved it to `waiting_handoff`.

**It converted "the gate would judge this" into "the evidence is absent."** GATE-006 already tested
the transition against `phase_b_workflow_transition`, and already held a reasoned branch for a step
declaring the state it is already in. With the key blanked the gate could reach neither branch and
reported *"requires [to_state] and the call names none of it"* — evidence-absence standing in for a
judgement the instrument was built to make. An independent audit read that as proof the estate was
reporting missing branches as policy.

**The fix was a REMOVAL.** Resolve the declaration; leave the judging to the gate that owns it.
GATE-006 refusals across the estate went 12 → 0, and nothing was weakened: an undeclared transition
is still refused, by the check whose `evidence_source` names the transition table.

**The lens.** When a key comes back unresolved, ask whether the resolver is *resolving* it or
*validating* it. A resolver that validates is duplicating a downstream check, and when the two
disagree the downstream check loses silently. Related: [[linking-column-written-after-the-read]],
[[instruments-report-on-the-wrong-subject]], [[a-guard-that-fires-on-the-correct-refusal]].
