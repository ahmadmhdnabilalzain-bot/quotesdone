# Phase B — invariant results

All measured against production `htdblwldjkcgjvmqkbeh` on 15 Aug 2026, after deployment.
Zero paid inference: no OpenRouter request, no other paid provider call, no LLM anywhere in
this phase.

```bash
node scripts/checks/phase_b_invariants.test.mjs
node scripts/checks/phase_b_guards_reject_injected_defects.test.mjs
node scripts/phase_b/validate_package.mjs
```

| suite | result |
| --- | --- |
| `fn_phase_b_invariants()` + package checksums + activation checks | **77 / 77 pass** |
| injected-defect suite — do the guards actually fire? | **18 / 18 fire** |
| package validation against the live organization | **84 / 84 pass** |

## Package counts, all exact

30 workflows · 257 steps · 161 handoffs (47 cross-department) · 56 business objects ·
54 business rules · 50 exceptions · 34 SLA policies · 32 gates · 347 events ·
14 workflow states · 35 workflow transitions · 11 step states · 19 step transitions ·
10 founder boundaries.

60 of 60 package files verified against `SHA256SUMS.txt`.

## Identity and ownership

| invariant | result |
| --- | --- |
| steps with an accountable owner | 257 of 257 |
| unknown accountable step owners | 0 |
| inactive accountable step owners | 0 |
| steps with multiple accountable owners | 0 |
| workflows without an accountable owner | 0 |
| overlay accountable outside its declared scope | 0 |
| dynamic placeholder holding accountability | 0 |
| canonical roles unrepresented | 0 of 90 |
| departments unrepresented | 0 of 10 |
| category overlays governed | 86 |

The one overlay-accountable step in the package is `W14-S05 Validate technical completeness`, an
`analysis` step inside quotation evaluation. That is the single exception the master spec
declares, and `fn_phase_b_owner_guard` narrows it further: an overlay may be accountable only
for an `analysis` step in W05, W06, W07, W10 or W14, and never elsewhere.

## Review, authority and business integrity

| invariant | result |
| --- | --- |
| creator/final-reviewer collisions | 0 |
| workflow owner is also its own reviewer | 0 |
| exception escalating to its own detector | 0 |
| overlay with dispatch, payment, reveal or release authority | 0 |
| onboarding role deciding its own supplier's verification | 0 |
| payment executor reconciling its own action | 0 |
| release decided by an implementer | 0 |
| founder boundaries with no gate anywhere in scope | 0 of 10 |
| dispatch start event requires quote readiness | enforced |
| dispatch start event requires an approved supplier-safe package | enforced |
| dispatch steps without an idempotency scope | 0 of 9 |
| mutable accepted-terms record | 0 |
| mutable approved supplier-safe package | 0 |
| platform rewrite of a supplier quotation | 0 |

## The eighteen injected defects, and what refused each one

A constraint that has never refused anything is indistinguishable from no constraint. Each case
runs inside a transaction that always ends in `rollback`, and the suite asserts the row counts
are unchanged afterwards — they were: 257 steps, 161 handoffs, 50 exceptions before and after.

| injected defect | refused by |
| --- | --- |
| step with no accountable owner | `fn_phase_b_owner_guard` (before the NOT NULL) |
| two owners for one step | `phase_b_workflow_step_pkey` |
| owner that does not resolve | `fn_phase_b_owner_guard` |
| inactive (retired) owner | `fn_phase_b_owner_guard` |
| alias stored instead of the canonical id | `fn_phase_b_owner_guard` |
| next step pointing at a step that does not exist | `graph.impossible_next_step_references` |
| undeclared state transition `completed -> active` | `fn_phase_b_transition_allowed` |
| creator is its own reviewer | `phase_b_step_creator_not_reviewer` |
| creator/reviewer collision through two aliases | `fn_phase_b_resolve_role` comparison |
| overlay given dispatch authority in W12 | `fn_phase_b_owner_guard` |
| overlay owning a decision step inside its own scope | `fn_phase_b_owner_guard` |
| handoff naming a sender who does not own the step | `fn_phase_b_handoff_guard` |
| handoff whose sender is its receiver | `phase_b_handoff_two_parties` |
| owner change with no handoff contract | `handoff.owner_change_without_contract` |
| exception escalating to its own detector | `phase_b_exception_independent_escalation` |
| every founder gate removed | `authority.founder_boundary_without_any_gate` |
| closure attempted with an open blocker | `fn_phase_b_closure_blockers` |
| closure attempted with a mandatory step incomplete | `fn_phase_b_closure_blockers` |

## Three defects found in the committed package

The package is checksummed and was not edited. Each correction lives in
`scripts/phase_b/lib/identity.mjs`, is applied once when the deliverables are derived, and is
recorded in `public.phase_b_package_erratum` with its evidence.

**EX-006 is short one cell.** `escalation_owner_role_id` holds
*"Block activation/verification and correct displayed/recorded version."* — a sentence, where
the other 49 rows hold a role id — so `required_response` and `closure_condition` are each
shifted one column left and the last column is empty. Corrected to escalate to
`general_counsel`: the detector is `compliance_and_privacy_officer`, so escalation cannot return
to the same identity; terms text is founder-reserved under FDR-002 and the founder boundary
mapping assigns *"General Counsel blocks until approval"* under FDR-007.

**W13's primary object does not exist.** The workflow registry names `notification_delivery`;
the business object registry has `notification` and `notification_attempt` and no third row.
Corrected to `notification` — the record that reaches a delivered/failed/suppressed state.
`notification_attempt` is the per-try child.

**W22 has no closure-typed step.** It is the only one of the 30. Its last step, `W22-S07 Release
go/no-go`, is typed `decision` and jumps straight to `WORKFLOW_COMPLETE`, so GATE-008 (closure
completeness) had nothing to attach to in product delivery. The closure anchor is derived as
`step_type = 'closure' OR next_step_if_pass = 'WORKFLOW_COMPLETE'`, which selects the identical
step for the other 29 workflows — verified, including that no closure-typed step is ever
non-final and no non-final step reaches `WORKFLOW_COMPLETE`. This attaches the gate to W22
rather than leaving it unenforced, keeps the declared 257-step count, and changes no step, owner
or output.

## Five checks that were wrong before the package was

Recorded because the failure mode matters more than the fix.

**The negation-blind one.** `authority.payment_executor_reconciles_own_action` classified a step
as the payment executor if its `required_action` matched `/execut|captur|charg|disburs|payout/`.
W16-S06's action reads *"Reconcile provider, transaction, invoice and ledger records
**independently of the payment executor**"* — so the step whose entire purpose is to be separate
from the executor was classified as the executor. It now selects money-moving steps by what they
*produce* (`required_output` naming a payment request, provider event or transaction state).

**The one that measured the wrong subject.**
`integrity.dispatch_without_quote_ready_gate` looked for a gate *named* quote-ready scoped to
W12. Readiness is decided in W05 under GATE-011 and consumed by W12 through its start event, so
the check was asking a question the invariant does not ask. It now asserts the actual
guarantee: W12 cannot start without quote readiness, and the gate establishing it exists.

**Three that assumed a vocabulary the package does not use:** a terminal-target list missing
`CORRECTION_OR_REJECTION_PATH` and `WORKFLOW_BLOCKED` (111 false positives); a rule that no
transition may leave a terminal state, when `completed -> superseded` is explicitly declared;
and a founder-gate rule demanding a gated step in every scoped workflow, when several boundaries
are constraints rather than approval events.

## And one defect in the test suite itself

The first run of the injected-defect suite reported that two handoff guards had **accepted**
their defects. They had not. Five cases targeted `H-W12-01-02`, a handoff id that does not
exist: the `UPDATE` matched zero rows, raised nothing, and silence was read as acceptance.

A zero row count cannot tell a dead guard from an injection that never landed. Every mutating
case now derives its id from the live registry and wraps the statement so it raises
`INJECTION MISSED` when it matches no row.

## Phase A, still frozen

| | approved | live after Phase B |
| --- | --- | --- |
| `fn_phase_a_baseline_drift()` | 0 rows | **0 rows** |
| `fn_phase_a_organization_violations()` | 0 | **0** |
| active departments | 10 | 10 |
| canonical roles | 90 | 90 |
| category overlays | 86 | 86 |
| `org_workflow_ownership` | 30 | 30 |

`org_workflow_ownership` is inside the frozen Phase A digest, so the package had to agree with
it rather than the reverse. All 30 workflows' accountable owners and independent reviewers were
compared after alias resolution: **0 conflicts**. No Phase A change request is required.

## Phase boundaries

| | |
| --- | --- |
| OpenRouter requests | **0** |
| paid inference requests | **0** |
| paid inference cost | **USD 0.00** |
| LLM routes released from the hold | 0 of 8 — all 8 still open until 2126 |
| cron jobs created by Phase B | 0 |
| cron jobs total / active | 205 / 186, unchanged from preflight |
| provider routes activated | 0 |
| autonomous executors activated | 0 |
| synthetic customers created | 0 (`public.customers` = 0 rows) |
| synthetic inquiries created | 0 (`public.inquiries` = 0 rows) |
| workflow runs created | 0 (`public.workflow_run` = 323, unchanged) |
| notifications sent | 0 |
