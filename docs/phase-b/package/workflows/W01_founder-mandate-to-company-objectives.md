# W01 — Founder mandate to company objectives

## Purpose

Convert the founder mandate into approved company objectives, department mandates and accountable execution boundaries.

## Ownership

- **Accountable workflow owner:** `ceo`
- **Contributors:** chief_of_staff; corporate_performance_director; strategy_director
- **Independent reviewer/challenge role:** `founder`
- **Criticality:** `high`
- **Primary business object:** `company_objective`
- **State profile:** `governance_cycle`

## Start and end

- **Start event:** Founder mandate
- **Required end state:** Approved company objectives and department mandates
- **Founder boundary:** Founder approves reserved decisions

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W01-S01 | Capture founder mandate | intake | chief_of_staff |  | Versioned founder-mandate record and open objective cycle. | Mandate source, date, scope and founder-reserved implications are explicit. |
| 2 | W01-S02 | Develop strategic options | analysis | strategy_director |  | Strategy options and scenario memorandum. | At least one viable option, assumptions, risks and rejected alternatives are documented. |
| 3 | W01-S03 | Translate target into KPI tree | analysis | corporate_performance_director |  | Company KPI tree and target trajectory. | Outcome metrics are measurable, non-duplicative and causally linked to the mandate. |
| 4 | W01-S04 | Set financial resource envelope | decision | cfo |  | Financial envelope and affordability statement. | Resource limits reconcile to current financial capacity and founder-approved limits. |
| 5 | W01-S05 | Define department mandates | handoff | chief_of_staff |  | Department mandate register. | Every objective has one accountable head and no objective is orphaned or multiply owned. |
| 6 | W01-S06 | Approve operating objective set | decision | ceo | founder | Approved company objectives or founder decision request. | All operating decisions are within delegated authority; reserved items are not self-approved. |
| 7 | W01-S07 | Issue accountable work | execution | chief_of_staff |  | Active initiative and assignment register. | Every initiative has one owner, due date, expected outcome and escalation path. |
| 8 | W01-S08 | Confirm objective cycle closure | closure | corporate_performance_director |  | Closed objective-setting cycle and approved baseline. | No unowned objective, unresolved dependency or unapproved founder-boundary item remains. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W01-01-02 | W01-S01 | W01-S02 | chief_of_staff | strategy_director | within_department | Prior required step accepted or workflow start event. Founder mandate; current company state; external and internal evidence. |
| H-W01-02-03 | W01-S02 | W01-S03 | strategy_director | corporate_performance_director | within_department | Prior required step accepted or workflow start event. Founder mandate; strategy options; current baseline. |
| H-W01-03-04 | W01-S03 | W01-S04 | corporate_performance_director | cfo | cross_department | Prior required step accepted or workflow start event. Strategy options; KPI tree; current cash, budget and commitments. |
| H-W01-04-05 | W01-S04 | W01-S05 | cfo | chief_of_staff | cross_department | Prior required step accepted or workflow start event. KPI tree; strategy option; resource envelope. |
| H-W01-05-06 | W01-S05 | W01-S06 | chief_of_staff | ceo | within_department | Prior required step accepted or workflow start event. Strategy options; KPI tree; department mandates; budget envelope. |
| H-W01-06-07 | W01-S06 | W01-S07 | ceo | chief_of_staff | within_department | Prior required step accepted or workflow start event. Approved company objectives and department mandates. |
| H-W01-07-08 | W01-S07 | W01-S08 | chief_of_staff | corporate_performance_director | within_department | Prior required step accepted or workflow start event. Issued initiatives; complete ownership and measurement setup. |

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
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-001 | Duplicate or conflicting founder mandate | chief_of_staff | ceo | Pause objective cycle; preserve both versions; request founder clarification. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
