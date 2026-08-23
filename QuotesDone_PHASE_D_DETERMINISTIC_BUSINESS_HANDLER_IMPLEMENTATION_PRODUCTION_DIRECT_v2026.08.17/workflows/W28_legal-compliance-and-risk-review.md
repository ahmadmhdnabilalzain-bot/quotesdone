# W28 — Legal, compliance and risk review

- **Domain:** legal
- **Criticality:** critical
- **Profile:** review_cycle
- **Primary object:** `legal_risk_review`
- **Accountable role:** `general_counsel`
- **Start event:** Legal/compliance/risk event
- **Required end state:** Position, verdict, controls and escalation
- **Founder boundary:** Founder for material binding commitment

## Purpose

Create a documented legal, compliance and risk position with controls, escalation and founder gates.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W28-S01` | Open legal/compliance/risk review | intake | `general_counsel` |  |  | `W28-S02` |
| 2 | `W28-S02` | Gather facts and source documents | execution | `contract_manager` | relevant_business_owner |  | `W28-S03` |
| 3 | `W28-S03` | Assess legal position | analysis | `general_counsel` | contract_manager |  | `W28-S04` |
| 4 | `W28-S04` | Assess compliance and privacy | review | `compliance_privacy_officer` |  |  | `W28-S05` |
| 5 | `W28-S05` | Assess risk and control adequacy | review | `risk_governance_manager` |  |  | `W28-S06` |
| 6 | `W28-S06` | Develop contract/control response | execution | `contract_manager` | general_counsel; risk_governance_manager |  | `W28-S07` |
| 7 | `W28-S07` | Issue review decision | decision | `general_counsel` |  | ceo | `W28-S08` |
| 8 | `W28-S08` | Monitor obligations and controls | measurement | `risk_governance_manager` | contract_manager; relevant_business_owner |  | `W28-S09` |
| 9 | `W28-S09` | Close legal-risk case | closure | `general_counsel` |  |  | `WORKFLOW_COMPLETE` |

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
