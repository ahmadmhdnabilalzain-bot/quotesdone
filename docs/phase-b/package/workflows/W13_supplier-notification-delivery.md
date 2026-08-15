# W13 — Supplier notification delivery

## Purpose

Deliver approved messages through permitted channels with consent, suppression, retry and terminal-state handling.

## Ownership

- **Accountable workflow owner:** `lifecycle_channel_operations_specialist`
- **Contributors:** communications_manager; supplier_matching_dispatch_operator
- **Independent reviewer/challenge role:** `compliance_privacy_officer`
- **Criticality:** `high`
- **Primary business object:** `notification_delivery`
- **State profile:** `delivery_cycle`

## Start and end

- **Start event:** Approved queued notification
- **Required end state:** Delivered/failed/suppressed state
- **Founder boundary:** Consent and sender policy enforced

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W13-S01 | Accept approved notification | intake | lifecycle_channel_operations_specialist |  | Open delivery attempt. | Message type, recipient, consent basis and source record are present. |
| 2 | W13-S02 | Apply consent and suppression rules | review | lifecycle_channel_operations_specialist |  | Send-eligible or suppressed decision. | Suppressed recipients cannot proceed to delivery. |
| 3 | W13-S03 | Select permitted channel and template | decision | communications_manager |  | Rendered delivery request. | Template version and channel are approved and contain no disallowed data. |
| 4 | W13-S04 | Attempt delivery | execution | lifecycle_channel_operations_specialist |  | Delivery attempt result. | A provider acknowledgement or explicit adapter failure is recorded. |
| 5 | W13-S05 | Retry eligible failure | execution | lifecycle_channel_operations_specialist |  | Retry result or terminal failure. | Retries do not duplicate successful delivery and respect caps. |
| 6 | W13-S06 | Escalate terminal delivery failure | handoff | communications_manager |  | Terminal-failure escalation. | The business owner can choose an approved alternative or acknowledge non-delivery. |
| 7 | W13-S07 | Close notification delivery | closure | lifecycle_channel_operations_specialist |  | Closed notification-delivery record. | Final state and all attempts reconcile to the canonical notification. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W13-02-03 | W13-S02 | W13-S03 | lifecycle_channel_operations_specialist | communications_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W13-03-04 | W13-S03 | W13-S04 | communications_manager | lifecycle_channel_operations_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W13-05-06 | W13-S05 | W13-S06 | lifecycle_channel_operations_specialist | communications_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W13-06-07 | W13-S06 | W13-S07 | communications_manager | lifecycle_channel_operations_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-016 | Notification eligibility | Assignment exists, template approved, consent/suppression pass. | Suppress/block. |
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
| BR-011 | No customer identity before reveal | Supplier-facing payloads, files, portal views and notifications may not contain customer identity before the approved reveal state. |
| BR-012 | Approved safe package required | No supplier assignment or notification may be created without an approved immutable supplier-safe package. |
| BR-017 | Notification count equals successful assignments | Refused or failed assignments are not counted as contacted and do not create success notifications. |
| BR-034 | Consent and suppression enforcement | Notifications must respect consent, opt-out, suppression, frequency and sender-policy rules. |
| BR-035 | Only approved asset revision publishes | Marketing or operational content may publish only the exact independently approved revision. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-045 | Retry is a new attempt | Retries preserve the failed first attempt and use a new attempt record linked to the original. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-051 | One dispatch source of truth | All supplier assignments and notifications originate from the canonical W12 dispatch batch. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-020 | Notification provider failure | lifecycle_channel_operations_specialist | communications_manager | Retry only eligible errors; escalate terminal failure. |
| EX-021 | Consent/opt-out conflict | lifecycle_channel_operations_specialist | compliance_privacy_officer | Suppress delivery and record legal basis/conflict. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
