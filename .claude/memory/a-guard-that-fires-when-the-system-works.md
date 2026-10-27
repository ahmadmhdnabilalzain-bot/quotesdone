---
name: a-guard-that-fires-when-the-system-works
description: "The mirror of the impossible-guard lens — a post-condition whose refusal count measures SUCCESS, not failure."
metadata: 
  node_type: memory
  type: project
  originSessionId: f4baf9ca-e2a9-4d49-aa5b-18d5d5fefa11
  modified: 2026-08-20T22:32:47.664Z
---

`fn_phase_d_handoff_accept` asserted "exactly one open task on the receiving step" (`if v_tasks <> 1
then raise`). Since D36 the Phase D dispatch runs inside the kernel's OPENER, so accepting a handoff
opens the receiving step and the handler attempts it in the same statement — and when the handler
EXECUTES, the work is done and the kernel closes the task. Count 0. Refused.

W01-S05 and W21-S08 are the only two steps in the estate whose handler executes. They were the only
two whose incoming handoff was refused. **Of 257 steps, the two that worked were the two the guard
blocked.**

**Why:** the estate has a well-worn lens for guards that can never fire ([[guarded-by-a-condition-that-cannot-occur]],
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]]) and one for guards that always fire
([[a-condition-that-cannot-not-fire]]). This is the third shape and the hardest to see, because the
guard looks reasonable and its refusals look like defects in whatever it refused.

**How to apply:** when a post-condition refuses, ask *what would this count read if the thing under
it had SUCCEEDED?* Here the comment named the failure it defended against — "a duplicate acceptance
that opened a second task makes this 2" — so the contract was AT MOST one, and `<> 1` had swept in a
zero that means the opposite. Split the zero: 0 with an EXECUTED dispatch on the receiving step is
success; 0 without one is still the failure. Prove it with one variable — two drives differing only
in `app.phase_d_dispatch` on/off gave opposite outcomes.
