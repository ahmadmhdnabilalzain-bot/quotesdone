# W09 — Supplier onboarding

- **Domain:** supplier
- **Criticality:** high
- **Profile:** onboarding_cycle
- **Primary object:** `supplier_account`
- **Accountable role:** `supplier_onboarding_specialist`
- **Start event:** Supplier invitation/registration
- **Required end state:** Complete verification file
- **Founder boundary:** No self-approval

## Purpose

Collect and validate the supplier profile, capabilities, documents, terms and verification submission.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W09-S01` | Open supplier onboarding case | intake | `supplier_onboarding_specialist` |  |  | `W09-S02` |
| 2 | `W09-S02` | Verify supplier contact channels | review | `supplier_onboarding_specialist` | lifecycle_channel_operations_specialist |  | `W09-S03` |
| 3 | `W09-S03` | Collect company profile | execution | `supplier_onboarding_specialist` |  |  | `W09-S04` |
| 4 | `W09-S04` | Collect supplier documents | execution | `supplier_onboarding_specialist` | document_intelligence_manager |  | `W09-S05` |
| 5 | `W09-S05` | Map categories and capabilities | analysis | `supplier_onboarding_specialist` | taxonomy_governance_manager; category_knowledge_curator |  | `W09-S06` |
| 6 | `W09-S06` | Capture canonical supplier terms acceptance | execution | `supplier_onboarding_specialist` |  | compliance_privacy_officer | `W09-S07` |
| 7 | `W09-S07` | Check onboarding completeness | review | `supplier_onboarding_specialist` |  |  | `W09-S08` |
| 8 | `W09-S08` | Submit independent verification case | handoff | `supplier_onboarding_specialist` |  |  | `W09-S09` |
| 9 | `W09-S09` | Close onboarding | closure | `supplier_onboarding_specialist` |  |  | `WORKFLOW_COMPLETE` |

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
