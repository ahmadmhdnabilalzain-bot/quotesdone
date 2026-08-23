# Claude Code Master Prompt — QuotesDone Phase D

Implement **Phase D: deterministic business handlers and code correctness**.

This is implementation, not planning-only and not professional AI certification.

## Precondition

Before editing, verify a fresh independent audit returned `PHASE_C_FINAL_ACCEPTANCE_PASS` and Phase C is founder-approved, tagged and frozen.

If not, stop with:

`PHASE_D_BLOCKED_PHASE_C_NOT_FROZEN`

## Frozen baselines

Do not alter without formal change request and founder approval:

- 10 departments;
- 90 canonical roles;
- 86 category overlays;
- reporting/reviewer boundaries;
- 30 workflows;
- 257 steps;
- effective owners;
- handoffs;
- 54 rules;
- 32 gates;
- states/transitions;
- founder boundaries;
- Phase C kernel contracts.

Use PBCR-001: W14-S05 belongs to `quote_evaluation_specialist`; the overlay contributes but never owns the task.

## Zero-cost

Enforce:

```text
NO_PAID_AI=true
OPENROUTER_DISABLED=true
AI_PROVIDER_MODE=mock
PHASE_D_EXTERNAL_EFFECT_MODE=mock
```

Any paid-provider request is failure.

Do not run V3 certification, paid models, live email/SMS/WhatsApp, live social publishing, live/test charges or refunds, persistent demo accounts or automatic activation.

## Production-direct

For each increment: inspect read-only, implement/test locally, commit migration/rollback/evidence, rehearse exact SQL in aborted transaction, deploy committed increment, verify live, rollback on mandatory failure. Production may not be ahead of main.

## D0 — Reconcile all current code

Export live effective A/B/C registries and frozen hashes.

Populate every attached matrix using actual frontend/API/Edge Function/database/trigger/cron/webhook/queue/storage/provider/test callers.

For all 257 steps assign current handler, callers, reads/writes, direct DML, rules/gates, effects, idempotency, failure and target action.

Use KEEP_VERIFIED, KEEP_BETTER_EXISTING, REPAIR, REPLACE_WITH_CANONICAL_HANDLER, IMPLEMENT, WRAP_TO_CANONICAL, DISABLE_DUPLICATE or RETIRE_HISTORICAL.

Required: 257/257 reconciled; unknown callers 0; unclassified direct business-write paths 0.

## D1 — Handler registry/executor

Every step requires explicit handler ID/version/class, input/output schema, owner/reviewer, rules/gates, object reads/writes, idempotency/locks, stable failure contract, compensation, capability/provider dependency and trace point.

Shared code is allowed; ambiguous binding is not.

Implement/preserve one canonical handler executor that validates kernel objects/actor, assembles typed inputs, enforces rules/gates, executes and validates handler output, writes through canonical object services and returns to the Phase C step engine.

Handlers may not create parallel workflow/task/handoff/event paths.

Required: 257/257 bindings; ambiguous handlers 0; handler kernel bypass 0.

## D2 — 56 business objects

Define canonical storage, read/write services, ownership/RLS, versioning, mutation, status, trace, retention, safe/raw representation and compensation.

No arbitrary page/Edge Function direct DML. Immutable evidence remains immutable. Null/no-row is failure.

Required: 56/56 reconciled; missing write service 0; append-only mutation accepted 0; cross-account access accepted 0.

## D3 — 54 rules, 32 gates, states and reviews

Map every rule/gate to a real enforcement point and machine refusal code. Test both pass/fail.

Review-required steps need immutable verdict by an independent canonical role. Alias self-review is refused.

Required: unenforced rules 0; unenforced gates 0; invalid transitions 0; self-review 0; closure with blocker 0; prose-only contracts 0.

## D4 — Handoffs

Export live effective handoffs, especially PBCR-001-affected W14 rows.

Enforce sender, receiver, packet schema, source version, acceptance, SLA, rejection, return owner, accountability transfer and closure.

Required: 100% reconciled; incomplete packet accepted 0; ambiguous receiver 0; rejected handoff advancing 0.

## D5 — Frontend/API/RLS/storage

For each user-facing step prove component→client→HTTP→service→database→visible result.

Implement server-side validation, identity/resource authority, deliberate RLS/grants and safe SECURITY DEFINER functions.

Storage: ownership path, MIME/extension/magic-byte, size, safe filename, quarantine/scan, authorized short-lived URL, approved revision.

Required: cross-account access 0; unsafe bucket policies 0; frontend actions without backend 0; launch backend features with no reachable UI/API 0.

## D6 — External effects

Implement durable effect contracts for email, WhatsApp/SMS, social, payment/refund, external storage, Apify/webhooks.

All remain mock/disabled. Require approved payload, consent, idempotency, attempt/result IDs, retries/dead-letter, trace and reconciliation.

Required: live effects 0; null success 0; refused effect counted delivered 0; duplicate effects 0.

## D7 — Finance/legal/privacy

Implement deterministic contracts for W08, W10, W15, W16, W17, W27, W28.

Only specific refund approve/reject is founder-gated.

Prove payment confirmation/reconciliation separation, reveal after reconciliation, distinct executor/reconciler, immutable refund decision, exact terms version/hash, no certificate before acceptance, approved supplier-safe payload/files, hidden customer identity and quarantined unknown money state.

No live payment/refund.

## D8 — Idempotency/concurrency/failure/cancel

Every handler defines idempotency, lock, first attempt, retry class, terminal failure, compensation and cancellation.

Test registration, step completion, assignment, quote revision, effect delivery and monetary concurrency.

Required: duplicate effects 0; cancellation active leftovers 0; retry erases first failure 0; partial rows 0.

## D9 — Capability boundaries, no model

For reasoning/document/image/creative steps implement typed capability request/output, role/context/evidence IDs, confidence, validation, timeout/failure, mock fixture and production fail-closed behavior.

Phase D mocks work only in explicit test context.

Required: capability steps without interface 0; real business steps completed from Phase D mock 0; paid model calls 0.

## D10 — Implement by waves

D0/D1 foundations; D2 W04–W17; D3 W03/W18–W21; D4 W22–W24/W29; D5 W01/W02/W25–W30; D6 full closure.

Do not advance with unresolved critical defects.

## D11 — Tests

For all 257 steps run positive, missing input, wrong actor, invalid state, duplicate, failed rule/gate and malformed output.

For all 30 workflows run happy closure, failure/block, cancellation and replay.

Use local fixtures, aborted transactions or zero-effect namespaced canaries. No persistent demo accounts.

Run `PHASE_D_INJECTED_DEFECT_CATALOG.csv`.

Every expected population uses a nonzero denominator.

## D12 — Events

Reconcile all 347 events with separate structural/runtime status, real producer/consumer/outbox/result/trace/idempotency.

Provider events may be structurally ready but externally disabled.

Required: misleading connected 0; self-loop 0; event without factual state change 0; live external event effects 0.

## D13 — Full deterministic workflow closure

Drive all 30 workflows to explicit closure with fixtures.

Required: 30/30 closed; false terminals 0; unresolved owner/successor 0; closure with blockers 0; duplicate successor tasks 0; missing traces 0; external effects 0.

## D14 — Closure report

Create every file in `PHASE_D_REQUIRED_DELIVERABLES.md`.

Report exact counts for baselines; handlers by status; all 30 workflows; objects/rules/gates/handoffs/events; security; financial/privacy; effects; cost; and later Phase E/provider/synthetic dependencies.

Do not begin Phase E.

End exactly:

`PHASE_D_READY_FOR_FOUNDER_APPROVAL`

or:

`PHASE_D_NOT_READY`
