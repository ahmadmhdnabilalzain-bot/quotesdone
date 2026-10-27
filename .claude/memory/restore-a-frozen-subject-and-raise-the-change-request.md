---
name: restore-a-frozen-subject-and-raise-the-change-request
description: A real fix to a frozen Phase C kernel routine is still not yours to make — restore the body, raise a PCCR, and fix the harness instead.
metadata:
  type: feedback
---

23 Aug 2026: J02 fixed a measured defect in `fn_kernel_cancel` (a run cancellation refused on the
state model of a command nobody named). `fn_phase_c_freeze_drift` then read
`frozen_subjects_drifted 1 of 25` — `canonical_cancellation_service` is a frozen Phase C subject and
the amendment had no founder approval.

**Why:** `scripts/phase_d/approve_pccr_amendments.mjs` records an approval the founder gave IN
WRITING, quoted in the session brief. It is not a way to GIVE one. Recording an amendment without
his words would forge a founder approval — the exact thing [[never-state-what-you-have-not-measured]]
and the no-fabrication rule forbid. This is not the "decide it, don't escalate" case
([[decide-dont-present-options]]): the freeze exists because he said these subjects do not change
without him.

**How to apply:** restore the frozen body (re-apply its canonical file), remove the migration and
its MANIFEST.txt line so the canonical routine engine reports 0 drift both ways, write the change
request as `docs/phase-d/PCCR_nnn_*.md` with the measurement and the exact one sentence he is being
asked to approve — then look for the fix that does NOT touch the frozen subject. Here the four-mode
harness had coupled two modes through one founder command; giving cancellation its own transaction
fixed the measurement with the kernel untouched.
