
# Workflow Runtime Contract

The frozen Phase B workflow registry is authoritative.

Every runtime workflow must support:

- stable workflow ID and version;
- business object ID/version;
- start event and dedupe key;
- one canonical accountable owner;
- active-step set derived from allowed transitions;
- workflow and step state guards;
- gate and rule evaluation;
- handoff creation/acceptance/rejection;
- exception and SLA handling;
- event-outbox emission;
- command/task links;
- cancellation/supersession/compensation;
- closure evidence;
- audit and trace IDs.

No UI, Edge Function, trigger or cron job may invent a parallel workflow state outside the canonical engine.

A better existing state machine may be kept only if it is demonstrably equivalent, all callers use it, and the Phase B registry maps without loss. Record `CANONICAL_BETTER_KEEP` with evidence.
