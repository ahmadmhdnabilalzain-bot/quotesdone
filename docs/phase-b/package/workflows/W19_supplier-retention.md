# W19 — Supplier retention

## Purpose

Diagnose supplier disengagement and execute measured recovery, restriction or exit recommendations.

## Ownership

- **Accountable workflow owner:** `supplier_retention_specialist`
- **Contributors:** supplier_intelligence_analyst; marketplace_director; communications_manager
- **Independent reviewer/challenge role:** `supplier_verification_reviewer`
- **Criticality:** `medium`
- **Primary business object:** `supplier_retention_case`
- **State profile:** `retention_cycle`

## Start and end

- **Start event:** Supplier churn/response decline
- **Required end state:** Measured recovery or exit decision recommendation
- **Founder boundary:** No override of verification/enforcement

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W19-S01 | Open supplier retention case | intake | supplier_retention_specialist |  | Open supplier-retention case. | Signal is linked to an approved supplier and measured baseline. |
| 2 | W19-S02 | Analyze supplier behavior and context | analysis | supplier_intelligence_analyst |  | Supplier behavior analysis. | Analysis distinguishes supplier-side cause from platform demand or workflow failure. |
| 3 | W19-S03 | Diagnose retention cause | analysis | supplier_retention_specialist |  | Retention diagnosis and proposed intervention. | Diagnosis is evidence-based and does not override verification or enforcement. |
| 4 | W19-S04 | Approve supplier intervention | decision | marketplace_director |  | Supplier retention action plan. | Action stays within supplier fairness and commercial policy. |
| 5 | W19-S05 | Execute and measure intervention | execution | supplier_retention_specialist |  | Intervention result. | Outcome measures active supply/response improvement, not only contact activity. |
| 6 | W19-S06 | Escalate verification or enforcement issue | handoff | supplier_verification_reviewer |  | Verification/enforcement handoff. | Retention role cannot keep an unsafe supplier active. |
| 7 | W19-S07 | Close supplier retention case | closure | supplier_retention_specialist | marketplace_director | Closed supplier-retention record. | Final state, residual gap and next review date are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W19-01-02 | W19-S01 | W19-S02 | supplier_retention_specialist | supplier_intelligence_analyst | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W19-02-03 | W19-S02 | W19-S03 | supplier_intelligence_analyst | supplier_retention_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W19-03-04 | W19-S03 | W19-S04 | supplier_retention_specialist | marketplace_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W19-04-05 | W19-S04 | W19-S05 | marketplace_director | supplier_retention_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W19-05-06 | W19-S05 | W19-S06 | supplier_retention_specialist | supplier_verification_reviewer | within_department | Retention analysis reveals verification, fraud or conduct concern. Workflow record; prior accepted outputs; applicable policy. |
| H-W19-06-07 | W19-S06 | W19-S07 | supplier_verification_reviewer | supplier_retention_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-034 | Consent and suppression enforcement | Notifications must respect consent, opt-out, suppression, frequency and sender-policy rules. |
| BR-041 | Activity is not outcome | Managers may not declare success solely from activity or vanity metrics when a business outcome is defined. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-032 | Retention action requests unauthorized discount | customer_success_director | chief_revenue_officer | Block discount; use within-policy option or founder decision. |
| EX-033 | Supplier disengagement caused by platform failure | supplier_retention_specialist | marketplace_director | Open process/product issue rather than blaming supplier. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
