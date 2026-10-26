# Claude prompt — shared autonomy foundation

Audit existing `company_event`, `event_subscription`, `event_delivery`, `workflow`, `workflow_step`, `org_tasks`, `org_action_executor`, `decision_*`, `outcome_record`, `agent_runs`, `os_audit_log`, kill switches and cron jobs. Then implement the minimum extensions required by this folder without duplicating working structures.

Deliver:

1. Event emitter coverage report for every customer, supplier, RFQ, quote, transaction, message, document, marketing, finance, security and deployment mutation.
2. Durable workflow-run/step implementation with leases, idempotency and retry.
3. Executor coverage report comparing workflow action classes to registered real executors.
4. Safe executor registrations for the agreed P0/P1 actions.
5. Unified decision-trace endpoint and UI contract.
6. Observe/Control mode enforcement.
7. Tests for duplicate delivery, worker crash, provider outage, timeout, rollback and dead-letter recovery.
8. No production deployment; return staging results and rollback migration.
