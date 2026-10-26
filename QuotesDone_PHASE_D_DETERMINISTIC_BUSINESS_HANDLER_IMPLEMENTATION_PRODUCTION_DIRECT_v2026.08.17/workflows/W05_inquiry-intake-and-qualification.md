# W05 — Inquiry intake and qualification

- **Domain:** marketplace
- **Criticality:** critical
- **Profile:** qualification_cycle
- **Primary object:** `inquiry`
- **Accountable role:** `rfq_qualification_manager`
- **Start event:** Customer starts inquiry
- **Required end state:** Structured quote-ready or explicitly blocked inquiry
- **Founder boundary:** No dispatch before readiness/privacy gates

## Purpose

Convert a customer request into a structured, legitimate and quote-ready inquiry or an explicit blocked/clarification state.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W05-S01` | Open inquiry case | intake | `rfq_qualification_manager` |  |  | `W05-S02` |
| 2 | `W05-S02` | Obtain route candidates | handoff | `inquiry_router` | rfq_qualification_manager |  | `W05-S03` |
| 3 | `W05-S03` | Load minimum qualification requirements | analysis | `rfq_qualification_manager` | relevant_category_overlay |  | `W05-S04` |
| 4 | `W05-S04` | Process provided documents | handoff | `document_intelligence_manager` | boq_specification_analyst; drawing_cad_analyst; relevant_category_overlay |  | `W05-S05` |
| 5 | `W05-S05` | Ask minimum sufficient questions | execution | `rfq_qualification_manager` | relevant_category_overlay |  | `W05-S06` |
| 6 | `W05-S06` | Validate consistency and legitimacy | review | `inquiry_quality_scoring_analyst` | rfq_qualification_manager; fraud_reviewer |  | `W05-S07` |
| 7 | `W05-S07` | Decide qualification status | decision | `rfq_qualification_manager` |  | inquiry_quality_scoring_analyst | `W05-S08` |
| 8 | `W05-S08` | Freeze qualification version | execution | `rfq_qualification_manager` |  |  | `W05-S09` |
| 9 | `W05-S09` | Close or hand off inquiry qualification | closure | `rfq_qualification_manager` |  |  | `WORKFLOW_COMPLETE` |

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
