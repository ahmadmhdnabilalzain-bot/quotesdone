
# Phase C Zero-Cost Test Plan

## Environment controls

Enforce:

```text
NO_PAID_AI=true
OPENROUTER_DISABLED=true
AI_PROVIDER_MODE=mock
```

Paid inference secret values should be absent from the test process. Network calls to known paid inference endpoints must be intercepted and fail the test.

## Gate C0 — Baseline

- Phase A baseline/tags/registries verified.
- Phase B baseline/tags/registries and effective errata verified.
- Expected counts exact.
- Production ref exact.

## Gate C1 — Component inventory

Inventory and classify all:

- routed frontend mutations;
- API actions;
- Edge Functions;
- database functions/procedures;
- triggers;
- cron jobs;
- event subscriptions;
- queue/outbox consumers;
- webhooks;
- storage triggers/policies;
- agent/task runners.

No active state-changing component remains unowned or unclassified.

## Gate C2 — Identity and ownership

Test canonical, legacy, merged, packaged role and title resolution. Unknown/inactive/currently blocked identities refuse. New writes use canonical IDs.

## Gate C3 — Frozen workflow binding

- 30/30 workflow runtime bindings.
- 257/257 step bindings or explicit `DEFERRED_RUNTIME_IMPLEMENTATION` with accountable owner and Phase D action.
- 161/161 handoff bindings.
- 347/347 event producer/consumer classifications.
- 32/32 gate enforcement classifications.
- 54/54 rule enforcement classifications.

Phase C should implement the core runtime boundary and classify remaining business handlers; it may defer business-correctness tests to Phase D, but cannot leave an unknown owner or unknown path.

## Gate C4 — Founder command center

Run all command acceptance cases with deterministic fixtures.

Require:

- founder authentication;
- immutable raw message;
- safe intent or clarification;
- exact workflow and role;
- atomic command/task creation;
- task IDs returned immediately;
- status/cancel/reprioritize/explain paths;
- multi-department plan;
- refund approval semantics;
- no founder approval for non-refund actions;
- no raw side effect;
- non-null traces.

## Gate C5 — Authority and reviewer independence

Inject unknown actions, self-review aliases, founder-approval misuse, policy bypass and invalid reviewer assignments. All must refuse without state change.

## Gate C6 — Trace coverage

For test fixtures:

- every command has trace;
- every task has trace;
- every workflow/step mutation has trace;
- every consequential action has decision trace;
- every tool call has result trace;
- every system execution has accountable role.

## Gate C7 — Events, handoffs and idempotency

Test duplicate, delayed, out-of-order, rejected and retried messages. No duplicate side effect. First failure preserved. Dead-letter visible.

## Gate C8 — Output validation

Feed valid, malformed, incomplete and truncated fixtures. Invalid output cannot mutate state.

## Gate C9 — Provider block and cost

Assert:

```text
OpenRouter requests = 0
Other paid inference requests = 0
Paid inference cost = USD 0.00
```

Do not infer zero from a caught query error. Measure from network guard and applicable cost logs.

## Gate C10 — Production rehearsal/deploy

- exact committed database SQL rehearsed and rolled back;
- no fingerprint drift after rehearsal;
- deployed source hashes match Git;
- all Phase A/B/C invariants pass after deployment;
- no activation state unintentionally changed;
- no persistent test fixtures remain.
