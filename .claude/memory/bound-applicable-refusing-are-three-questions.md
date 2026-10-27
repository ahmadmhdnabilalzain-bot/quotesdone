---
name: bound-applicable-refusing-are-three-questions
description: "Bound, applicable and actually-refusing are three separate questions; a brief and two audits all stopped at the second and named the wrong blocker."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: de3a8ccf-f85f-43d1-bedc-d402901ec8ac
  modified: 2026-08-20T16:47:34.248Z
---

The 2026-08-20 session brief said BR-043 refused every Phase D dispatch: scope `all`, a condition
about the call, `fn_phase_d_rule_applies` takes only a step id, so it falls through to
`applies = true` on all 257 steps, and it requires `exception_authority_ref` which nothing supplies.

Every clause of that is true, and the conclusion is false. **BR-043 refuses nothing.** Its predicate
in `fn_phase_d_rule_check` returns `NOT_APPLICABLE, ok = true` when the call names no
`policy_exception`. It appeared in none of the 254 refusals in an estate-wide drive.

Three questions, and they are not the same question:

1. **Is the rule BOUND to the step?** `phase_d_handler_binding.rule_ids`. Cheap, and where the
   earlier note [[a-list-with-no-third-answer]] already warns counting stops too early.
2. **Does it APPLY?** `fn_phase_d_rule_applies`. Scope is not applicability.
3. **Does the predicate actually REFUSE?** Only driving it answers this. A predicate may hold its own
   `NOT_APPLICABLE` branch that neither of the first two questions can see.

A brief, an R1 audit and an R2 audit all stopped at question 2 and named a blocker that was not
blocking. The real causes — found by driving all 30 workflows through the kernel rather than reading
the registry — were two statement orderings: see
[[a-resolver-that-reruns-the-gates-own-test]] and the `fn_kernel_handoff_accept` ordering that set
the run active eleven lines AFTER the call that dispatched into it.

**How to apply:** before building the fix a brief proposes, drive the thing and read the rows it
writes. `phase_d_dispatch.reason` names the rules that actually refused; a tally of those took
minutes and disproved a diagnosis three documents agreed on. Reinforces
[[session-briefs-carry-misdiagnoses]] and [[a-mention-is-not-a-call]].
