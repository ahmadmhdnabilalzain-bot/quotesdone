# W21 — Strategic partnership development

## Purpose

Qualify, structure, review and execute strategic partnership or government engagement opportunities.

## Ownership

- **Accountable workflow owner:** `strategic_partnerships_government_relations_manager`
- **Contributors:** business_development_manager; account_manager; general_counsel
- **Independent reviewer/challenge role:** `chief_revenue_officer`
- **Criticality:** `high`
- **Primary business object:** `partnership_opportunity`
- **State profile:** `opportunity_cycle`

## Start and end

- **Start event:** Qualified partnership opportunity
- **Required end state:** Approved partnership proposal/engagement plan
- **Founder boundary:** Founder for equity/country/material commitments

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W21-S01 | Open partnership opportunity | intake | strategic_partnerships_government_relations_manager |  | Open partnership opportunity. | Counterparty, source, opportunity type and potential business value are explicit. |
| 2 | W21-S02 | Qualify strategic fit | analysis | business_development_manager |  | Qualification assessment. | Unqualified opportunities do not consume legal or executive work. |
| 3 | W21-S03 | Develop partnership structure | analysis | strategic_partnerships_government_relations_manager |  | Partnership proposal. | Structure stays within founder-approved business and commercial policy. |
| 4 | W21-S04 | Conduct due diligence and legal review | review | general_counsel |  | Legal/risk findings and required controls. | Material risks and binding commitments are explicit. |
| 5 | W21-S05 | Approve engagement path | decision | chief_revenue_officer | ceo | Partnership decision. | Reserved commitments, country expansion, equity and material spend are escalated. |
| 6 | W21-S06 | Negotiate and execute approved engagement | execution | strategic_partnerships_government_relations_manager |  | Executed partnership/engagement record. | Executed terms match the approved structure and authority. |
| 7 | W21-S07 | Measure partnership outcome | measurement | account_manager |  | Partnership performance result. | Outcome is measured against the approved business case. |
| 8 | W21-S08 | Close, renew or exit partnership | closure | chief_revenue_officer |  | Final partnership state. | Obligations, data, contracts and residual risks are closed or owned. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W21-01-02 | W21-S01 | W21-S02 | strategic_partnerships_government_relations_manager | business_development_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W21-02-03 | W21-S02 | W21-S03 | business_development_manager | strategic_partnerships_government_relations_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W21-03-04 | W21-S03 | W21-S04 | strategic_partnerships_government_relations_manager | general_counsel | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W21-04-05 | W21-S04 | W21-S05 | general_counsel | chief_revenue_officer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W21-05-06 | W21-S05 | W21-S06 | chief_revenue_officer | strategic_partnerships_government_relations_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W21-06-07 | W21-S06 | W21-S07 | strategic_partnerships_government_relations_manager | account_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W21-07-08 | W21-S07 | W21-S08 | account_manager | chief_revenue_officer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-042 | Uncertainty explicit | Analysis and decisions must distinguish fact, assumption, inference, confidence and unresolved uncertainty. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-035 | Partnership requires equity/country expansion | chief_revenue_officer | founder | Pause execution and submit founder decision. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
