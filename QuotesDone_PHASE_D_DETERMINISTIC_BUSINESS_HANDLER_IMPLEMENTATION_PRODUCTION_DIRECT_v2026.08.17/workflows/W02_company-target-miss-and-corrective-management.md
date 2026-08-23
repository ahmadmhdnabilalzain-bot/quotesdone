# W02 — Company target miss and corrective management

- **Domain:** executive
- **Criticality:** high
- **Profile:** improvement_cycle
- **Primary object:** `performance_recovery_case`
- **Accountable role:** `corporate_performance_director`
- **Start event:** Material KPI/trajectory miss
- **Required end state:** Binding-constraint diagnosis and corrective initiative
- **Founder boundary:** Founder only for reserved policy/budget changes

## Purpose

Diagnose material trajectory or KPI misses and create, assign, monitor and close corrective action.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W02-S01` | Detect material trajectory miss | intake | `corporate_performance_director` | business_intelligence_analyst; forecasting_analyst |  | `W02-S02` |
| 2 | `W02-S02` | Validate the measurement | review | `data_intelligence_director` | data_engineer; business_intelligence_analyst |  | `W02-S03` |
| 3 | `W02-S03` | Identify the binding constraint | analysis | `corporate_performance_director` | department_heads; chief_of_staff |  | `W02-S04` |
| 4 | `W02-S04` | Develop recovery scenarios | analysis | `strategy_director` | forecasting_analyst; fp_a_analyst |  | `W02-S05` |
| 5 | `W02-S05` | Assess affordability and resource trade-offs | analysis | `cfo` | fp_a_analyst |  | `W02-S06` |
| 6 | `W02-S06` | Approve corrective initiative | decision | `ceo` | corporate_performance_director; cfo; affected_department_head | strategy_director | `W02-S07` |
| 7 | `W02-S07` | Assign corrective work | handoff | `chief_of_staff` | project_coordinator_pmo; affected_department_head |  | `W02-S08` |
| 8 | `W02-S08` | Measure intervention outcome | measurement | `corporate_performance_director` | data_intelligence_director; affected_department_head |  | `W02-S09` |
| 9 | `W02-S09` | Close, continue or revise recovery | closure | `ceo` | corporate_performance_director; chief_of_staff |  | `WORKFLOW_COMPLETE` |

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
