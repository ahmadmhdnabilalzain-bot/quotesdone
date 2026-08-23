# W15 — Customer comparison and reveal

- **Domain:** customer
- **Criticality:** critical
- **Profile:** customer_decision_cycle
- **Primary object:** `quotation_comparison`
- **Accountable role:** `rfq_success_specialist`
- **Start event:** Sufficient approved quotations
- **Required end state:** Customer comparison and approved reveal path
- **Founder boundary:** Pricing/reveal policy founder-reserved

## Purpose

Publish approved comparable quotations, capture customer selection and open the founder-approved reveal path.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W15-S01` | Check comparison readiness | review | `rfq_success_specialist` | quote_evaluation_specialist |  | `W15-S02` |
| 2 | `W15-S02` | Construct customer comparison | execution | `quote_evaluation_specialist` | relevant_category_overlay |  | `W15-S03` |
| 3 | `W15-S03` | Review customer visibility and privacy | review | `compliance_privacy_officer` | rfq_success_specialist |  | `W15-S04` |
| 4 | `W15-S04` | Publish comparison to customer | execution | `rfq_success_specialist` | lifecycle_channel_operations_specialist |  | `W15-S05` |
| 5 | `W15-S05` | Capture customer selection | decision | `rfq_success_specialist` | customer_success_director |  | `W15-S06` |
| 6 | `W15-S06` | Calculate founder-approved reveal charge | execution | `payments_billing_manager` | billing_reconciliation_specialist |  | `W15-S07` |
| 7 | `W15-S07` | Complete reveal payment handoff | handoff | `payments_billing_manager` |  |  | `W15-S08` |
| 8 | `W15-S08` | Reveal permitted contact relationship | execution | `rfq_success_specialist` | customer_success_director; communications_manager |  | `W15-S09` |
| 9 | `W15-S09` | Close comparison and reveal cycle | closure | `rfq_success_specialist` |  |  | `WORKFLOW_COMPLETE` |

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
