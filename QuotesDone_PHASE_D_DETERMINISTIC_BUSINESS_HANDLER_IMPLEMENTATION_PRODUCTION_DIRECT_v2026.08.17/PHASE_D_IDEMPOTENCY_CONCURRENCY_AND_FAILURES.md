# Idempotency, Concurrency and Failure Semantics

Every mutation defines business idempotency scope, stable key, existing-result response and zero orphan traces/effects.

Use authoritative locks for registration, run/step/task, assignment, quote revision, money and effect dedupe.

Failure classes: validation, authority, rule, gate, retryable infrastructure, terminal provider, concurrency, dependency unavailable, capability unavailable, cancellation/supersession.

A failed operation cannot leave partial workflow/task/trace/effect/financial state. Use one transaction or explicit compensation.

Retries preserve first attempt/failure and never create a second business effect.
