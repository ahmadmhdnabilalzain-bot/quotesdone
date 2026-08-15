# W28 — Legal, compliance and risk review

## Purpose

Create a documented legal, compliance and risk position with controls, escalation and founder gates.

## Ownership

- **Accountable workflow owner:** `general_counsel`
- **Contributors:** compliance_privacy_officer; risk_governance_manager; contract_manager; trust_safety_manager
- **Independent reviewer/challenge role:** `ceo`
- **Criticality:** `critical`
- **Primary business object:** `legal_risk_review`
- **State profile:** `review_cycle`

## Start and end

- **Start event:** Legal/compliance/risk event
- **Required end state:** Position, verdict, controls and escalation
- **Founder boundary:** Founder for material binding commitment

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W28-S01 | Open legal/compliance/risk review | intake | general_counsel |  | Open legal-risk case. | Question, parties, jurisdiction, deadline and decision owner are explicit. |
| 2 | W28-S02 | Gather facts and source documents | execution | contract_manager |  | Review evidence packet. | Facts are separated from assumptions and source versions are recorded. |
| 3 | W28-S03 | Assess legal position | analysis | general_counsel |  | Legal position memorandum. | Legal fact, interpretation and uncertainty are distinguished. |
| 4 | W28-S04 | Assess compliance and privacy | review | compliance_privacy_officer |  | Compliance/privacy verdict. | Violating activity is blocked or controlled and evidence is explicit. |
| 5 | W28-S05 | Assess risk and control adequacy | review | risk_governance_manager |  | Risk/control assessment. | Residual risk and risk owner are explicit. |
| 6 | W28-S06 | Develop contract/control response | execution | contract_manager |  | Proposed legal/control response. | Response follows the approved position and does not exceed authority. |
| 7 | W28-S07 | Issue review decision | decision | general_counsel | ceo | Legal/compliance/risk decision. | Material binding commitments or founder-reserved policy are escalated. |
| 8 | W28-S08 | Monitor obligations and controls | measurement | risk_governance_manager |  | Obligation/control monitoring record. | Every obligation/control has one owner and due date. |
| 9 | W28-S09 | Close legal-risk case | closure | general_counsel |  | Closed legal/compliance/risk record. | Residual risk and future review triggers are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W28-01-02 | W28-S01 | W28-S02 | general_counsel | contract_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-02-03 | W28-S02 | W28-S03 | contract_manager | general_counsel | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-03-04 | W28-S03 | W28-S04 | general_counsel | compliance_privacy_officer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-04-05 | W28-S04 | W28-S05 | compliance_privacy_officer | risk_governance_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-05-06 | W28-S05 | W28-S06 | risk_governance_manager | contract_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-06-07 | W28-S06 | W28-S07 | contract_manager | general_counsel | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-07-08 | W28-S07 | W28-S08 | general_counsel | risk_governance_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W28-08-09 | W28-S08 | W28-S09 | risk_governance_manager | general_counsel | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-028 | Legal-risk authority | Legal/compliance/risk review complete and founder gate satisfied where required. | Block/escalate. |
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
| EX-044 | Tax matter requires current professional interpretation | financial_controller | general_counsel | Escalate to current authoritative source/external UAE tax professional. |
| EX-045 | Legal review requires founder-reserved commitment | general_counsel | founder | Block execution and submit impact/evidence for founder decision. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
