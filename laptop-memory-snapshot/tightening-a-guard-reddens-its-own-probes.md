---
name: tightening-a-guard-reddens-its-own-probes
description: "When a guard gets stricter, the checks that exercised its OTHER arms go red on the new refusal — and accepting that refusal code silently deletes their coverage."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: b8c40486-c680-4046-8a9d-cc5a4595866a
  modified: 2026-08-21T21:16:24.590Z
---

Making `fn_phase_c_require_founder` resolve a verified auth subject instead of a typed email
(PCCR-003, 21 Aug 2026) turned **six** existing checks red in one suite run. Every red was the guard
working. None of them was a defect in the new code.

**Why:** a probe that reached a downstream arm by satisfying the identity check with a string now
gets refused at the identity check instead. `phase_c_guards_reject_injected_defects` was the sharp
case — two of its refund cases are about a *rejected decision that was executed* and an *executor who
is also the reconciler*, and both came back `28000` for identity before their own arm was reached.

**The trap, and it is the whole point:** the cheap fix is to update the expected SQLSTATE to the new
one. Do that and the case still passes, still has a name that says it tests the rejected-execution
guard, and tests nothing but the identity check. Three cases would then be one case, three times.

**How to apply:** when a guard gets stricter, for each red check ask *which arm was this exercising?*
— then give the probe whatever the new, stricter guard legitimately needs (here: bind the verified
subject the way the server does, transaction-locally, inside a transaction that aborts) so the
original arm is what refuses. Keep one case that does NOT satisfy the new check and expects the new
refusal, so the tightening itself is tested too.

Related: [[a-guard-that-fires-on-the-correct-refusal]],
[[evidence-that-states-the-predicates-premise]], [[never-state-what-you-have-not-measured]].
