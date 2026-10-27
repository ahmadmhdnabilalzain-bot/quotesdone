---
name: freeze-the-population-before-the-write
description: "A check whose population is defined by the column the migration rewrites goes green by emptying its own denominator; and an increment's own gate passing is not the estate's gate passing."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 953dddc0-0434-4402-8342-dd32e9bf3929
  modified: 2026-08-16T21:41:44.021Z
---

Two ways a fix can certify itself, both hit on 17 Aug 2026 during the kernel rebuild.

**1. The denominator was its own subject.** K11's exposure invariant defined its population as
"components that are inactive or deferred". The migration then reclassified 48 of them to active.
Every check went green — over a denominator that fell from 149 to 101. The rows did not stop being
wrong; they stopped being counted. Fixed by snapshotting the population into
`phase_c_component_exposure_scope` BEFORE any write, and measuring against the frozen set.

**How to apply:** if a migration writes column X, no check in that migration may use column X in its
`where`. Freeze the population first, or key the check on something the migration does not touch.

**2. The increment's gate is not the estate's gate.** K5 retyped
`phase_c_event_outbox.first_failure` from text to timestamptz. `fn_phase_c_invariants` still compared
it to `''`, so all 71 checks raised 22007 — and `fn_phase_c_baseline_drift` with them, because it
calls them. The K5 rehearsal passed: it ran the KERNEL invariants. The end-of-session sweep found it.

**How to apply:** after any ALTER TABLE ... TYPE, grep every routine for the old comparison
(`= ''`, `<> ''`, `coalesce(col,'')`) before applying, and run the ESTATE's invariant board in the
same rehearsal, not just the new increment's.

Related: [[a-denominator-does-not-fix-a-population]], [[instruments-report-on-the-wrong-subject]],
[[absent-input-scores-as-satisfied]], [[green-pr-does-not-mean-deployable]].
