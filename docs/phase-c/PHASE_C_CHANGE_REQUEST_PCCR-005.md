# PCCR-005 — `internal_review_service`: a verdict may be recorded for a step that declares no reviewer

**Status on 24 Aug 2026: RAISED. NOT APPROVED. NOT APPLIED.**
`public.fn_kernel_review_decide` is running its frozen body. `public.fn_phase_c_freeze_drift()`
reads `frozen_subjects_drifted` **0 of 25** and `amendments_awaiting_founder_approval` **0 of 5**.
Nothing in this session changed the subject and nothing in this document records an approval.

**This change request is not required for Phase D.** The hole it describes was closed a different
way, without touching any frozen routine — see *The resolution that was applied instead*, below.
PCCR-005 is the alternative resolution, disclosed so the founder can choose it if he prefers it.
The recommendation at the foot of this document is **defer**.

---

## The defect, measured by execution

`fn_kernel_review_decide` accepts `approved`, `rejected` and `changes_requested`, seals the decision
into a `TRACE-ROLE-ACTION` trace row and stamps `phase_c_task.reviewer_role_id`.

Exactly one predicate reads that verdict, in two places that say the same thing —
`fn_kernel_step_complete` §3g (`k3_reviewer_verdict_missing`) and `fn_phase_d_handler_execute` §4b
(`pd_review_not_recorded`) — and both are guarded by:

```
coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
```

**28 of the 257 frozen steps name an independent reviewer. On the other 229, nothing read the
verdict at all.** And even on the 28 the predicate tests for the *presence of an approval*, never
for the *presence of a rejection* — right by accident there, silent everywhere else.

Driven on production, 24 Aug 2026, in transactions that end in `raise exception`
(`scripts/tmp_diag/rev_gap.mjs`):

```
W04-S03   declares no reviewer
          fn_kernel_review_decide(decision 'rejected')  -> ok = true
          fn_phase_d_recorded_review                    -> verdict 'rejected'
          fn_kernel_step_complete(outcome 'pass')       -> COMPLETED, state = completed

W04-S04   declares compliance_and_privacy_officer
          the same rejected verdict                     -> REFUSED k3_reviewer_verdict_missing
```

A reviewer rejected the work, the rejection was recorded through the canonical door, and the step
completed anyway.

---

## The complete amendment table

| element | value |
|---|---|
| **Amendment ID** | PCCR-005 |
| **Frozen Phase C subject** | `internal_review_service` — row of `public.phase_c_frozen_subject`, `object_kind` routine |
| **Frozen routine signature** | `public.fn_kernel_review_decide(p_input jsonb) returns jsonb`, `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path TO 'public','pg_temp'` |
| **Frozen source digest** | the value in `phase_c_frozen_subject.digest` for this subject; verified live on 24 Aug 2026 as equal to `sha256(pg_get_functiondef(oid))` of the running body, so the subject is undrifted |
| **Proposed source digest** | **not computed, because nothing was generated.** No migration file exists for this amendment and none will be written unless it is approved. Stated rather than left blank: PCCR-004's table carries a proposed digest because that amendment was built, applied, measured and reverted; this one has not been built at all. |
| **Exact current behaviour** | The routine validates the decision value and a non-empty reason; loads the task; reads `phase_b_workflow_step.independent_reviewer_role_id` into `v_declared`; **and only if `v_declared is not null`** compares the offered reviewer against it. Where the step declares no reviewer, `v_declared` is null, the comparison is skipped, the independence check still runs, and the verdict is sealed and stamped. |
| **Exact alleged defect** | A verdict — including `rejected` — can be created against a step whose frozen row names no independent reviewer, and no reader of that verdict exists for such a step. The record is accepted and then has no consequence. |
| **Reproducible production evidence** | `node scripts/tmp_diag/rev_gap.mjs W04-S03` and `… W04-S04`, output quoted above. Both run inside transactions that end in `raise exception`; nothing is left behind. |
| **Proposed behaviour** | `fn_kernel_review_decide` refuses when the step declares no independent reviewer, returning `{ok:false, error:'step_declares_no_reviewer', step_id, message:…}` in the same shape as its existing `not_the_declared_reviewer` and `reviewer_not_independent` refusals. It would raise nothing and write nothing. |
| **Caller impact** | A caller recording a verdict for one of the 28 reviewer-declaring steps sees no change. A caller recording one for any of the other 229 receives `ok:false` where it previously received `ok:true`. **Measured: this repository contains no such caller** — every recorded verdict in the Phase D harness is against a step that declares a reviewer, or is the deliberate probe above. |
| **Command-cancellation impact** | None. `fn_kernel_cancel` neither reads nor writes review verdicts, and no cancellation path calls `fn_kernel_review_decide`. |
| **Workflow / run / step / task / handoff / outbox / trace impact** | **Trace:** one fewer `TRACE-ROLE-ACTION` row would be written in the refused case — a refusal writes no trace today either, so the shape is unchanged. **Task:** `phase_c_task.reviewer_role_id` would not be stamped in the refused case. **Workflow, run, step run, handoff, outbox:** untouched; none is read or written by this routine. |
| **Security impact** | None. Same signature, same `SECURITY DEFINER`, same pinned `search_path`, no grant change, no new relation read or written. The change only narrows what is accepted. |
| **Privacy impact** | None. No column is newly read, no payload widened, nothing emitted outward. |
| **Founder-boundary impact** | None. `public.phase_b_founder_boundary` is unchanged; no boundary scopes internal review. W01-S06 names `founder` as its independent reviewer and is one of the 28 — its behaviour is unchanged. |
| **Phase A impact** | None. `fn_phase_a_baseline_drift()` returns 0 rows before and after; no department, role or overlay is read or written. |
| **Phase B impact** | None. `fn_phase_b_baseline_drift()` returns 0 rows before and after. `phase_b_workflow_step.independent_reviewer_role_id` is READ, never written. This is not a Phase B change request. |
| **Compatibility** | A behavioural narrowing, not a signature change. Same arguments, same result keys; one new `error` value in an existing `ok:false` shape. A caller that handles `ok:false` today handles this. |
| **Migration** | One `CREATE OR REPLACE FUNCTION`, generated by splicing a single guard into the live body after the `v_declared` lookup. No DDL, no grant, so no `REVOKE`. Applied by `node scripts/apply_sql.mjs <file> --apply` and read back. The amendment row would then be recorded through `public.fn_phase_c_freeze_amendment_approve`. |
| **Exact rollback** | Re-apply the last file defining `fn_kernel_review_decide`, restoring the frozen body byte-for-byte, then delete the `public.phase_c_freeze_amendment` row for PCCR-005. `create or replace` has no DDL to reverse; classification `ROUTINE_RESTORE`, no `scripts/sql/down/` file required. Verification: `sha256(pg_get_functiondef)` equals the frozen digest and `frozen_subjects_drifted` reads 0 of 25. |
| **Positive cases** | (1) an approved verdict on a reviewer-declaring step → sealed as today; (2) a rejected verdict on a reviewer-declaring step → sealed as today, and `fn_kernel_step_complete` still refuses the pass; (3) a verdict offered by the wrong role → still `not_the_declared_reviewer`; (4) `fn_phase_c_freeze_drift()` 0 red with the amendment recorded. |
| **Negative cases** | (1) any verdict on a step declaring no reviewer → `ok:false, error:'step_declares_no_reviewer'`, no trace row, `reviewer_role_id` unstamped; (2) the creator as reviewer on a declaring step → still `reviewer_not_independent`, including through an alias; (3) an unknown task → still `task_not_found`; (4) an empty reason → still refused. |
| **Present on a branch** | **No.** Nothing was generated. |
| **Present on production** | **No.** The live digest equals the frozen baseline, measured 24 Aug 2026. |
| **Consequence of approval** | A review verdict can exist only where the frozen architecture asks for one. The ambiguity of an unrelated review record coexisting with a step disappears at the source rather than being handled downstream. |
| **Consequence of rejection** | Nothing breaks, and nothing is left open — the hole is already closed the other way (below). What remains is that a verdict may be *recorded* for a step that declares no reviewer; under N02 it is now *honoured* rather than ignored, so it can no longer be recorded and walked past. |

---

## The resolution that was applied instead, and why it did not need him

`fn_kernel_review_decide` is frozen. `fn_phase_c_workflow_step_run` and its guards are not, and the
table already carried a sibling `BEFORE UPDATE` guard of exactly the right shape
(`a00_phase_c_step_run_trace_guard`).

`scripts/sql/phase_d_n02_a_rejected_review_stopped_nothing_on_the_229_steps_that_name_no_reviewer.sql`
adds `a01_phase_c_step_run_review_verdict`, which refuses a move to `completed` while the **latest**
sealed verdict for that run and step is `rejected` or `changes_requested`.

It resolves the same contract in the safer direction — **a verdict recorded against any step is now
honoured rather than ignored** — and it needs no frozen change. Proved by execution, four positive
controls and one negative:

```
W04-S03 rejected verdict, outcome pass   REFUSED pd_review_verdict_rejected
W04-S04 rejected verdict, outcome pass   REFUSED k3_reviewer_verdict_missing (unchanged)
no verdict at all,        outcome pass   COMPLETED  state=completed
approved verdict,         outcome pass   COMPLETED  state=completed
rejected then approved,   outcome pass   COMPLETED  state=completed   (the correction path)
rejected verdict,         outcome fail   COMPLETED  state=failed      (a rejection must let a step fail)
```

The two resolutions do not conflict. If PCCR-005 is ever approved, fewer verdicts exist and the
guard simply has less to find.

---

## Recommendation

**PCCR-005_DEFER.**

Every Phase D review requirement is met without it:

* a review-required step completing with no verdict — **0**, refused by the frozen kernel at §3g;
* a rejected review progressing forward — **0**, refused by `a01_phase_c_step_run_review_verdict`
  on all 257 steps;
* an alias self-review accepted — **0**, `fn_kernel_reviewer_independent` resolves both identity
  vocabularies before comparing.

What is **not** met, and is the only reason this document exists: *review rows accepted for
non-review steps* is not 0 — the service still accepts the record. It is no longer consequence-free,
which was the actual danger. Narrowing the frozen service is a tidier contract, and it is his call
whether a tidier contract is worth amending a frozen subject for.

Until he writes the approval sentence, `fn_kernel_review_decide` keeps its frozen body, and no
migration, script or document in this repository may record the approval on his behalf.
