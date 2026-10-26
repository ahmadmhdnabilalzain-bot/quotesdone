# W17 — Refund, dispute and fraud

- **Domain:** risk
- **Criticality:** critical
- **Profile:** case_workflow
- **Primary object:** `refund_dispute_case`
- **Accountable role:** `trust_safety_manager`
- **Start event:** Refund/dispute/fraud event
- **Required end state:** Evidence-based resolution/escalation
- **Founder boundary:** Money movement and legal commitments gated

## Purpose

Resolve refund, dispute and fraud cases through evidence, authority, execution, reconciliation and appeal paths.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W17-S01` | Open refund/dispute/fraud case | intake | `trust_safety_manager` |  |  | `W17-S02` |
| 2 | `W17-S02` | Triage jurisdiction and authority | analysis | `trust_safety_manager` | general_counsel; payments_billing_manager |  | `W17-S03` |
| 3 | `W17-S03` | Collect transaction and communication evidence | execution | `customer_support_specialist` | billing_reconciliation_specialist; rfq_success_specialist |  | `W17-S04` |
| 4 | `W17-S04` | Conduct fraud review when triggered | review | `fraud_reviewer` | supplier_intelligence_analyst |  | `W17-S05` |
| 5 | `W17-S05` | Conduct legal/compliance review when triggered | review | `general_counsel` | compliance_privacy_officer; contract_manager |  | `W17-S06` |
| 6 | `W17-S06` | Decide case outcome | decision | `trust_safety_manager` | payments_billing_manager; fraud_reviewer; general_counsel | risk_governance_manager | `W17-S07` |
| 7 | `W17-S07` | Execute approved financial action | execution | `payments_billing_manager` |  | billing_reconciliation_specialist | `W17-S08` |
| 8 | `W17-S08` | Apply trust/supplier/customer enforcement | execution | `trust_safety_manager` | supplier_verification_reviewer; customer_success_director |  | `W17-S09` |
| 9 | `W17-S09` | Reconcile and notify | handoff | `billing_reconciliation_specialist` | communications_manager; customer_support_specialist |  | `W17-S10` |
| 10 | `W17-S10` | Handle appeal or escalation | review | `risk_governance_manager` | general_counsel; trust_safety_manager |  | `W17-S11` |
| 11 | `W17-S11` | Close case | closure | `trust_safety_manager` |  |  | `WORKFLOW_COMPLETE` |

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
