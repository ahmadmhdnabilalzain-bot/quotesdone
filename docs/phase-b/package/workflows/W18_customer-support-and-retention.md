# W18 — Customer support and retention

## Purpose

Resolve customer issues, reduce churn and execute measured retention actions without consent or authority violations.

## Ownership

- **Accountable workflow owner:** `customer_success_director`
- **Contributors:** customer_support_specialist; customer_retention_specialist; rfq_success_specialist
- **Independent reviewer/challenge role:** `corporate_performance_director`
- **Criticality:** `medium`
- **Primary business object:** `customer_case`
- **State profile:** `support_cycle`

## Start and end

- **Start event:** Customer issue/churn signal
- **Required end state:** Resolved issue or measured retention action
- **Founder boundary:** No spam/consent breach

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W18-S01 | Open customer case | intake | customer_support_specialist |  | Open classified customer case. | Customer ownership, issue type, urgency and source are explicit. |
| 2 | W18-S02 | Resolve normal support request | execution | customer_support_specialist |  | Resolution, information request or handoff. | Support does not guess technical, legal or financial answers. |
| 3 | W18-S03 | Escalate workflow-specific issue | handoff | customer_support_specialist |  | Accepted specialist handoff. | Receiving owner, evidence, request and return condition are complete. |
| 4 | W18-S04 | Diagnose churn or dissatisfaction | analysis | customer_retention_specialist |  | Retention diagnosis. | Diagnosis is based on behavior/evidence rather than generic outreach. |
| 5 | W18-S05 | Approve retention intervention | decision | customer_success_director |  | Retention action plan. | No unauthorized discount, spam or policy change is included. |
| 6 | W18-S06 | Execute customer intervention | execution | customer_retention_specialist |  | Retention-intervention result. | Consent/frequency rules pass and the action is linked to the diagnosis. |
| 7 | W18-S07 | Measure and close case | closure | customer_success_director |  | Closed customer case and measured outcome. | Closure records whether the underlying issue was actually resolved. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W18-03-04 | W18-S03 | W18-S04 | customer_support_specialist | customer_retention_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W18-04-05 | W18-S04 | W18-S05 | customer_retention_specialist | customer_success_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W18-05-06 | W18-S05 | W18-S06 | customer_success_director | customer_retention_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W18-06-07 | W18-S06 | W18-S07 | customer_retention_specialist | customer_success_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| EX-031 | Customer case requires specialist answer | customer_support_specialist | customer_success_director | Create complete handoff; do not guess. |
| EX-032 | Retention action requests unauthorized discount | customer_success_director | chief_revenue_officer | Block discount; use within-policy option or founder decision. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
