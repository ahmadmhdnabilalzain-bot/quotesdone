---
name: a-guard-that-manufactures-what-it-prevents
description: "A BEFORE DELETE guard that REFUSED while child work was live turned every fixture cleanup into committed residue within the hour — compensate first, do not refuse."
metadata:
  type: feedback
---

27 Aug 2026. To stop orphaned workflow runs I attached `a00_kernel_parent_delete_guard` to seven
canonical relations, refusing a parent DELETE while any live run named it. Measured against the
estate the same afternoon: **it produced the exact residue it existed to prevent.**

Every fixture that creates a customer cleans up by deleting that customer. `public.customers` carries
`z50_customer_registered_kernel_emit`, which opens a W04 run on INSERT. So the cleanup delete was
refused, two `ZZ DEMO` rows stayed committed on production, `fn_phase_d_fixture_residue()` went
0 → 2, and four Phase D checks went red.

The fix is the other arm: **cancel the child work through the canonical path, then permit the
delete.** It runs BEFORE the row goes so the subject still resolves, it goes through
`fn_kernel_cancel` (which refuses its own transaction if it leaves queued derived work), and it
asserts afterwards that no live run still names the object.

**Why:** a refusal only moves the problem to the caller, and a caller that gives up on the delete
leaves the parent AND the work. Compensation means the orphan cannot be produced at all. It is also
what a PDPL erasure should do — deleting a customer while their onboarding run stays open is not
privacy, it is a dangling workflow about a person who no longer exists.

**How to apply:** before adding a guard that refuses a normal operation, ask what already performs
that operation on a schedule or in a test, and run the suite before believing the guard is finished.
See [[a-new-guard-reddens-the-fixture-not-the-code]], [[tightening-a-guard-reddens-its-own-probes]]
and [[the-primary-identity-is-not-how-producers-key-a-subject]].
