# Phase B Founder Acceptance Checklist

## A. Scope separation

- [ ] Phase A remains frozen.
- [ ] No knowledge, tools, models, prompts, traces or certification work was performed.
- [ ] No OpenRouter or paid inference was used.
- [ ] No synthetic business data was created.
- [ ] No workflow automation, provider route or cron job was activated.

## B. Canonical workflows

- [ ] Exactly 30 workflows exist.
- [ ] Every workflow has one accountable owner.
- [ ] Every workflow has a start event and required end state.
- [ ] Every workflow has a primary business object.
- [ ] Every workflow has explicit founder boundaries.
- [ ] Every workflow has a closure path.

## C. Steps and ownership

- [ ] Exactly 257 steps exist.
- [ ] Every step has one accountable owner.
- [ ] All 90 roles are represented.
- [ ] All 10 departments are represented.
- [ ] No inactive or unknown role owns a current step.
- [ ] No step has two accountable owners.
- [ ] No required step is unreachable.
- [ ] No step can silently bypass a predecessor gate.

## D. States and transitions

- [ ] Workflow states and transitions are complete and valid.
- [ ] Step states and transitions are complete and valid.
- [ ] Cancellation, expiry, retry, rejection and supersession preserve history.
- [ ] No terminal record is silently rewritten.
- [ ] No invalid transition can be applied.

## E. Handoffs

- [ ] All 161 owner changes have handoff contracts.
- [ ] All 47 cross-department handoffs name sender, receiver, packet, acceptance, rejection and SLA.
- [ ] A sent message is not counted as an accepted handoff.
- [ ] Every rejected handoff returns to an accountable owner.

## F. Business rules and gates

- [ ] All 54 canonical business rules are represented.
- [ ] All 32 global gates are represented.
- [ ] Founder-reserved decisions are mapped to affected workflows.
- [ ] No creator/reviewer conflict remains.
- [ ] Category overlays cannot dispatch, approve suppliers, reveal identity, move money or approve releases.
- [ ] Supplier-safe approval, quote readiness and supplier verification are hard dispatch gates.
- [ ] Payment reconciliation is a hard reveal gate.

## G. Exceptions and timers

- [ ] All 50 exception patterns have detection owner, escalation owner, response and closure.
- [ ] All waiting states have a timer/escalation policy.
- [ ] No exception can disappear into an unread queue.
- [ ] Unknown monetary, privacy, security or legal state remains blocked and visible.

## H. Existing-code reconciliation

- [ ] Every current workflow/function/trigger/cron/event/UI path is mapped to a canonical workflow or classified.
- [ ] Duplicate and conflicting paths are identified.
- [ ] Dead code is identified.
- [ ] Missing runtime connections are explicitly deferred to Phase C.
- [ ] No code path is declared working merely because a table/function exists.

## I. Production-direct protocol

- [ ] Forward migration committed before deployment.
- [ ] Exact rollback committed.
- [ ] Aborted transaction rehearsal passed.
- [ ] Pre-rehearsal and post-abort fingerprints match.
- [ ] Production deployment applied only the committed migration.
- [ ] Post-deployment Phase A and Phase B invariants pass.
- [ ] Repository and production are in parity.
- [ ] No user, supplier, inquiry, payment or notification data was created or deleted.

## Final verdict

Claude must end with exactly:

`PHASE_B_READY_FOR_FOUNDER_APPROVAL`

or

`PHASE_B_NOT_READY`
