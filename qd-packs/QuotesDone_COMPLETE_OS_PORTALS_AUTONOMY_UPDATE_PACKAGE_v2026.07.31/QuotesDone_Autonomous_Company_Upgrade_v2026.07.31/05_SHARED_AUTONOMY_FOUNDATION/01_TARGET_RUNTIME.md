# Target runtime

```text
Business mutation / scheduled trigger / founder objective
                ↓
Reliable event outbox
                ↓
Canonical company_event (correlation + causation)
                ↓
Event subscriptions
                ↓
Durable workflow_run
                ↓
Workflow step: retrieve data/knowledge
                ↓
Decision engine: rules + policy + authority + confidence
                ↓
Action executor (idempotent real side effect)
                ↓
Decision trace + audit + outcome record
                ↓
Retry / compensation / dead-letter if needed
                ↓
Executive Observe Mode stream
```

## Action classes that should receive explicit executors

Examples, subject to current-code audit and policy:

- supplier_profile_extract
- supplier_document_remind
- supplier_document_reconcile
- supplier_invite
- supplier_approve_clean
- inquiry_route
- inquiry_qualify
- inquiry_dispatch
- quote_extract
- quote_compare
- comparison_report_generate
- customer_notify
- supplier_notify
- email_send_outbox
- whatsapp_send_outbox
- social_publish
- blog_publish
- seo_publish
- finance_ingest
- ap_duplicate_scan
- gl_post_safe
- refund_prepare / refund_execute_gated
- backup_run
- dr_test
- knowledge_ingest
- knowledge_refresh
- metric_alerts
- incident_contain

Every executor must declare risk, reversibility, idempotency strategy, required authority, timeout, retry policy and compensation.
