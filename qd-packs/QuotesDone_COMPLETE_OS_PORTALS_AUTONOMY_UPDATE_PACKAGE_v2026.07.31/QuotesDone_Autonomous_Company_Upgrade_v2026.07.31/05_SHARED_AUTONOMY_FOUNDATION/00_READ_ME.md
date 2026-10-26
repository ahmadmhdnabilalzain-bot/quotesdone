# Shared autonomy foundation

This is the most important upgrade. QuotesDone already has agents, tasks, workflows, events, policies and many scheduled jobs. The remaining challenge is making their execution durable and trustworthy.

The current Chief of Staff execution engine processes a small bounded batch and only performs a real side effect when an action class is present in `org_action_executor`; otherwise it stores a generated deliverable and marks work done/prepared. The executor registry in the export contains only a limited set of real actions. This is insufficient for a fully unattended company.

Implement the following before adding advanced visual features:

1. Reliable event outbox and schema registry.
2. Durable workflow runs and step runs.
3. Universal correlation/causation IDs.
4. Idempotency and execution leases.
5. Expanded action registry.
6. Unified decision trace.
7. Dead-letter and compensation paths.
8. Default Observe Mode and rare Control Mode.
9. Measured outcomes and executor reliability scores.
10. Model-free operation for deterministic tasks.
