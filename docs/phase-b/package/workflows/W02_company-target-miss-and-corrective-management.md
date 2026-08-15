# W02 — Company target miss and corrective management

## Purpose

Diagnose material trajectory or KPI misses and create, assign, monitor and close corrective action.

## Ownership

- **Accountable workflow owner:** `corporate_performance_director`
- **Contributors:** ceo; chief_of_staff; department heads; data_intelligence_director; cfo
- **Independent reviewer/challenge role:** `strategy_director`
- **Criticality:** `high`
- **Primary business object:** `performance_recovery_case`
- **State profile:** `improvement_cycle`

## Start and end

- **Start event:** Material KPI/trajectory miss
- **Required end state:** Binding-constraint diagnosis and corrective initiative
- **Founder boundary:** Founder only for reserved policy/budget changes

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W02-S01 | Detect material trajectory miss | intake | corporate_performance_director |  | Performance-recovery case with trigger evidence. | Miss is measured against an approved baseline and is not a data-quality artefact. |
| 2 | W02-S02 | Validate the measurement | review | data_intelligence_director |  | Validated miss or corrected measurement. | The miss is confirmed with traceable data or closed as a measurement defect. |
| 3 | W02-S03 | Identify the binding constraint | analysis | corporate_performance_director |  | Causal diagnosis and binding-constraint statement. | Diagnosis distinguishes activity, leading indicators, conversion, revenue, cost and risk. |
| 4 | W02-S04 | Develop recovery scenarios | analysis | strategy_director |  | Recovery options and scenario comparison. | Options include a no-change baseline and explicit assumptions. |
| 5 | W02-S05 | Assess affordability and resource trade-offs | analysis | cfo |  | Financial impact and affordability assessment. | No option exceeds founder-approved financial authority without escalation. |
| 6 | W02-S06 | Approve corrective initiative | decision | ceo | strategy_director | Approved corrective initiative or founder decision request. | Decision addresses the binding constraint and states measurable success and failure conditions. |
| 7 | W02-S07 | Assign corrective work | handoff | chief_of_staff |  | Corrective work plan and assignments. | Every work item has one accountable owner and a defined return path. |
| 8 | W02-S08 | Measure intervention outcome | measurement | corporate_performance_director |  | Outcome comparison and variance diagnosis. | Outcome uses the predeclared metrics and does not substitute vanity measures. |
| 9 | W02-S09 | Close, continue or revise recovery | closure | ceo |  | Closed recovery case or approved next recovery cycle. | Closure records the result, remaining risk and any validated organizational lesson. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W02-01-02 | W02-S01 | W02-S02 | corporate_performance_director | data_intelligence_director | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-02-03 | W02-S02 | W02-S03 | data_intelligence_director | corporate_performance_director | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-03-04 | W02-S03 | W02-S04 | corporate_performance_director | strategy_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-04-05 | W02-S04 | W02-S05 | strategy_director | cfo | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-05-06 | W02-S05 | W02-S06 | cfo | ceo | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-06-07 | W02-S06 | W02-S07 | ceo | chief_of_staff | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-07-08 | W02-S07 | W02-S08 | chief_of_staff | corporate_performance_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W02-08-09 | W02-S08 | W02-S09 | corporate_performance_director | ceo | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-003 | Founder-reserved boundaries | No AI role may approve or alter a founder-reserved decision. |
| BR-004 | Canonical identity only for new work | All new workflow ownership and state writes use canonical active identities; aliases are input/history compatibility only. |
| BR-005 | Inactive identity cannot act | Inactive, merged-away or unknown identities cannot own or execute current work. |
| BR-006 | Valid transition only | Business objects and workflow runs may move only through declared state transitions. |
| BR-007 | Prerequisite enforcement | A step cannot start or complete before all required predecessor outputs and gates pass. |
| BR-008 | Complete handoff packet | A receiving owner may reject an incomplete handoff; incomplete handoffs cannot be treated as accepted. |
| BR-009 | Closure criteria required | No workflow may close while a mandatory step, blocker, obligation or handoff remains unresolved. |
| BR-010 | History preservation | Completed decisions, reviews, acceptances, revisions and attempts are never overwritten; changes create new versions/records. |
| BR-040 | Metric definition consistency | Reports and forecasts use canonical metric definitions and source lineage. |
| BR-041 | Activity is not outcome | Managers may not declare success solely from activity or vanity metrics when a business outcome is defined. |
| BR-042 | Uncertainty explicit | Analysis and decisions must distinguish fact, assumption, inference, confidence and unresolved uncertainty. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-002 | Company KPI miss caused by bad data | data_intelligence_director | corporate_performance_director | Correct the measurement; do not open/continue an operational recovery based on invalid data. |
| EX-003 | Corrective action exceeds approved budget | cfo | founder | Block approval and submit founder decision request with impact. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
