# W10 — Supplier verification

- **Domain:** supplier
- **Criticality:** critical
- **Profile:** independent_review_cycle
- **Primary object:** `supplier_verification_case`
- **Accountable role:** `supplier_verification_reviewer`
- **Start event:** Complete/reviewable supplier file
- **Required end state:** Independent approve/refuse/correct decision
- **Founder boundary:** No approval without evidence

## Purpose

Issue an independent, evidence-based supplier approval, correction, refusal or suspension decision.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W10-S01` | Accept verification case | intake | `supplier_verification_reviewer` |  |  | `W10-S02` |
| 2 | `W10-S02` | Verify legal identity and licence | review | `supplier_verification_reviewer` | document_intelligence_manager |  | `W10-S03` |
| 3 | `W10-S03` | Verify capability claims | review | `supplier_verification_reviewer` | supplier_intelligence_analyst; relevant_category_overlay |  | `W10-S04` |
| 4 | `W10-S04` | Perform fraud/risk challenge where triggered | handoff | `fraud_reviewer` | risk_governance_manager |  | `W10-S05` |
| 5 | `W10-S05` | Issue verification decision | decision | `supplier_verification_reviewer` |  | risk_governance_manager | `W10-S06` |
| 6 | `W10-S06` | Open correction window if applicable | execution | `supplier_verification_reviewer` | supplier_onboarding_specialist; communications_manager |  | `W10-S07` |
| 7 | `W10-S07` | Notify supplier and internal owners | handoff | `supplier_onboarding_specialist` | lifecycle_channel_operations_specialist |  | `W10-S08` |
| 8 | `W10-S08` | Close verification case | closure | `supplier_verification_reviewer` |  |  | `WORKFLOW_COMPLETE` |

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
