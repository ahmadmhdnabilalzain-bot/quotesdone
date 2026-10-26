# W22 — Product discovery to delivery

- **Domain:** product
- **Criticality:** high
- **Profile:** delivery_cycle
- **Primary object:** `product_change`
- **Accountable role:** `product_manager`
- **Start event:** Validated product need
- **Required end state:** Implemented release candidate with acceptance evidence
- **Founder boundary:** No production release without independent gate

## Purpose

Move an approved product need through UX, engineering, verification and independent release approval.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W22-S01` | Define and prioritize the requirement | decision | `product_manager` | chief_product_technology_officer; customer_success_director; marketplace_director |  | `W22-S02` |
| 2 | `W22-S02` | Own experience design and UX acceptance criteria | execution | `product_ux_designer` | product_manager; frontend_engineer |  | `W22-S03` |
| 3 | `W22-S03` | Own implementation delivery | execution | `engineering_manager` | solution_architect; product_manager |  | `W22-S04` |
| 4 | `W22-S04` | Implement backend | execution | `backend_engineer` | solution_architect; engineering_manager |  | `W22-S05` |
| 5 | `W22-S05` | Implement frontend | execution | `frontend_engineer` | product_ux_designer; engineering_manager |  | `W22-S06` |
| 6 | `W22-S06` | Verify behavior against acceptance criteria | review | `test_automation_engineer` | product_manager; product_ux_designer |  | `W22-S07` |
| 7 | `W22-S07` | Release go/no-go | decision | `qa_release_management_director` | cybersecurity_engineer; it_operations_site_reliability_engineer |  | `WORKFLOW_COMPLETE` |

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
