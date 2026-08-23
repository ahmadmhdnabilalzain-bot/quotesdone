# W24 — Release and production approval

- **Domain:** assurance
- **Criticality:** critical
- **Profile:** release_cycle
- **Primary object:** `release_candidate`
- **Accountable role:** `qa_release_management_director`
- **Start event:** Release candidate
- **Required end state:** Go/no-go and rollback readiness
- **Founder boundary:** Founder approval where deployment policy requires

## Purpose

Produce an independent go/no-go decision, deploy safely, verify, monitor and roll back when required.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W24-S01` | Register release candidate | intake | `qa_release_management_director` |  |  | `W24-S02` |
| 2 | `W24-S02` | Verify build and deterministic tests | review | `test_automation_engineer` | engineering_manager |  | `W24-S03` |
| 3 | `W24-S03` | Verify security and privacy | review | `cybersecurity_engineer` | compliance_privacy_officer |  | `W24-S04` |
| 4 | `W24-S04` | Verify AI behavior when applicable | review | `ai_quality_assurance_reviewer` | model_evaluation_reviewer |  | `W24-S05` |
| 5 | `W24-S05` | Verify rollback and operational readiness | review | `it_operations_site_reliability_engineer` | engineering_manager |  | `W24-S06` |
| 6 | `W24-S06` | Issue release go/no-go | decision | `qa_release_management_director` |  | risk_governance_manager | `W24-S07` |
| 7 | `W24-S07` | Execute approved deployment | execution | `it_operations_site_reliability_engineer` | engineering_manager |  | `W24-S08` |
| 8 | `W24-S08` | Run post-deployment verification | review | `test_automation_engineer` | it_operations_site_reliability_engineer; business_owner |  | `W24-S09` |
| 9 | `W24-S09` | Rollback when required | execution | `it_operations_site_reliability_engineer` |  | qa_release_management_director | `W24-S10` |
| 10 | `W24-S10` | Close release | closure | `qa_release_management_director` |  |  | `WORKFLOW_COMPLETE` |

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
