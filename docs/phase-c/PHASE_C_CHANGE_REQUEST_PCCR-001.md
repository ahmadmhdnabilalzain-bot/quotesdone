# PCCR-001 — Phase C change request

**Status: RAISED, NOT APPROVED.** Section 11 is the only element of this document that is not
measured, and it is not mine to fill.

`PHASE_D_CHANGE_CONTROL.md` line 7 says *"A kernel contract change requires Phase C change request"*
and line 9 lists nine required elements. Three changes to frozen Phase C objects were applied to
`htdblwldjkcgjvmqkbeh` on 2026-08-20 and recorded in `public.phase_c_freeze_amendment` without one.
Two independent acceptance audits raised the gap; the second could find no Phase C change request in
the tree at all, and it was right — there was none. This is it, written after the fact and saying so.

**Scope: three amendments.** `phase_c_freeze_amendment` holds rows `1`, `2` and `4`. There is no row
3: the first attempt at the third insert failed on a `GENERATED ALWAYS` identity column and consumed
the sequence value. That is an identity gap, not a missing amendment.

| id | subject | frozen object | file |
|---:|---|---|---|
| 1 | `canonical_step_engine` | `fn_kernel_open_step(p_input jsonb)` | `phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql` |
| 2 | `canonical_workflow_start_service` | `fn_kernel_workflow_start(p_input jsonb)` | same file |
| 4 | `component_crosswalk` | `public.phase_c_component` (3 rows) | `phase_d_e6_the_record_still_claimed_the_door_e4_closed.sql` |

---

## 1. Observed problem

**Amendments 1 and 2.** The 19 Aug independent acceptance measured 0 edge-function callers, 0 active
cron and 0 triggers on the Phase D executor and concluded Phase D had no application caller. Phase D
had built `fn_phase_d_handler_execute` *beside* the kernel's advance path rather than inside it, so
the only thing that ever invoked a Phase D handler was `fn_phase_d_drive_workflow` — a harness whose
own header states it is not a business path. The estate reached the kernel; the kernel did not reach
Phase D.

**Amendment 4.** `phase_d_e4_the_door_was_never_a_browser.sql` revoked EXECUTE on 57 SECURITY DEFINER
routines. Three `phase_c_component` rows recorded `external_entry = 'unauthenticated_only'` and
`classification = 'ACTIVE_PUBLIC_ENTRY'` **because of a PUBLIC EXECUTE grant** — K11 promoted them
for that reason on 2026-08-16, and their own crosswalk rows have said the repair out loud since:
*"Phase D: give it a caller and an entry point, or retire it. It is deployed and unreachable."*
E4 did the second half, and `fn_kernel_component_exposure_state.external_entry_disagrees_with_derivation`
went `0 → 3 of 149` within minutes.

## 2. Evidence

- **The dispatch gap.** Re-measured with comments and string literals stripped: fifteen of the twenty
  apparent callers of the kernel entries name them inside a comment, an error hint or a
  `where proname = '…'` board query. *A mention is not a call.* What is really there, one hop out:
  18 trigger functions on live tables → `fn_kernel_source_emit` → `fn_kernel_signal_submit` /
  `fn_kernel_trigger_submit` → `fn_kernel_workflow_start` / `fn_kernel_step_complete`; `os_api` →
  `fn_founder_command_submit` → `fn_kernel_workflow_start`; and cron 278 every minute through
  `fn_kernel_outbox_deliver`.
- **The stale record.** `phase_d_object_record` `authenticated SELECT = false` while 30 `v_obj_*`
  views over it read `true`; `fn_supplier_quality` had, after E4, no reachability vector of any kind —
  no grant to anon or authenticated, no internal caller, no trigger, no schedule, no view, no queue
  consumer, no webhook, and no caller in `src/**` or `scripts/**`.
- **The guard's own instruction.** `a00_phase_c_component_classification_guard` **refuses** the
  minimal write: `if new.classification like 'ACTIVE\_%' and not v_reachable then raise`, with the
  message *"Wire the missing leg, or record what is true; do not relabel the row."* The classification
  and activation_state moves are that instruction carried out, not a relabel to make a board green.

## 3. Current behaviour, before the change

`fn_kernel_open_step` and `fn_kernel_workflow_start` opened a step run and returned. No Phase D
handler ran on any estate path. `phase_c_component` recorded three components as publicly reachable
entries on the strength of a grant that had been revoked.

## 4. Proposed behaviour, and what was actually applied

- **1 and 2:** one declared local and one call to `public.fn_phase_d_dispatch_step`, immediately
  before each routine's existing final `return`. `fn_kernel_workflow_start` needed its own because it
  opens a run's FIRST step inline and does not call `fn_kernel_open_step`. Both bodies were produced
  by reading the live definition out with `pg_get_functiondef` and splicing; **every other line is
  byte-identical to the frozen one**. `fn_phase_d_dispatch_step` never raises for a business reason —
  a refusal is recorded in `phase_d_dispatch` and the kernel's own transaction is not affected.
- **4:** three rows set to `external_entry = 'no'`, with `classification` moved to the value
  `fn_kernel_component_reachability` derives — `ACTIVE_SCRIPT_ENTRY` for `fn_phase_b_invariants` and
  `fn_rating_due`, `DEFERRED_RUNTIME_IMPLEMENTATION` plus `activation_state = 'inactive'` for
  `fn_supplier_quality`.

## 5. Owner, reviewer, state and gate impact

**None.** No workflow ownership, workflow order, state, transition, gate, business rule, handoff
accountability, category-overlay authority or founder boundary changes. Measured after:
`fn_phase_a_baseline_drift()` **0 rows**, `fn_phase_b_baseline_drift()` **0 rows**,
`fn_phase_c_invariants()` **71 checks, 0 red**, `fn_kernel_all_boards()` **35 boards / 418 checks /
8 red**, and all 8 reds are pre-existing and separately ratcheted in `scripts/checks/kernel-boards.json`.

## 6. Security, privacy and financial impact

Amendment 4 **reduces** exposure: three components lose a public entry they should never have had.
Amendments 1 and 2 add no grant and no external effect — `fn_phase_d_dispatch_step` writes only
`phase_d_dispatch` and, on success, `phase_d_effect_ledger`. Paid inference over the whole session:
`llm_attempt` **0 rows**, `ai_cost_log` **0 rows**, **AED 0.00**. Outbound: 0 new `notifications`
rows. Business tables unchanged at 0 customers / 0 inquiries / 0 quotes / 0 transactions.

## 7. Backward compatibility

`CREATE OR REPLACE` on both kernel routines preserves signature and ACL; every existing caller is
unaffected. The three component rows are read by `fn_kernel_component_reachability` and the
committed crosswalk CSV, both of which were re-measured and now agree
(`phase_c_component_crosswalk.test.mjs`: 1801 = 1801, 0 findings).

## 8. Migration and rollback

Rollback class for all three is recorded in `docs/phase-d/PHASE_D_ROLLBACK_CLASSIFICATION_D9.md`.
`d36` is `EXPLICIT_DOWN_REQUIRED` with a written down script; `e6` is `ADDITIVE_SURVIVAL_SAFE` and
**both halves must revert together** — removing the amendment row without reverting the three
component rows makes `fn_phase_c_freeze_drift()` report drift it cannot explain, and reverting the
components without removing the amendment leaves an amendment whose `new_digest` matches nothing.

## 9. How the freeze was respected

`public.phase_c_frozen_subject.digest` was **never overwritten** — for any subject, at any point.
Each amendment pins `prior_digest` to the exact frozen baseline and `new_digest` to
`encode(sha256(convert_to(pg_get_functiondef(oid),'UTF8')),'hex')` over the live definition, neither
of which is a literal in any file. `fn_phase_c_freeze_drift()` reads **0 of 25 drifted** with **3
changed under a recorded amendment**, and a later edit on top of any of the three reads as drift
again — which is the point.

## 10. The document conflict this request exists inside

`PHASE_D_CHANGE_CONTROL.md` requires this document. The founder's session brief of 2026-08-20
instead names the amendment table as the mechanism, in its non-negotiables:

> "A change to a Phase C kernel routine body is allowed but trips `fn_phase_c_freeze_drift()`; record
> it in `public.phase_c_freeze_amendment` pinned to the exact prior digest. NEVER overwrite
> `phase_c_frozen_subject.digest` — that is a rubber stamp and the amendment table exists so it does
> not have to happen."

**This request does not resolve that conflict and does not need to.** Both instructions are now
satisfied: the amendments are recorded in the table as the brief requires, and the change request the
control document requires exists and is this file. If the founder confirms the brief supersedes,
nothing here changes. If he confirms the control document governs, section 11 is the outstanding item.

## 11. Founder approval requirement

**Required, and NOT given.** Nothing in this document may be read as approval. It is raised by the
builder, after the fact, and every element above except this one is a measurement.

- [ ] Founder approval — *unsigned*

---

**Raised:** 2026-08-20 · **Applied before raised:** yes, and that is the defect this document also
records · **Project:** `htdblwldjkcgjvmqkbeh` · **Merge commit:** `a2347ad` (#452) and `dd3dd23` (#451)
