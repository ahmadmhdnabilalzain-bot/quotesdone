# W07 — Document/BOQ/drawing processing

- **Domain:** documents
- **Criticality:** high
- **Profile:** document_cycle
- **Primary object:** `inquiry_document`
- **Accountable role:** `document_intelligence_manager`
- **Start event:** Document uploaded/received
- **Required end state:** Structured evidence and unresolved gaps
- **Founder boundary:** No invented values

## Purpose

Classify, extract and structure uploaded documents, BOQs and drawings while preserving provenance and unresolved gaps.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W07-S01` | Register document and provenance | intake | `document_intelligence_manager` |  |  | `W07-S02` |
| 2 | `W07-S02` | Classify document type and handling path | decision | `document_intelligence_manager` |  |  | `W07-S03` |
| 3 | `W07-S03` | Validate document usability | review | `document_intelligence_manager` | cybersecurity_engineer |  | `W07-S04` |
| 4 | `W07-S04` | Extract BOQ/specification evidence | analysis | `boq_specification_analyst` | relevant_category_overlay |  | `W07-S05` |
| 5 | `W07-S05` | Extract drawing/CAD evidence | analysis | `drawing_cad_analyst` | relevant_category_overlay |  | `W07-S06` |
| 6 | `W07-S06` | Resolve document conflicts | review | `document_intelligence_manager` | rfq_qualification_manager; relevant_category_overlay |  | `W07-S07` |
| 7 | `W07-S07` | Return structured evidence to inquiry | handoff | `document_intelligence_manager` |  |  | `W07-S08` |
| 8 | `W07-S08` | Close document-processing cycle | closure | `document_intelligence_manager` |  |  | `WORKFLOW_COMPLETE` |

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
