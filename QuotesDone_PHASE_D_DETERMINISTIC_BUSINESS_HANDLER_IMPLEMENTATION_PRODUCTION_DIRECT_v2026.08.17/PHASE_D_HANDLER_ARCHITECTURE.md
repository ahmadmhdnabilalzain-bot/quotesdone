# Canonical Handler Architecture

Each step binding includes handler/version/class, schemas, owner/reviewer, rules/gates, object reads/writes, idempotency, locks, failure contract, compensation, capability/provider dependency and trace policy.

Use an existing better executor or one canonical handler executor that:

1. resolves the frozen step;
2. locks run/step/task;
3. validates actor/authority;
4. assembles typed inputs;
5. enforces rules/gates;
6. executes the handler;
7. validates output;
8. persists through canonical object services;
9. creates review/effect records;
10. returns to the Phase C step engine.

### Step families

- Intake: preserve exact source and validate initial evidence.
- Analysis: deterministic calculations/rules; optional later capability request.
- Execution: one authorized state change; external effects use outbox.
- Review: independent immutable verdict.
- Decision: evidence, authority and stable outcome.
- Handoff: frozen packet, acceptance, SLA and return owner.
- Measurement: authoritative denominator and formula.
- Closure: all mandatory blockers resolved.

### Capability boundary

Implement typed request/output, evidence IDs, confidence, validation, mock fixture and production fail-closed state. A Phase D mock cannot complete a real business step.

### Provider boundary

Record intent, durable outbox, idempotency, request/result ID, retry/dead-letter and disabled/mock mode.

### Direct-write prohibition

Handlers may not independently create or mutate workflow runs, step runs, tasks, handoffs, traces, reviews, refund decisions or domain events.
