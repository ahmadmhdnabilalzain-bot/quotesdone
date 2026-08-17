# Phase B change request — PBCR-001

**Founder reference:** `PHASE_B_CR_W14_S05_ACCOUNTABILITY`
**Raised and approved:** 17 Aug 2026, by the founder, in the session brief.
**Applied:** 17 Aug 2026 — `scripts/sql/phase_b_cr_001_w14_s05_accountability.sql`
**Record row:** `public.phase_b_change_request` where `change_request_id = 'PBCR-001'` (append-only)

```sql
set local app.phase_b_change_reason = 'PBCR-001: …';
```

---

## 1. Observed problem

W14 — Quotation Submission and Evaluation cannot reach its closure step. W14-S05 *Validate
technical completeness* is accountable to `relevant_category_overlay`, a dynamic overlay
placeholder rather than a canonical role. The execution kernel refuses to open a step whose owner
does not resolve, so the walk stops at S05 and W14 never reaches W14-S09.

## 2. Evidence

```sql
select workflow_id, verdict, detail
  from public.fn_kernel_workflow_graph_validate() where verdict <> 'OK';
```

```
W14 | REGISTRY_DEFECT | 1 reachable step(s) the engine cannot progress from; 1 successor owner(s)
                        that do not resolve to an active canonical role; 1 step owner(s)
                        unresolved; closure is topologically reachable but NOT executable: the
                        walk stops at a step the engine refuses to open
```

SUMMARY row: `unresolved_successor_owners = 1`, `owners_unresolved = 1`,
`closure_path_executable = false`, workflows with no executable closure path **1 of 30**.

```sql
select * from public.fn_phase_c_resolve_actor('relevant_category_overlay');
-- kind=unknown, role_id=null,
-- reason='no active canonical role, alias or system actor named ''relevant_category_overlay'''
```

W14-S05 is the **only** one of the 257 steps with `actor_kind = 'category_overlay'`, and
`relevant_category_overlay` is the only entry in `phase_b_dynamic_actor` besides `founder` carrying
`may_be_accountable = true`.

## 3. Current workflow and step

W14 / **W14-S05**, step_no 5, step_type `analysis`, `next_step_if_pass` W14-S06, `next_step_if_fail`
WORKFLOW_BLOCKED_OR_ESCALATED, `founder_gate` none.

| field | before |
|---|---|
| `accountable_role_id` | `relevant_category_overlay` |
| `package_accountable_token` | `relevant_category_overlay` |
| `actor_kind` | `category_overlay` |
| `contributors` | `{quote_evaluation, relevant_domain_specialist}` |
| `independent_reviewer_role_id` | `null` |

## 4. Proposed change

| field | before | after |
|---|---|---|
| `accountable_role_id` | `relevant_category_overlay` | **`quote_evaluation`** |
| `package_accountable_token` | `relevant_category_overlay` | **`quote_evaluation_specialist`** |
| `actor_kind` | `category_overlay` | **`canonical_role`** |
| `contributors` | `{quote_evaluation, relevant_domain_specialist}` | **`{relevant_category_overlay, relevant_domain_specialist}`** |
| `independent_reviewer_role_id` | `null` | `null` (unchanged) |
| `phase_b_dynamic_actor.relevant_category_overlay.may_be_accountable` | `true` | **`false`** |
| `phase_b_handoff` H-W14-04-05, H-W14-05-06 | present | **deleted** (161 → 159) |

**On the name.** The founder's amendment names the new owner `quote_evaluation_specialist`. That is
the *package accountable token*. The canonical Phase A `role_id` behind it is **`quote_evaluation`**,
whose `display_name` is exactly *"Quote Evaluation Specialist"* and which already owns the other
eight W14 steps — W14-S04's `package_accountable_token` is literally `quote_evaluation_specialist`.
So the amendment is applied by pointing the step at the existing canonical role. **No role is
created.** The Phase A role count does not move and `fn_phase_a_baseline_drift()` stays at 0 rows.

**Why the two handoffs go.** `phase_b_handoff_two_parties` is a CHECK constraint:
`sending_role_id <> receiving_role_id`. Once W14-S05 is owned by `quote_evaluation`, both edges
become `quote_evaluation → quote_evaluation` and the constraint refuses them. That is the registry
telling the truth: W14-S03 → W14-S04, also `quote_evaluation` to `quote_evaluation`, carries no
handoff edge either. `fn_kernel_workflow_graph_validate` already classifies these as *"legitimate
same-owner hops with no handoff edge (not a defect)"* and counted 66 of them; these become the 67th
and 68th. Deleting them also removes the last two rows naming `category_overlay` as a sending or
receiving department — a department that does not exist in the frozen Phase A org of ten.

## 5. Affected owners

**Gains:** `quote_evaluation` (Quote Evaluation Specialist, department `marketplace`) becomes
accountable for W14-S05, consistent with its ownership of the other eight W14 steps and with its
remit over quotation normalization, validation and comparison.

**Loses:** `relevant_category_overlay` loses accountability everywhere — it was accountable on
exactly one step — and becomes a **required technical contributor** on W14-S05. It still supplies
the category-specific technical judgement; it may not own the task or the state transition.

**Unchanged:** `relevant_domain_specialist` remains a **conditional** contributor, resolved only for
complex, multi-category or cross-trade scope. Its own `resolution_rule` already says *"Resolve only
when multi-category coordination requires it."*

Compliance, Risk, Legal and Trust roles are **not** added as standing reviewers.
`independent_reviewer_role_id` stays NULL precisely because they review only when a registered risk
or regulatory trigger requires them, and naming a standing reviewer would make that unconditional.

No canonical role is created, renamed, retired or re-departmented.

## 6. State-machine impact

None. W14-S05 keeps `step_no` 5, `step_type` analysis, its entry condition, `next_step_if_pass`
W14-S06, `next_step_if_fail` WORKFLOW_BLOCKED_OR_ESCALATED, `success_workflow_state`
`waiting_handoff` and `failure_workflow_state` `blocked`. No workflow state, step state or
transition is added, removed or re-routed.

The change makes an already-declared transition **executable** where it previously was not. No run
can become stuck by it, and no run was ever in flight at W14-S05 — the step could not be opened.

## 7. Gate and rule impact

No gate and no business rule is added, removed, weakened or re-scoped. The 32 gates and 54 business
rules are untouched. The effect on gating is **stricter, not weaker**: `fn_kernel_open_step` now has
a resolvable owner to check authority against, where before it refused the step outright.

## 8. Customer and supplier impact

None visible to either. A supplier quotation still passes commercial validation, then technical
validation, then clarification if needed. What changes is that technical validation can now
actually complete and the quotation can reach comparison — before this change, **no quotation could
pass W14-S05 at all**.

## 9. Privacy, legal and financial impact

None. No identity is revealed, no terms are accepted, no money moves, no refund authority changes,
no retention window changes. W14-S05 carries `founder_gate = none` before and after; no
founder-reserved boundary FDR-001…FDR-010 is approached.

## 10. Backward compatibility

No historical record is deleted, edited or back-dated.

- `phase_c_task` rows owned by `relevant_category_overlay` or any `category_overlay_*` role: **0**
- `phase_c_workflow_step_run` rows for W14-S05: **0**
- `phase_c_handoff_run` rows against H-W14-04-05 or H-W14-05-06: **0**

All zero because the step could never be opened. `phase_b_dynamic_actor` keeps the
`relevant_category_overlay` token, its meaning and its resolution rule; only its authority to be
accountable is withdrawn.

The exact pre-change content of both deleted handoff rows is captured verbatim in
`scripts/sql/rollback/phase_b_cr_001_w14_s05_accountability.rollback.sql` — read out of production
before the delete, not reconstructed.

## 11. Founder approval requirement

**Required, and given.** It changes step ownership and category-overlay authority, both frozen
subjects. Approved by the founder on 17 Aug 2026 in the session brief:

> "The founder approves this exact Phase B amendment … Change request ID:
> `PHASE_B_CR_W14_S05_ACCOUNTABILITY`"

---

## Digest subjects moved

`step_ownership`, `overlay_authority`, `handoff_accountability` — three of the nine subjects in
`fn_phase_b_structure_digest()`. The baseline was re-recorded after the change so the freeze
protects the amended architecture rather than the old one.

## Verification — measured, not asserted

Rehearsed first in an **aborted production transaction**
(`scripts/sql/phase_b_cr_001_w14_s05_accountability.assert.sql`):

```
W14-S05 owner ............ quote_evaluation
W14-S05 token ............ quote_evaluation_specialist
W14-S05 actor_kind ....... canonical_role
W14-S05 contributors ..... relevant_category_overlay;relevant_domain_specialist
overlay may_be_accountable f
steps with overlay actor . 0    (expect 0)
handoffs ................. 159  (expect 159)
steps .................... 257  (expect 257)
workflows ................ 30   (expect 30)
workflows not OK ......... 0    (expect 0)
unresolved successor owners 0   (expect 0)
owners_unresolved ........ 0    (expect 0)
closure_path_executable .. t    (expect true)
phase A drift rows ....... 0    (expect 0)
```

Then **executed** end to end, still inside an aborted transaction
(`scripts/sql/phase_b_cr_001_w14_s05_accountability.walk.sql`) — because a validator liking the
registry is not the same as the workflow running:

```
path ............... W14-S01 -> W14-S02 -> W14-S03 -> W14-S04 -> W14-S05
                     -> W14-S06 -> W14-S07 -> W14-S08 -> W14-S09
W14-S05 executed by  quote_evaluation
W14-S05 final state  completed
last step reached .. W14-S09          (the explicit closure step)
run state .......... completed
```

That walk accepted every handoff with a complete packet and recorded a real independent review at
W14-S08. It did not bypass one contract.

## What the walk found that no check had

Driving the run rather than validating the registry exposed a **separate, latent kernel defect**:
`fn_kernel_workflow_start` created the entry step's *outgoing* handoff run at start time, and
`fn_kernel_step_complete` created the same edge again when that step actually completed — two open
handoff runs on one edge, on **16 of the 30 workflows**. It had never been seen because no run had
ever completed an entry step carrying an outgoing edge. Fixed in
`scripts/sql/kernel_k14_start_does_not_pre_hand_off.sql`, which is a deletion.
