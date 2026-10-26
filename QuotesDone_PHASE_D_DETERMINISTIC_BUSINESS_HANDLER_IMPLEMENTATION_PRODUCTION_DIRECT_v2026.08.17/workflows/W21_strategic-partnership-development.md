# W21 — Strategic partnership development

- **Domain:** growth
- **Criticality:** high
- **Profile:** opportunity_cycle
- **Primary object:** `partnership_opportunity`
- **Accountable role:** `strategic_partnerships_government_relations_manager`
- **Start event:** Qualified partnership opportunity
- **Required end state:** Approved partnership proposal/engagement plan
- **Founder boundary:** Founder for equity/country/material commitments

## Purpose

Qualify, structure, review and execute strategic partnership or government engagement opportunities.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W21-S01` | Open partnership opportunity | intake | `strategic_partnerships_government_relations_manager` |  |  | `W21-S02` |
| 2 | `W21-S02` | Qualify strategic fit | analysis | `business_development_manager` | account_manager; market_intelligence_analyst |  | `W21-S03` |
| 3 | `W21-S03` | Develop partnership structure | analysis | `strategic_partnerships_government_relations_manager` | chief_revenue_officer; account_manager |  | `W21-S04` |
| 4 | `W21-S04` | Conduct due diligence and legal review | review | `general_counsel` | risk_governance_manager; contract_manager; compliance_privacy_officer |  | `W21-S05` |
| 5 | `W21-S05` | Approve engagement path | decision | `chief_revenue_officer` | general_counsel; cfo | ceo | `W21-S06` |
| 6 | `W21-S06` | Negotiate and execute approved engagement | execution | `strategic_partnerships_government_relations_manager` | contract_manager; account_manager |  | `W21-S07` |
| 7 | `W21-S07` | Measure partnership outcome | measurement | `account_manager` | crm_revenue_operations_manager; business_intelligence_analyst |  | `W21-S08` |
| 8 | `W21-S08` | Close, renew or exit partnership | closure | `chief_revenue_officer` | strategic_partnerships_government_relations_manager |  | `WORKFLOW_COMPLETE` |

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
