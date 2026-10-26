# W16 — Payment, billing and reconciliation

- **Domain:** finance
- **Criticality:** critical
- **Profile:** financial_transaction_cycle
- **Primary object:** `payment_transaction`
- **Accountable role:** `payments_billing_manager`
- **Start event:** Reveal/payment event
- **Required end state:** Correct payment, invoice and reconciliation state
- **Founder boundary:** No self-reconciliation of own monetary action

## Purpose

Process payment, billing, invoicing and independent reconciliation with idempotent provider-event handling.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W16-S01` | Create payment request | intake | `payments_billing_manager` |  |  | `W16-S02` |
| 2 | `W16-S02` | Present payment to customer | execution | `payments_billing_manager` |  |  | `W16-S03` |
| 3 | `W16-S03` | Receive provider event | execution | `payments_billing_manager` |  |  | `W16-S04` |
| 4 | `W16-S04` | Apply payment state transition | decision | `payments_billing_manager` |  |  | `W16-S05` |
| 5 | `W16-S05` | Create invoice or receipt evidence | execution | `billing_reconciliation_specialist` | financial_controller |  | `W16-S06` |
| 6 | `W16-S06` | Independently reconcile payment | review | `billing_reconciliation_specialist` |  | financial_controller | `W16-S07` |
| 7 | `W16-S07` | Quarantine discrepancy | handoff | `financial_controller` | risk_governance_manager |  | `W16-S08` |
| 8 | `W16-S08` | Confirm payment result to reveal workflow | handoff | `billing_reconciliation_specialist` |  |  | `W16-S09` |
| 9 | `W16-S09` | Close payment cycle | closure | `payments_billing_manager` |  | risk_governance_manager | `WORKFLOW_COMPLETE` |

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
