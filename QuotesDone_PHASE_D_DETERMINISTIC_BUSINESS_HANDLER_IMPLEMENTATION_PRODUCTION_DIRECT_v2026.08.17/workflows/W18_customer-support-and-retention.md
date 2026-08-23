# W18 — Customer support and retention

- **Domain:** customer
- **Criticality:** medium
- **Profile:** support_cycle
- **Primary object:** `customer_case`
- **Accountable role:** `customer_success_director`
- **Start event:** Customer issue/churn signal
- **Required end state:** Resolved issue or measured retention action
- **Founder boundary:** No spam/consent breach

## Purpose

Resolve customer issues, reduce churn and execute measured retention actions without consent or authority violations.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W18-S01` | Open customer case | intake | `customer_support_specialist` |  |  | `W18-S02` |
| 2 | `W18-S02` | Resolve normal support request | execution | `customer_support_specialist` | communications_manager |  | `W18-S03` |
| 3 | `W18-S03` | Escalate workflow-specific issue | handoff | `customer_support_specialist` | rfq_success_specialist; payments_billing_manager; trust_safety_manager |  | `W18-S04` |
| 4 | `W18-S04` | Diagnose churn or dissatisfaction | analysis | `customer_retention_specialist` | customer_success_director; business_intelligence_analyst |  | `W18-S05` |
| 5 | `W18-S05` | Approve retention intervention | decision | `customer_success_director` | customer_retention_specialist |  | `W18-S06` |
| 6 | `W18-S06` | Execute customer intervention | execution | `customer_retention_specialist` | lifecycle_channel_operations_specialist |  | `W18-S07` |
| 7 | `W18-S07` | Measure and close case | closure | `customer_success_director` | customer_retention_specialist; corporate_performance_director |  | `WORKFLOW_COMPLETE` |

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
