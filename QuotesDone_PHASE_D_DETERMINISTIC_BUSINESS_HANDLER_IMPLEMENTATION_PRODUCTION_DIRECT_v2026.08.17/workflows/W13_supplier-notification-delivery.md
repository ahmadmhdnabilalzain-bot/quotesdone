# W13 — Supplier notification delivery

- **Domain:** communications
- **Criticality:** high
- **Profile:** delivery_cycle
- **Primary object:** `notification_delivery`
- **Accountable role:** `lifecycle_channel_operations_specialist`
- **Start event:** Approved queued notification
- **Required end state:** Delivered/failed/suppressed state
- **Founder boundary:** Consent and sender policy enforced

## Purpose

Deliver approved messages through permitted channels with consent, suppression, retry and terminal-state handling.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W13-S01` | Accept approved notification | intake | `lifecycle_channel_operations_specialist` |  |  | `W13-S02` |
| 2 | `W13-S02` | Apply consent and suppression rules | review | `lifecycle_channel_operations_specialist` | compliance_privacy_officer |  | `W13-S03` |
| 3 | `W13-S03` | Select permitted channel and template | decision | `communications_manager` | lifecycle_channel_operations_specialist |  | `W13-S04` |
| 4 | `W13-S04` | Attempt delivery | execution | `lifecycle_channel_operations_specialist` |  |  | `W13-S05` |
| 5 | `W13-S05` | Retry eligible failure | execution | `lifecycle_channel_operations_specialist` |  |  | `W13-S06` |
| 6 | `W13-S06` | Escalate terminal delivery failure | handoff | `communications_manager` | customer_support_specialist; supplier_onboarding_specialist; rfq_success_specialist |  | `W13-S07` |
| 7 | `W13-S07` | Close notification delivery | closure | `lifecycle_channel_operations_specialist` |  |  | `WORKFLOW_COMPLETE` |

## Phase D requirement

For every step populate the handler matrix and prove actual caller, authoritative handler, typed contract, object mutations, rules/gates, state, idempotency, failure, review/handoff, trace and external-effect policy.

## Workflow acceptance

- deterministic happy path reaches required end state;
- failure/block path is visible;
- cancellation leaves no active derived work;
- replay creates no duplicate effect;
- no live external effect;
- no paid inference;
- no founder approval except a specific refund in W17.
