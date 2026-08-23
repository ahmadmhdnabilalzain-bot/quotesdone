# W11 — Supplier coverage and acquisition gaps

- **Domain:** supplier
- **Criticality:** medium
- **Profile:** improvement_cycle
- **Primary object:** `supplier_coverage_case`
- **Accountable role:** `supplier_coverage_liquidity_specialist`
- **Start event:** Coverage/liquidity KPI miss
- **Required end state:** Prioritized supplier acquisition target
- **Founder boundary:** No unapproved outreach/spend

## Purpose

Measure supplier liquidity gaps and create prioritized acquisition targets tied to inquiry demand and revenue.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W11-S01` | Measure inquiry demand | measurement | `supplier_coverage_liquidity_specialist` | business_intelligence_analyst |  | `W11-S02` |
| 2 | `W11-S02` | Measure usable supplier supply | measurement | `supplier_intelligence_analyst` | supplier_coverage_liquidity_specialist |  | `W11-S03` |
| 3 | `W11-S03` | Calculate coverage and liquidity gap | analysis | `supplier_coverage_liquidity_specialist` |  |  | `W11-S04` |
| 4 | `W11-S04` | Prioritize acquisition targets | decision | `marketplace_director` | supplier_coverage_liquidity_specialist; chief_revenue_officer |  | `W11-S05` |
| 5 | `W11-S05` | Handoff acquisition target | handoff | `business_development_manager` | strategic_partnerships_government_relations_manager; supplier_onboarding_specialist |  | `W11-S06` |
| 6 | `W11-S06` | Measure supplier acquisition outcome | measurement | `supplier_coverage_liquidity_specialist` | crm_revenue_operations_manager; supplier_intelligence_analyst |  | `W11-S07` |
| 7 | `W11-S07` | Close or revise coverage case | closure | `marketplace_director` |  |  | `WORKFLOW_COMPLETE` |

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
