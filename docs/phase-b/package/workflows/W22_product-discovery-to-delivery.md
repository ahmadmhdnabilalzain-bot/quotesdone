# W22 — Product discovery to delivery

## Purpose

Move an approved product need through UX, engineering, verification and independent release approval.

## Ownership

- **Accountable workflow owner:** `product_manager`
- **Contributors:** product_ux_designer; engineering_manager; solution_architect; backend_engineer; frontend_engineer
- **Independent reviewer/challenge role:** `qa_release_management_director`
- **Criticality:** `high`
- **Primary business object:** `product_change`
- **State profile:** `delivery_cycle`

## Start and end

- **Start event:** Validated product need
- **Required end state:** Implemented release candidate with acceptance evidence
- **Founder boundary:** No production release without independent gate

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W22-S01 | Define and prioritize the requirement | decision | product_manager |  | Approved product requirement. | Requirement has one accountable owner, measurable acceptance criteria and a reason to build. |
| 2 | W22-S02 | Own experience design and UX acceptance criteria | execution | product_ux_designer |  | UX specification, prototype and UX acceptance criteria. | All affected user states, errors, empty states and accessibility/RTL requirements are explicit. |
| 3 | W22-S03 | Own implementation delivery | execution | engineering_manager |  | Engineering delivery plan. | Backend/frontend ownership is separated and dependencies are explicit. |
| 4 | W22-S04 | Implement backend | execution | backend_engineer |  | Backend implementation and technical evidence. | Implementation matches approved contracts and does not introduce an unapproved parallel path. |
| 5 | W22-S05 | Implement frontend | execution | frontend_engineer |  | Frontend implementation and UI evidence. | Implementation matches UX acceptance criteria across required states. |
| 6 | W22-S06 | Verify behavior against acceptance criteria | review | test_automation_engineer |  | Independent test evidence and defects. | Test author is not the final release approver and failed criteria remain visible. |
| 7 | W22-S07 | Release go/no-go | decision | qa_release_management_director |  | Release decision and W24 handoff. | No release proceeds with failed mandatory gates or missing rollback readiness. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W22-01-02 | W22-S01 | W22-S02 | product_manager | product_ux_designer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W22-02-03 | W22-S02 | W22-S03 | product_ux_designer | engineering_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W22-03-04 | W22-S03 | W22-S04 | engineering_manager | backend_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W22-04-05 | W22-S04 | W22-S05 | backend_engineer | frontend_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W22-05-06 | W22-S05 | W22-S06 | frontend_engineer | test_automation_engineer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W22-06-07 | W22-S06 | W22-S07 | test_automation_engineer | qa_release_management_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-022 | Product acceptance | Requirement, UX, backend, frontend and test acceptance are complete. | Return to owner. |
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
| BR-038 | Release independence | Product/engineering/AI implementers cannot issue the final release go/no-go. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-036 | Product requirement lacks acceptance criteria | product_manager | chief_product_technology_officer | Do not start delivery; complete requirement/UX acceptance. |
| EX-037 | Engineering implementation diverges from UX | product_ux_designer | product_manager | Fail UX acceptance; return specific defects. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
