# W14 — Quotation submission and evaluation

- **Domain:** marketplace
- **Criticality:** critical
- **Profile:** submission_review_cycle
- **Primary object:** `quotation`
- **Accountable role:** `quote_evaluation_specialist`
- **Start event:** Supplier submits/revises quote
- **Required end state:** Validated normalized comparison input
- **Founder boundary:** No alteration of supplier quote

## Purpose

Receive, version, validate and normalize supplier quotations for fair technical and commercial comparison.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W14-S01` | Open supplier quote window | intake | `quote_evaluation_specialist` | rfq_success_specialist |  | `W14-S02` |
| 2 | `W14-S02` | Receive supplier acknowledgement | execution | `rfq_success_specialist` | lifecycle_channel_operations_specialist |  | `W14-S03` |
| 3 | `W14-S03` | Receive quotation revision | execution | `quote_evaluation_specialist` |  |  | `W14-S04` |
| 4 | `W14-S04` | Validate commercial completeness | review | `quote_evaluation_specialist` |  |  | `W14-S05` |
| 5 | `W14-S05` | Validate technical completeness | analysis | `quote_evaluation_specialist` | relevant_category_overlay; relevant_domain_specialist |  | `W14-S06` |
| 6 | `W14-S06` | Request supplier clarification if needed | handoff | `quote_evaluation_specialist` | lifecycle_channel_operations_specialist |  | `W14-S07` |
| 7 | `W14-S07` | Normalize comparable fields | analysis | `quote_evaluation_specialist` |  |  | `W14-S08` |
| 8 | `W14-S08` | Approve or exclude quote from comparison | decision | `quote_evaluation_specialist` |  | rfq_success_specialist | `W14-S09` |
| 9 | `W14-S09` | Close quotation collection | closure | `quote_evaluation_specialist` | marketplace_director |  | `WORKFLOW_COMPLETE` |

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
