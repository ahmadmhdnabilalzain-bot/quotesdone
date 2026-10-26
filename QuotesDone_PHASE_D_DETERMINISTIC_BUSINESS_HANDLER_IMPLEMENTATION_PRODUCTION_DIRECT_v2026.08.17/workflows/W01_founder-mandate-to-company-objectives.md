# W01 — Founder mandate to company objectives

- **Domain:** executive
- **Criticality:** high
- **Profile:** governance_cycle
- **Primary object:** `company_objective`
- **Accountable role:** `ceo`
- **Start event:** Founder mandate
- **Required end state:** Approved company objectives and department mandates
- **Founder boundary:** Founder approves reserved decisions

## Purpose

Convert the founder mandate into approved company objectives, department mandates and accountable execution boundaries.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W01-S01` | Capture founder mandate | intake | `chief_of_staff` |  |  | `W01-S02` |
| 2 | `W01-S02` | Develop strategic options | analysis | `strategy_director` | ceo; market_intelligence_analyst; forecasting_analyst |  | `W01-S03` |
| 3 | `W01-S03` | Translate target into KPI tree | analysis | `corporate_performance_director` | data_intelligence_director; cfo |  | `W01-S04` |
| 4 | `W01-S04` | Set financial resource envelope | decision | `cfo` | fp_a_analyst |  | `W01-S05` |
| 5 | `W01-S05` | Define department mandates | handoff | `chief_of_staff` | ceo; corporate_performance_director; department_heads |  | `W01-S06` |
| 6 | `W01-S06` | Approve operating objective set | decision | `ceo` | chief_of_staff; corporate_performance_director; cfo | founder | `W01-S07` |
| 7 | `W01-S07` | Issue accountable work | execution | `chief_of_staff` | department_heads; project_coordinator_pmo |  | `W01-S08` |
| 8 | `W01-S08` | Confirm objective cycle closure | closure | `corporate_performance_director` | chief_of_staff; ceo |  | `WORKFLOW_COMPLETE` |

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
