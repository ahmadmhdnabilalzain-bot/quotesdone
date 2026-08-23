# W12 — Supplier matching and dispatch

- **Domain:** marketplace
- **Criticality:** critical
- **Profile:** transaction_cycle
- **Primary object:** `dispatch_batch`
- **Accountable role:** `supplier_matching_dispatch_operator`
- **Start event:** Approved supplier-safe quote-ready inquiry
- **Required end state:** Idempotent selected assignments and notification records
- **Founder boundary:** No gate bypass or unapproved supplier

## Purpose

Select eligible suppliers and create idempotent assignments and exactly one notification record per selected supplier.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W12-S01` | Accept dispatch-ready package | intake | `supplier_matching_dispatch_operator` |  |  | `W12-S02` |
| 2 | `W12-S02` | Build eligible supplier pool | analysis | `supplier_matching_dispatch_operator` | supplier_intelligence_analyst |  | `W12-S03` |
| 3 | `W12-S03` | Apply fairness and capacity policy | analysis | `supplier_matching_dispatch_operator` | marketplace_director; supplier_coverage_liquidity_specialist |  | `W12-S04` |
| 4 | `W12-S04` | Review policy exception if needed | review | `marketplace_director` |  |  | `W12-S05` |
| 5 | `W12-S05` | Revalidate immediately before assignment | review | `supplier_matching_dispatch_operator` |  |  | `W12-S06` |
| 6 | `W12-S06` | Create idempotent supplier assignments | execution | `supplier_matching_dispatch_operator` |  |  | `W12-S07` |
| 7 | `W12-S07` | Create exactly one notification per assignment | handoff | `supplier_matching_dispatch_operator` | lifecycle_channel_operations_specialist |  | `W12-S08` |
| 8 | `W12-S08` | Record selection and exclusion evidence | execution | `supplier_matching_dispatch_operator` |  |  | `W12-S09` |
| 9 | `W12-S09` | Close dispatch batch | closure | `supplier_matching_dispatch_operator` |  | marketplace_content_privacy_reviewer | `WORKFLOW_COMPLETE` |

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
