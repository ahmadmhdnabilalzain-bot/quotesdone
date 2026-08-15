# W24 — Release and production approval

## Purpose

Produce an independent go/no-go decision, deploy safely, verify, monitor and roll back when required.

## Ownership

- **Accountable workflow owner:** `qa_release_management_director`
- **Contributors:** test_automation_engineer; cybersecurity_engineer; ai_quality_assurance_reviewer; it_operations_site_reliability_engineer
- **Independent reviewer/challenge role:** `risk_governance_manager`
- **Criticality:** `critical`
- **Primary business object:** `release_candidate`
- **State profile:** `release_cycle`

## Start and end

- **Start event:** Release candidate
- **Required end state:** Go/no-go and rollback readiness
- **Founder boundary:** Founder approval where deployment policy requires

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W24-S01 | Register release candidate | intake | qa_release_management_director |  | Open release record. | Commit, migrations, artifacts and environment are immutable and identified. |
| 2 | W24-S02 | Verify build and deterministic tests | review | test_automation_engineer |  | Test evidence. | All mandatory checks are measured; errored checks are not counted as passes. |
| 3 | W24-S03 | Verify security and privacy | review | cybersecurity_engineer |  | Security/privacy verdict. | Critical vulnerabilities or privacy violations block release. |
| 4 | W24-S04 | Verify AI behavior when applicable | review | ai_quality_assurance_reviewer |  | AI behavior verdict. | Unsafe or unmeasured consequential AI behavior blocks release. |
| 5 | W24-S05 | Verify rollback and operational readiness | review | it_operations_site_reliability_engineer |  | Operational readiness verdict. | Rollback is executable and monitoring covers the changed behavior. |
| 6 | W24-S06 | Issue release go/no-go | decision | qa_release_management_director | risk_governance_manager | Release verdict. | No failed mandatory gate is overridden by the delivery team. |
| 7 | W24-S07 | Execute approved deployment | execution | it_operations_site_reliability_engineer |  | Deployment result and environment version. | Deployed fingerprint matches the approved candidate. |
| 8 | W24-S08 | Run post-deployment verification | review | test_automation_engineer |  | Post-deployment verification result. | All critical checks pass and no unexpected state change occurs. |
| 9 | W24-S09 | Rollback when required | execution | it_operations_site_reliability_engineer | qa_release_management_director | Rollback result. | Prior state is restored and the incident/change remains open for diagnosis. |
| 10 | W24-S10 | Close release | closure | qa_release_management_director |  | Closed release record. | Final version, verdict, monitoring and residual issues are recorded. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W24-01-02 | W24-S01 | W24-S02 | qa_release_management_director | test_automation_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-02-03 | W24-S02 | W24-S03 | test_automation_engineer | cybersecurity_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-03-04 | W24-S03 | W24-S04 | cybersecurity_engineer | ai_quality_assurance_reviewer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-04-05 | W24-S04 | W24-S05 | ai_quality_assurance_reviewer | it_operations_site_reliability_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-05-06 | W24-S05 | W24-S06 | it_operations_site_reliability_engineer | qa_release_management_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-06-07 | W24-S06 | W24-S07 | qa_release_management_director | it_operations_site_reliability_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-07-08 | W24-S07 | W24-S08 | it_operations_site_reliability_engineer | test_automation_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-08-09 | W24-S08 | W24-S09 | test_automation_engineer | it_operations_site_reliability_engineer | within_department | Deployment or post-deployment mandatory gate fails. Workflow record; prior accepted outputs; applicable policy. |
| H-W24-09-10 | W24-S09 | W24-S10 | it_operations_site_reliability_engineer | qa_release_management_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

## Applicable hard gates

| gate_id | gate_name | required_evidence | fail_result |
| --- | --- | --- | --- |
| GATE-001 | Phase A baseline frozen | Phase A founder-approved tag, fingerprints and registries exist. | Stop and create formal Phase A change request. |
| GATE-002 | Canonical active owner | Step owner resolves to one active canonical role or permitted overlay. | Block assignment. |
| GATE-003 | One accountable owner | Exactly one accountable owner for workflow and step. | Reject multiply owned/unowned step. |
| GATE-004 | Creator-reviewer separation | Creator and final independent reviewer resolve to different effective identities. | Reject review and reassign reviewer. |
| GATE-005 | Founder boundary | Decision is within delegated authority or founder approval exists. | Block and escalate to founder. |
| GATE-006 | Valid workflow transition | Requested transition is declared and prerequisites are satisfied. | Reject transition. |
| GATE-007 | Complete handoff | Required packet, source version, blockers and requested action are present. | Reject back to sender with reason. |
| GATE-008 | Closure completeness | All mandatory steps, obligations and blockers are closed/handed off. | Block closure. |
| GATE-024 | Release readiness | Tests, security, AI (if relevant), rollback and operations pass. | No-go/rollback. |
| GATE-031 | Zero paid inference | OpenRouter and paid provider call counts are zero during Phase B. | Stop phase and report breach. |
| GATE-032 | No workflow activation | No new cron, autonomous executor, provider route or live workflow is activated by Phase B. | Rollback activation change. |

## Applicable business rules

| rule_id | rule_name | rule_text |
| --- | --- | --- |
| BR-001 | One accountable owner | Every workflow and required workflow step has exactly one accountable owner. |
| BR-002 | Creator/reviewer separation | A creator cannot be the sole final independent reviewer of the same consequential output. |
| BR-004 | Canonical identity only for new work | All new workflow ownership and state writes use canonical active identities; aliases are input/history compatibility only. |
| BR-005 | Inactive identity cannot act | Inactive, merged-away or unknown identities cannot own or execute current work. |
| BR-006 | Valid transition only | Business objects and workflow runs may move only through declared state transitions. |
| BR-007 | Prerequisite enforcement | A step cannot start or complete before all required predecessor outputs and gates pass. |
| BR-008 | Complete handoff packet | A receiving owner may reject an incomplete handoff; incomplete handoffs cannot be treated as accepted. |
| BR-009 | Closure criteria required | No workflow may close while a mandatory step, blocker, obligation or handoff remains unresolved. |
| BR-010 | History preservation | Completed decisions, reviews, acceptances, revisions and attempts are never overwritten; changes create new versions/records. |
| BR-036 | Actual artifact review | Visual/video/file review must inspect the actual final artifact, not only the prompt or brief. |
| BR-037 | No self-certification | An agent, department or builder cannot independently certify its own consequential behavior or change. |
| BR-038 | Release independence | Product/engineering/AI implementers cannot issue the final release go/no-go. |
| BR-039 | Rollback readiness | No consequential production release is approved without a defined and executable rollback/recovery path. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-045 | Retry is a new attempt | Retries preserve the failed first attempt and use a new attempt record linked to the original. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-039 | Release check errors/429 | qa_release_management_director | it_operations_site_reliability_engineer | Mark unmeasured, not passed; rerun after infrastructure recovery. |
| EX-040 | Production verification fails | qa_release_management_director | it_operations_site_reliability_engineer | Trigger approved rollback and incident/change investigation. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
