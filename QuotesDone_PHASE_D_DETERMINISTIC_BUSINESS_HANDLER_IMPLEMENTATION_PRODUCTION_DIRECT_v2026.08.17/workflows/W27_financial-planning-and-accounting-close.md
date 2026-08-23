# W27 — Financial planning and accounting close

- **Domain:** finance
- **Criticality:** critical
- **Profile:** close_cycle
- **Primary object:** `financial_close`
- **Accountable role:** `cfo`
- **Start event:** Planning/close cycle
- **Required end state:** Budget/forecast/close with controls and exceptions
- **Founder boundary:** Founder approves above limits/equity/funding

## Purpose

Complete planning, accounting close, reconciliation, tax coordination, variance analysis and controlled reporting.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W27-S01` | Open planning/close cycle | intake | `cfo` | financial_controller |  | `W27-S02` |
| 2 | `W27-S02` | Collect and classify financial evidence | execution | `financial_controller` | accounts_payable_specialist; payments_billing_manager; collections_revenue_assurance_specialist |  | `W27-S03` |
| 3 | `W27-S03` | Reconcile cash, payments and billing | review | `billing_reconciliation_specialist` | financial_controller |  | `W27-S04` |
| 4 | `W27-S04` | Validate payables and accruals | review | `accounts_payable_specialist` | financial_controller |  | `W27-S05` |
| 5 | `W27-S05` | Validate revenue and collections | review | `collections_revenue_assurance_specialist` | financial_controller |  | `W27-S06` |
| 6 | `W27-S06` | Apply accounting close and controls | decision | `financial_controller` |  |  | `W27-S07` |
| 7 | `W27-S07` | Coordinate UAE tax compliance | review | `financial_controller` | general_counsel; compliance_privacy_officer |  | `W27-S08` |
| 8 | `W27-S08` | Prepare forecast and variance | analysis | `fp_a_analyst` | forecasting_analyst |  | `W27-S09` |
| 9 | `W27-S09` | Review and approve financial report | decision | `cfo` |  | risk_governance_manager | `W27-S10` |
| 10 | `W27-S10` | Close financial cycle | closure | `cfo` |  |  | `WORKFLOW_COMPLETE` |

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
