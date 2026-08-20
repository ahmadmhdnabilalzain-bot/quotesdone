# PCCR-002 — Phase C change request

**Status: RAISED, NOT APPROVED.** Section 11 is the only element of this document that is not
measured, and it is not mine to fill.

`PHASE_D_CHANGE_CONTROL.md` line 7 requires a Phase C change request for a kernel contract change.
This one is written **before** the change, unlike PCCR-001, which was written after.

**Scope: one amendment.** `public.phase_c_freeze_amendment` row `5`.

| id | subject | frozen object | file |
|---:|---|---|---|
| 5 | `handoff_service` | `fn_kernel_handoff_accept(p_input jsonb)` | `phase_d_e14_the_kernel_opened_a_step_into_a_run_it_would_not_let_anyone_complete.sql` |

Frozen baseline digest, read from `phase_c_frozen_subject` before the change:
`c84ba506288819caabe1a16df9a8a21b204ee2b47a761773ff6c08c0d941e90b`.

---

## 1. Observed problem

**No step in the estate could ever reach `EXECUTED`.** Phase D's deliverable is 257 deterministic
business handlers that the estate executes. Two independent acceptance audits, and my own drive of
all thirty workflows, recorded zero. `public.phase_d_effect_ledger` has never held a committed row.

The cause is eleven lines of ordering inside `fn_kernel_handoff_accept`. It calls
`fn_kernel_open_step` — which, since D36, dispatches the Phase D handler — and only afterwards sets
the workflow run back to `active`:

```
  v_opened := public.fn_kernel_open_step(jsonb_build_object( ... ));   -- line 84: dispatches Phase D

  -- The run is running again. waiting_handoff -> active and waiting_review -> active are both
  -- declared in phase_b_workflow_transition; the guard on phase_c_workflow_run enforces it.
  if r.state is distinct from 'active' then
    update public.phase_c_workflow_run set state = 'active' where run_id = r.run_id;   -- line 95
  end if;
```

So the kernel opens a step into a run that, for the duration of the handler's work, it still
considers not to be running. The handler's own effect for a `KERNEL_ONLY_TRANSITION` step is to
complete that step through `fn_kernel_step_complete`, and `fn_kernel_step_complete` refuses:

> `workflow run 16563 is in state waiting_handoff, not active — a step cannot be completed against
> a run that is not running (k3_run_not_active)`

The kernel opens the step, tells Phase D to run it, and then refuses the only thing Phase D can do
with it. The author's own comment — *"The run is running again"* — states the intent; the statement
that carries it out is simply below the call instead of above it.

## 2. Evidence

All measured against `htdblwldjkcgjvmqkbeh` on 2026-08-20 in aborted transactions. Residue
(`fn_phase_d_fixture_residue()`) was 0 before and after every probe.

1. **Estate-wide drive, thirty workflows, one transaction.** 207 `phase_d_dispatch` rows.
   `EXECUTED` 0. `phase_d_effect_ledger` 0.
2. **W01 driven step by step.** W01-S05 clears every applicable hard rule and every applicable hard
   gate, reaches its handler, and the dispatch row records
   `pd_rule_refused` carrying the kernel's `k3_run_not_active`. The refusal comes from inside
   `fn_phase_d_handler_execute`, not from any Phase D rule.
3. **The same function answers differently depending on when it is called.**
   `fn_phase_d_step_context(step_run_id)` called from inside the dispatch records `to_state`
   unresolved for W01-S04/S05/S06; called against the same step runs a moment after the accept
   returns, it resolves. That half was closed separately by
   `phase_d_e12_the_resolver_nulled_a_fact_the_gate_exists_to_judge.sql`, which stopped the resolver
   re-running GATE-006's own test. After E12, GATE-006 refusals across the estate fell from 12 to 4
   and W01-S05 progressed from a gate refusal to the kernel refusal above.
4. **The counterfactual, driven through the real entry point.** With the run already `active` — the
   state this change produces — `fn_phase_d_dispatch_step` for the same W01-S05 step run returns
   `{"outcome":"EXECUTED","handler_id":"hdl_w01_s05","effect_id":7351,"dispatched":true}` and
   `phase_d_effect_ledger` holds one row. Nothing else was varied.

## 3. Current behaviour, before the change

`fn_kernel_handoff_accept` records the handoff decision, resolves the successor owner, calls
`fn_kernel_open_step` for the successor step, and then, if the run is not already `active`, updates
`phase_c_workflow_run.state` to `active`. Phase D is dispatched inside `fn_kernel_open_step`, so it
runs while the run still holds the state it is leaving.

## 4. Proposed behaviour, and what will be applied

Move the run-state update **above** the `fn_kernel_open_step` call. Nothing else in the function
changes: the same condition (`if r.state is distinct from 'active'`), the same statement, the same
target row. `r` is read at the top of the function and is unaffected by the move.

The transition `waiting_handoff -> active` is declared in `phase_b_workflow_transition` and enforced
by `z20_phase_c_workflow_state_guard`, so the guard's opinion of the write is identical either side
of the move. If `fn_kernel_open_step` raises, the whole transaction rolls back exactly as before.

## 5. Owner, reviewer, state and gate impact

- **Owner:** `chief_of_staff` is the correction owner recorded on GATE-006, the gate whose evidence
  this ordering starved. The change is to a kernel contract, so the accountable owner for the
  contract is the kernel itself; no Phase B accountability moves.
- **Reviewer:** independent acceptance auditor, read-only, against a frozen tree.
- **Workflow states:** unchanged. No state, transition or guard is added, removed or redefined. The
  same transition happens; it happens eleven lines earlier.
- **Gates:** unchanged. No gate contract, evidence key or predicate is touched. GATE-006 begins to
  receive the evidence it was always declared to read.
- **Phase B freeze:** untouched. `fn_phase_b_baseline_drift()` covers workflow ownership, order,
  states, transitions, gates, business rules, handoff accountability, overlay authority and founder
  boundaries; none of them appear in this diff. Verified 0 rows after the change.

## 6. Security, privacy and financial impact

- **Security:** none. `CREATE OR REPLACE` preserves the ACL, so no grant moves. The function stays
  `SECURITY DEFINER` with the same `search_path`. No new caller, no new door.
- **Privacy:** none. No column, table or payload is read or written that was not read or written
  before.
- **Financial:** none, and this is the part that deserves the most care, because the change lets
  handlers execute that could not execute before. Three independent boundaries still hold and were
  re-measured after the change:
  - `fn_phase_d_handler_execute` fails closed on `capability_dependency <> 'NONE'` and on
    `provider_dependency <> 'NONE'` for any `execution_context` other than `test`. The kernel path
    hard-codes `production`, so every paid-inference and external-provider step still refuses.
  - The founder's provider and automation holds are untouched; 23 active cron jobs, none
    reactivated.
  - `ai_cost_log` unchanged across every probe, and the zero-residue business tables
    (`customers`, `inquiries`, `quotes`, `transactions`, `notifications`) stay at 0.

## 7. Backward compatibility

The signature, return shape and error codes of `fn_kernel_handoff_accept` are unchanged. Every
existing caller sees the same `jsonb`. The observable difference is that a successor step is now
opened into a running run, which is what every one of those callers already assumed: the previous
ordering was visible only to code that ran *inside* the open, and Phase D's dispatch is the only
such code.

## 8. Migration and rollback

- **Migration:** one `CREATE OR REPLACE FUNCTION`, applied by
  `node scripts/apply_sql.mjs scripts/sql/phase_d_e14_*.sql --apply` and verified by read-back.
- **Rollback:** re-apply the prior body, whose digest is recorded above and whose text is recoverable
  from `phase_c_freeze_amendment.prior_digest` plus the canonical routine manifest. Rolling back
  restores the pre-change behaviour exactly — including zero executed steps.
- **Rollback classification:** `REVERSIBLE_BY_REAPPLY`. No data migration, no dropped object, no
  column change.

## 9. How the freeze was respected

- `phase_c_frozen_subject.digest` is **never overwritten**.
- The amendment is recorded in `public.phase_c_freeze_amendment` with `prior_digest` pinned to the
  exact frozen baseline read before the change, `new_digest` to the body applied, and
  `change_request_ref = 'PCCR-002'` — a column added by
  `phase_d_e13_an_amendment_that_excuses_itself.sql` precisely so that an amendment can no longer
  excuse a digest move on its own authority.
- `fn_phase_c_freeze_drift()` now carries `frozen_subjects_changed_with_no_change_request`,
  expected 0, and `amendments_awaiting_founder_approval`, which will read 4 of 4 until a person
  fills `approved_by` / `approved_at`.
- `scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` asserts that this document
  exists, is tracked by git, names amendment 5 and names
  `fn_kernel_handoff_accept(p_input jsonb)`. A row without its artefact fails CI.

## 10. Why this is a change request and not a defect fix

The ordering is a defect by any reading — the kernel refuses the work it just commissioned. It would
still be a kernel contract change, and `PHASE_D_CHANGE_CONTROL.md` does not carve out defects. The
distinction the control document draws is between a change that is recorded and one that is not, and
this is the recorded kind.

## 11. Founder approval requirement

**Outstanding. This section is for the founder, and nothing in this session may fill it.**

The change control document requires founder approval for a kernel contract change. What is being
asked is narrow: permission for the amendment-table route — `phase_c_freeze_amendment` pinned to the
exact prior digest, with a written change request and an approval reference — to be the agreed
mechanism for amending a frozen Phase C contract, and approval of this specific amendment.

| field | value |
|---|---|
| `approved_by` | *(unfilled)* |
| `approved_at` | *(unfilled)* |
| covers | PCCR-002, amendment 5, `fn_kernel_handoff_accept(p_input jsonb)` |

PCCR-001 §11 carries the same outstanding request for amendments 1, 2 and 4.
