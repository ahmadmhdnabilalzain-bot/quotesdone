# Phase D Master Specification

## Objective

Implement, connect and deterministically verify the business handler for every frozen Phase B workflow step.

Phase C owns entry, workflow start, progression, cancellation, handoffs, review, outbox, traces and refund-only founder approval. Phase D supplies the actual business behavior of the 257 steps.

## Required end state

- Every step has one authoritative handler binding.
- Shared implementations are allowed only with explicit per-step bindings.
- No required handler remains `DEFERRED_RUNTIME_IMPLEMENTATION`.
- Intelligence-dependent steps have a complete capability boundary and fail closed until Phase E.
- Provider-dependent steps have a complete disabled/mock adapter.
- Frontend, API, Edge Functions, database and storage use the same canonical business services.
- Every write uses the kernel and approved business-object services.
- All 30 workflows can be driven to explicit closure with deterministic fixtures and zero paid inference.
- No live email, WhatsApp, publication, payment or refund occurs.
- Founder approval remains limited to a specific refund approve/reject decision.

## Final handler statuses

- `VERIFIED_EXISTING_HANDLER`
- `REPAIRED_EXISTING_HANDLER`
- `NEW_DETERMINISTIC_HANDLER`
- `CAPABILITY_BOUNDARY_READY`
- `EXTERNAL_ADAPTER_READY_DISABLED`
- `COMPATIBILITY_WRAPPER_TO_CANONICAL`
- `INTENTIONALLY_INACTIVE_WITH_FROZEN_REASON`
- `BLOCKED_DEFECT`

Phase D requires `BLOCKED_DEFECT = 0`.

## Reconciliation actions

- `KEEP_VERIFIED`
- `KEEP_BETTER_EXISTING`
- `REPAIR`
- `REPLACE_WITH_CANONICAL_HANDLER`
- `IMPLEMENT`
- `WRAP_TO_CANONICAL`
- `DISABLE_DUPLICATE`
- `RETIRE_HISTORICAL`

An object with no real caller is not implemented.

## One execution pattern

```text
canonical task
→ Phase C kernel validation
→ Phase D handler binding
→ typed input
→ rules/gates
→ optional capability/provider boundary
→ business-object service
→ typed result
→ Phase C step completion
→ handoff/next step/closure
→ factual event and trace
```

No handler may create parallel workflow/task/handoff/approval/event logic.
