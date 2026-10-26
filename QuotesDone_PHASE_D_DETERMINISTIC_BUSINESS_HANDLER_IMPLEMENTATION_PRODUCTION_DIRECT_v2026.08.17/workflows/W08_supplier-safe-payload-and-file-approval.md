# W08 — Supplier-safe payload and file approval

- **Domain:** privacy
- **Criticality:** critical
- **Profile:** independent_review_cycle
- **Primary object:** `supplier_safe_package`
- **Accountable role:** `marketplace_content_privacy_reviewer`
- **Start event:** Quote-ready inquiry proposed for suppliers
- **Required end state:** Approved immutable supplier-safe package or rejection
- **Founder boundary:** No customer identity leakage

## Purpose

Create and independently approve the immutable supplier-facing brief and file set with no customer identity leakage.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W08-S01` | Create supplier-safe brief candidate | execution | `rfq_qualification_manager` | document_intelligence_manager |  | `W08-S02` |
| 2 | `W08-S02` | Prepare supplier-facing files | execution | `document_intelligence_manager` | drawing_cad_analyst |  | `W08-S03` |
| 3 | `W08-S03` | Run privacy and identity review | review | `marketplace_content_privacy_reviewer` | compliance_privacy_officer |  | `W08-S04` |
| 4 | `W08-S04` | Run content fidelity review | review | `marketplace_content_privacy_reviewer` | rfq_qualification_manager; relevant_category_overlay |  | `W08-S05` |
| 5 | `W08-S05` | Return corrections when required | handoff | `marketplace_content_privacy_reviewer` | rfq_qualification_manager; document_intelligence_manager |  | `W08-S06` |
| 6 | `W08-S06` | Approve immutable supplier-safe package | decision | `marketplace_content_privacy_reviewer` |  | compliance_privacy_officer | `W08-S07` |
| 7 | `W08-S07` | Publish safe-package eligibility | handoff | `marketplace_content_privacy_reviewer` |  |  | `W08-S08` |
| 8 | `W08-S08` | Close supplier-safe review | closure | `marketplace_content_privacy_reviewer` |  |  | `WORKFLOW_COMPLETE` |

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
