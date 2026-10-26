# W19 — Supplier retention

- **Domain:** supplier
- **Criticality:** medium
- **Profile:** retention_cycle
- **Primary object:** `supplier_retention_case`
- **Accountable role:** `supplier_retention_specialist`
- **Start event:** Supplier churn/response decline
- **Required end state:** Measured recovery or exit decision recommendation
- **Founder boundary:** No override of verification/enforcement

## Purpose

Diagnose supplier disengagement and execute measured recovery, restriction or exit recommendations.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W19-S01` | Open supplier retention case | intake | `supplier_retention_specialist` |  |  | `W19-S02` |
| 2 | `W19-S02` | Analyze supplier behavior and context | analysis | `supplier_intelligence_analyst` | supplier_retention_specialist |  | `W19-S03` |
| 3 | `W19-S03` | Diagnose retention cause | analysis | `supplier_retention_specialist` | marketplace_director; communications_manager |  | `W19-S04` |
| 4 | `W19-S04` | Approve supplier intervention | decision | `marketplace_director` | supplier_retention_specialist |  | `W19-S05` |
| 5 | `W19-S05` | Execute and measure intervention | execution | `supplier_retention_specialist` | lifecycle_channel_operations_specialist; supplier_onboarding_specialist |  | `W19-S06` |
| 6 | `W19-S06` | Escalate verification or enforcement issue | handoff | `supplier_verification_reviewer` | trust_safety_manager |  | `W19-S07` |
| 7 | `W19-S07` | Close supplier retention case | closure | `supplier_retention_specialist` |  | marketplace_director | `WORKFLOW_COMPLETE` |

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
