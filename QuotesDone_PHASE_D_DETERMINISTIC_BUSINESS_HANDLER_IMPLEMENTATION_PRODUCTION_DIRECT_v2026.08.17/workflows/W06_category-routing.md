# W06 — Category routing

- **Domain:** marketplace
- **Criticality:** critical
- **Profile:** classification_cycle
- **Primary object:** `inquiry_route_set`
- **Accountable role:** `inquiry_router`
- **Start event:** New or changed inquiry evidence
- **Required end state:** Confirmed route set or clarification request
- **Founder boundary:** No silent uncertain activation

## Purpose

Determine and confirm the correct category/route set without silently activating uncertain scope.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W06-S01` | Normalize routing evidence | intake | `inquiry_router` | rfq_qualification_manager |  | `W06-S02` |
| 2 | `W06-S02` | Generate route candidates | analysis | `inquiry_router` | relevant_category_overlay |  | `W06-S03` |
| 3 | `W06-S03` | Evaluate ambiguity and exclusions | analysis | `inquiry_router` | rfq_qualification_manager; relevant_domain_specialist |  | `W06-S04` |
| 4 | `W06-S04` | Request customer clarification | execution | `rfq_qualification_manager` | inquiry_router |  | `W06-S05` |
| 5 | `W06-S05` | Confirm route set | decision | `inquiry_router` |  | inquiry_quality_scoring_analyst | `W06-S06` |
| 6 | `W06-S06` | Resolve multi-category coordination | handoff | `rfq_qualification_manager` | mep_domain_specialist; construction_civil_domain_specialist; interior_fitout_domain_specialist; industrial_energy_domain_specialist |  | `W06-S07` |
| 7 | `W06-S07` | Publish routing result to inquiry | closure | `inquiry_router` |  |  | `WORKFLOW_COMPLETE` |

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
