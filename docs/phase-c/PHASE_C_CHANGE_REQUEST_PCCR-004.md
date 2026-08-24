# PCCR-004 — `fn_kernel_cancel` refuses a run on the state model of a command nobody named

**Status on 24 Aug 2026: RAISED. NOT APPROVED. NOT APPLIED. Disposition `DEFER_OR_REJECT`.**

`public.fn_kernel_cancel` is running its frozen body. `public.fn_phase_c_freeze_drift()` reads
`frozen_subjects_drifted` **0 of 25** and `amendments_awaiting_founder_approval` **0 of 5**.
Nothing in this session changed the subject, no migration file for the proposed body exists in the
tree, and no `public.phase_c_freeze_amendment` row names PCCR-004.

This document is the canonical registration of a change request whose detail was written up on
23 Aug 2026 in `docs/phase-d/PCCR_004_CANCELLATION_SERVICE.md` (the defect and the proposed
amendment) and `docs/phase-d/PCCR_004_AMENDMENT_TABLE.md` (the eleven-element amendment table,
digests and rollback). Those two documents are the full record; this one carries the elements
`docs/phase-d/PHASE_D_CHANGE_CONTROL.md` requires at the registered path so that
`public.phase_c_change_request.document_path` resolves to a file that exists.

---

## 1. The defect, and the observed problem

**Subject:** `canonical_cancellation_service` — `public.fn_kernel_cancel(p_input jsonb)`, a frozen
Phase C subject in `public.phase_c_frozen_subject`, frozen digest `fc59489aff…`.

Two halves of one root cause — **one identifier doing two jobs**:

1. The caller asks to cancel a **workflow run**. The routine derives the run's **command**, consults
   the *command's* state model, and abandons the run's cancellation on the strength of it. Measured
   on W01, W04 and W24: with the command already `failed`,
   `{"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted"}` and the
   run left `active`. `public.phase_c_command_transition` has no `failed -> cancelled` and is right
   not to — a failed command is not cancelled. The guard fires on a subject nobody asked about.
2. Sections (e) tasks, (g) outbox and (h) traces match on `command_id` while (c), (d) and (f) scope
   to `v_runs`. Cancelling ONE run of a command therefore closes the tasks, outbox rows and traces
   of its **sibling** runs while leaving those runs open.

## 2. Evidence

Two Phase D drives of W01 inside one fixture scenario produce runs 47357 and 47358 under founder
command 12773; the failure path is driven on the first, moving the command to `failed`; the cancel
is then called on the second. Reproduced on W01, W04 and W24. The amendment was written, applied
and measured on 23 Aug 2026 and **reverted** the same day when the kernel board reported the drift.

## 3. Current behaviour

As above: a run whose command cannot legally move is not cancelled, and a run that IS cancelled
takes its siblings' tasks, outbox rows and traces with it.

## 4. Proposed behaviour

`v_command` becomes the command the subject *belongs to* — reported, never acted on unless entitled.
A new `v_cmd` is the command this call *may close and sweep*, set only when the caller named the
command, or when the caller named a run that is the command's last open run and the command's own
state model permits the move. Where `v_cmd` is null the run is still cancelled and the result
carries `command_closed: false` with the reason in `command_note`. Full text and the exact diff:
`docs/phase-d/PCCR_004_CANCELLATION_SERVICE.md` §3.

## 5. Owner and reviewer

Owner: `quality_and_release_director`. Reviewer: `risk_and_governance_manager`. Neither resolves to
the other under either identity vocabulary (`fn_kernel_reviewer_independent` = true).

## 6. Gates and business rules affected

No gate and no business rule changes. GATE-009 (cancellation authority) and BR-042 are evaluated
against the same evidence before and after; the amendment changes only which subject the routine
acts on once a cancellation is authorised.

## 7. Security and privacy impact

None. No grant, policy, RLS state or identity resolution changes. The routine stays SECURITY DEFINER
with the same `search_path` pin and the same `kernel_write_authority` registrations.

## 8. Financial impact

None directly. Indirectly: the sibling-sweep half means a cancellation today can close the tasks and
outbox rows of runs that are still active, including runs carrying payment steps. No money moves in
either the current or the proposed behaviour — `fn_kernel_cancel` writes no financial table.

## 9. Compatibility

Backwards compatible for every caller that names a command (behaviour unchanged, including the early
refusal). Callers that name a run see a cancellation succeed where it previously refused, and see
`command_closed: false` where the command is not entitled to close. No signature change.

## 10. Migration and rollback

Migration: a single `create or replace` of `fn_kernel_cancel`, plus the
`public.phase_c_freeze_amendment` row naming PCCR-004. No DDL, no new object, so the classification
is `ROUTINE_RESTORE` and no `scripts/sql/down/` file is required. Rollback: re-apply the last file
before it that defines `fn_kernel_cancel`, which restores the frozen body byte-for-byte, then delete
the amendment row. Verification after rollback: `sha256(pg_get_functiondef)` equals `fc59489a…` and
`frozen_subjects_drifted` reads 0 of 25.

## 11. Founder approval

**Not given, and not sought again.** His disposition of 24 Aug 2026 is `DEFER_OR_REJECT`, recorded
in `public.phase_c_change_request.disposition` with its reason, on these grounds:

* the frozen cancellation service passes **30 of 30** Phase D cancellation cases;
* no current production path performs partial cancellation of one run while preserving sibling runs;
* Phase D does not depend on the amendment.

`public.phase_c_change_request` carries a CHECK — `phase_c_change_request_deferral_is_not_approval`
— that refuses an `approved_by` on a deferred or rejected request, so this row cannot later be read
as an approval. The defect remains real and remains recorded; it is deferred, not closed.
