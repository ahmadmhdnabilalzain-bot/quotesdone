# PCCR-007 — The frozen kernel can reject a handoff

**Date:** 2026-09-01
**Author:** autonomy audit remediation
**Status:** applied to `htdblwldjkcgjvmqkbeh`, read back identical, kernel boards 7/7.

## The gap

Rejection is a first-class, frozen outcome on all 159 handoffs (every `phase_b_handoff` carries a
`rejection_condition` and a `return_owner_role_id`), but the frozen kernel exposed only
`fn_kernel_handoff_accept`. There was no `fn_kernel_handoff_reject`.

`fn_phase_d_handoff_reject` therefore recorded the refusal on the Phase D side and, by its own
disclosure, left the kernel handoff run `status = 'open'` **forever**. An open handoff run is a hard
closure blocker: the workflow run could never close, no remediation step opened for the return owner,
and one receiver refusal (or silence) stranded the run until a human cancelled it. Half the handoff
lifecycle had no door. Measured: 2 runs sat 300+ hours overdue with no path forward.

## The change

Add `public.fn_kernel_handoff_reject(jsonb)`, the mirror of `fn_kernel_handoff_accept`, reusing the
existing kernel primitives — **no new mechanism**:

- same lock order (workflow run, then handoff run); same receiver check via `fn_phase_c_resolve_actor`;
- requires both a `reason` and the exact `missing` item (the frozen `rejection_condition` demands it);
- records the rejection through `fn_phase_c_handoff_decide('reject', …)` — the kernel-internal path that
  moves the handoff run to `'rejected'` and returns accountability to the frozen `return_owner_role_id`;
- moves the workflow run back to `'active'` (a rejected handoff must not leave it parked in
  `waiting_handoff`);
- opens a remediation step run + task for the return owner at the sending step via
  `fn_kernel_open_step`, unless a live step for it already exists — in which case that IS the
  remediation venue, not a duplicate.

A rejection advances **no new downstream work** and transfers accountability to nobody but the return
owner. Write authority is registered in `kernel_write_authority` for the one protected table it writes
directly (`phase_c_workflow_run`); everything else goes through primitives that carry their own
authority.

`fn_phase_d_handoff_reject` is repointed to call this primitive, so a rejected handoff now **closes and
remediates** instead of only being logged. The two Phase D assertions that a rejection must not move the
run or open a step are removed — they guarded the old "the kernel exposes no reject" invariant that this
PCCR replaces. The Phase D acceptance audit record is still written exactly as before.

## Verification (aborted-transaction rehearsal)

On the two real open handoff runs (H-W20-01-02, runs 80 and 82):
`fn_phase_d_handoff_reject(...)` returned `kernel_handoff_still_open = false`, kernel handoff
`status = 'rejected'`, workflow run `state = 'active'`, and a Phase D acceptance row — then rolled back,
leaving zero residue. Kernel boards 7/7; `phase_c_guards_reject_injected_defects` 0 failed; Phase A/B
baseline drift 0.

## Files

- `scripts/sql/pccr_007_the_kernel_can_reject_a_handoff.sql` — the kernel primitive + write authority.
- `scripts/sql/pccr_007b_phase_d_reject_calls_the_kernel_door.sql` — Phase D repoint.
