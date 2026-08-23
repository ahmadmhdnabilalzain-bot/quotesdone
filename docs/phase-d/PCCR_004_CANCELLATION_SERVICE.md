# PCCR-004 — `fn_kernel_cancel` refuses a workflow run on the state model of a command nobody named

**Status: RAISED, NOT APPROVED, NOT APPLIED.** Nothing in the estate has been changed by this
document. `fn_kernel_cancel` is running its frozen body and
`fn_phase_c_freeze_drift.frozen_subjects_drifted` reads **0 of 25**.

**Subject:** `canonical_cancellation_service` — `public.fn_kernel_cancel(p_input jsonb)`, a frozen
Phase C subject in `public.phase_c_frozen_subject`, frozen digest `fc59489aff…`.

**Why this is a change request and not a fix.** The amendment was written, applied and measured on
23 Aug 2026, and then **reverted** when the kernel board reported the drift. The Phase C freeze
exists so that the kernel's own services do not change without the founder's approval, recorded
through the authenticated founder-session door that G01 built, and this session's brief carries no
such approval. `scripts/phase_d/approve_pccr_amendments.mjs` records an approval the founder gave
**in writing**; it is not a way to give one.

---

## 1. What was measured

Two Phase D drives of W01 inside one fixture scenario produce runs 47357 and 47358 under founder
command 12773. The failure path is driven on the first, which moves the **command** to `failed`.
`fn_kernel_cancel` is then called on the **second** run — state `active`, and
`public.phase_b_workflow_transition` declares `active -> cancelled`:

```json
{"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted",
 "message": "The command state model does not allow this move. Nothing was cancelled."}
```

and run 47358 is still `active` afterwards. Reproduced on W01, W04 and W24.

`public.phase_c_command_transition` has no `failed -> cancelled` and is **right** not to: a failed
command is not cancelled. The caller asked to cancel a workflow run. The command was derived inside
the routine, its own model was consulted, and the run's cancellation was abandoned on the strength
of it — a guard firing on a subject nobody asked about, abandoning the one that was asked about.

## 2. The second half of the same root cause

Section (c) workflow runs, (d) step runs and (f) handoffs scope to `v_runs`. Sections **(e) tasks,
(g) outbox and (h) traces** match on `command_id`. So cancelling ONE run of a command closes the
tasks, outbox rows and traces of its **sibling** runs while leaving those runs open — an active run
with cancelled tasks underneath it, which is not a state the kernel should be able to produce.

Both halves are one defect: **one identifier doing two jobs.**

## 3. The proposed amendment

`v_command` becomes the command the subject *belongs to* — reported, never acted on unless
entitled. A new `v_cmd` is the command this call *may close and sweep*, and it is set only when:

* the caller named the command (`subject_kind = 'founder_command'`) — behaviour unchanged,
  **including** the early refusal when the command's state model forbids the move: there the
  command IS the subject; or
* the caller named a run, that run is the command's **last open run**, and the command's own state
  model permits the move.

Where `v_cmd` is null the run is still cancelled — that was always the thing asked for — and the
result carries `command_closed: false` with the reason in `command_note` instead of a refusal for
something the caller never asked for. Sections (a), (b), (e), (g), (h) and the postcondition (i)
read `v_cmd`.

The exact generated body is reproducible from `scripts/tmp_diag/gen_j02.mjs`, which splices three
anchors into the live body and asserts each matches exactly once.

## 4. What it costs to leave it

Nothing in production: no autonomous path cancels one run of a multi-run command today. It cost the
Phase D four-mode harness its cancellation measurement, and **that has been fixed in the harness
instead** — the cancellation arm is now its own transaction with its own audited fixture scenario,
so it can no longer inherit the failure arm's command state. See
`scripts/phase_d/build_four_mode_result.mjs`.

## 5. What the founder is being asked to approve

One sentence, in writing, naming the change request and the subject — the same form as PCCR-001 to
PCCR-003:

> PCCR-004 Amendment — canonical_cancellation_service. Approval is based on the amendment described
> in `docs/phase-d/PCCR_004_CANCELLATION_SERVICE.md`.

On that, the body is re-applied, the amendment row is recorded through the verified authenticated
founder-session path (`fn_phase_c_freeze_amendment_approve`), and the freeze board stays green
because the drift is amended rather than absent.
