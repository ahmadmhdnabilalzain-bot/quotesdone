---
name: callable-is-not-answerable-yet
description: A delegate being STABLE and invocable does not mean the question can be answered at the point the predicate runs.
metadata:
  type: feedback
---

BR-008 was given a real predicate because its delegate `fn_phase_d_handoff_packet_valid` is STABLE
and therefore callable. It then refused 29 of 30 workflows' first steps.

**The packet is what the sending step PRODUCES.** The predicate runs when the step has just opened
and nobody has performed it, so there is nothing to check. Its registry row said KERNEL_ENFORCED for
exactly that reason — the kernel checks the packet when the handoff is ACCEPTED.

**Why:** "can this routine be called from here" and "does the fact exist yet at this point in the
lifecycle" are different questions, and only the second one decides whether a predicate is honest.

**How to apply:** before turning a delegated check into a local predicate, ask when the fact it reads
comes into existence relative to when the predicate fires. If the answer is "later", leave it
delegated and label it — a rule that always refuses is the mirror of a rule that cannot refuse, and
just as useless.

Same increment, same shape inverted: `fn_kernel_sla_due` ends in `coalesce(<lookup>, 24)`, so
"returns non-null" could never fail — an unregistered policy silently gets a 24-hour deadline.

Related: [[a-condition-that-cannot-not-fire]], [[guarded-by-a-condition-that-cannot-occur]].
