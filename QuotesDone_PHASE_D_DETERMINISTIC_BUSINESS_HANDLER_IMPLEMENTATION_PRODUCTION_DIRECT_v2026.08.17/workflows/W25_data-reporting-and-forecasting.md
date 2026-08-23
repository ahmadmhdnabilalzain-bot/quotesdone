# W25 — Data reporting and forecasting

- **Domain:** data
- **Criticality:** high
- **Profile:** reporting_cycle
- **Primary object:** `intelligence_product`
- **Accountable role:** `data_intelligence_director`
- **Start event:** Reporting/forecast requirement
- **Required end state:** Decision-grade report/forecast
- **Founder boundary:** No unsupported causal claim

## Purpose

Create reliable metrics, reports and forecasts with provenance, uncertainty and decision relevance.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W25-S01` | Open intelligence request or cadence | intake | `data_intelligence_director` |  |  | `W25-S02` |
| 2 | `W25-S02` | Define metrics and source contract | decision | `data_intelligence_director` | business_intelligence_analyst; data_engineer |  | `W25-S03` |
| 3 | `W25-S03` | Validate and prepare data | execution | `data_engineer` |  |  | `W25-S04` |
| 4 | `W25-S04` | Construct analysis and report | analysis | `business_intelligence_analyst` | market_intelligence_analyst; supplier_intelligence_analyst |  | `W25-S05` |
| 5 | `W25-S05` | Construct forecast and uncertainty | analysis | `forecasting_analyst` |  |  | `W25-S06` |
| 6 | `W25-S06` | Review decision relevance and integrity | review | `data_intelligence_director` |  | corporate_performance_director | `W25-S07` |
| 7 | `W25-S07` | Publish and capture decision usage | handoff | `data_intelligence_director` | chief_of_staff; relevant_department_head |  | `W25-S08` |
| 8 | `W25-S08` | Close or schedule refresh | closure | `data_intelligence_director` |  |  | `WORKFLOW_COMPLETE` |

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
