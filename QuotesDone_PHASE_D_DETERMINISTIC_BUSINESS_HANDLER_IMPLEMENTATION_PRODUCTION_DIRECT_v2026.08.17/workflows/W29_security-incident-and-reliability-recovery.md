# W29 — Security incident and reliability recovery

- **Domain:** assurance
- **Criticality:** critical
- **Profile:** incident_cycle
- **Primary object:** `incident`
- **Accountable role:** `it_operations_site_reliability_engineer`
- **Start event:** Incident/security signal
- **Required end state:** Contained incident, restored service and evidence
- **Founder boundary:** No hidden destructive action

## Purpose

Detect, contain, investigate, recover and learn from security and reliability incidents.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W29-S01` | Open incident | intake | `it_operations_site_reliability_engineer` | cybersecurity_engineer |  | `W29-S02` |
| 2 | `W29-S02` | Classify severity and command | decision | `it_operations_site_reliability_engineer` | cybersecurity_engineer; qa_release_management_director |  | `W29-S03` |
| 3 | `W29-S03` | Contain immediate impact | execution | `it_operations_site_reliability_engineer` | backend_engineer; frontend_engineer |  | `W29-S04` |
| 4 | `W29-S04` | Conduct security investigation | review | `cybersecurity_engineer` | data_engineer; backend_engineer |  | `W29-S05` |
| 5 | `W29-S05` | Restore service safely | execution | `it_operations_site_reliability_engineer` | engineering_manager |  | `W29-S06` |
| 6 | `W29-S06` | Verify recovery and release safety | review | `qa_release_management_director` | test_automation_engineer; cybersecurity_engineer |  | `W29-S07` |
| 7 | `W29-S07` | Communicate incident status | handoff | `communications_manager` | customer_success_director; general_counsel |  | `W29-S08` |
| 8 | `W29-S08` | Conduct root-cause analysis | analysis | `engineering_manager` | it_operations_site_reliability_engineer; cybersecurity_engineer; process_improvement_manager |  | `W29-S09` |
| 9 | `W29-S09` | Assign corrective actions | handoff | `project_coordinator_pmo` | engineering_manager; process_improvement_manager |  | `W29-S10` |
| 10 | `W29-S10` | Close incident | closure | `it_operations_site_reliability_engineer` |  | risk_governance_manager | `WORKFLOW_COMPLETE` |

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
