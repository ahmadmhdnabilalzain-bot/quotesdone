# W23 — AI/model/prompt change

## Purpose

Design, implement and independently evaluate model, prompt, retrieval or routing changes before release.

## Ownership

- **Accountable workflow owner:** `ai_director`
- **Contributors:** ai_architect; agent_prompt_engineer; product_optimisation_engineer
- **Independent reviewer/challenge role:** `model_evaluation_reviewer`
- **Criticality:** `critical`
- **Primary business object:** `ai_change`
- **State profile:** `change_control_cycle`

## Start and end

- **Start event:** AI capability/change request
- **Required end state:** Evaluated model/prompt/retrieval change
- **Founder boundary:** Evaluator separation and no answer-key leakage

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W23-S01 | Open AI change request | intake | ai_director |  | Open AI change record. | Change scope, affected roles/workflows and reason are explicit. |
| 2 | W23-S02 | Define behavioral and cost acceptance | decision | ai_director |  | AI change acceptance contract. | Criteria include positive and negative cases and do not expose evaluator answer keys. |
| 3 | W23-S03 | Design AI architecture change | analysis | ai_architect |  | AI architecture design. | Design identifies state, authority, evidence, cost and failure behavior. |
| 4 | W23-S04 | Implement prompt/agent/retrieval change | execution | agent_prompt_engineer |  | Versioned AI implementation. | Implementation is traceable and does not alter sealed evaluator material. |
| 5 | W23-S05 | Run internal regression and cost analysis | review | product_optimisation_engineer |  | Internal regression and cost evidence. | Cost, truncation, failure and first-attempt reliability are explicit. |
| 6 | W23-S06 | Conduct independent model evaluation | review | model_evaluation_reviewer |  | Independent model evaluation verdict. | Reviewer did not implement the change and no answer key is exposed. |
| 7 | W23-S07 | Conduct workflow-level AI QA | review | ai_quality_assurance_reviewer |  | Workflow-level AI QA verdict. | Tests cover actual business state, authority and unsafe non-actions. |
| 8 | W23-S08 | Approve release-candidate handoff | decision | ai_director | qa_release_management_director | W24 release-candidate handoff. | Independent verdicts pass and no critical regression remains. |
| 9 | W23-S09 | Close AI change cycle | closure | ai_director |  | Closed AI change record. | Version, evidence and final state are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W23-02-03 | W23-S02 | W23-S03 | ai_director | ai_architect | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W23-03-04 | W23-S03 | W23-S04 | ai_architect | agent_prompt_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W23-04-05 | W23-S04 | W23-S05 | agent_prompt_engineer | product_optimisation_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W23-05-06 | W23-S05 | W23-S06 | product_optimisation_engineer | model_evaluation_reviewer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W23-06-07 | W23-S06 | W23-S07 | model_evaluation_reviewer | ai_quality_assurance_reviewer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W23-07-08 | W23-S07 | W23-S08 | ai_quality_assurance_reviewer | ai_director | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-023 | AI independent evaluation | Independent model and workflow evaluations pass without answer-key leakage. | Block change. |
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
| BR-037 | No self-certification | An agent, department or builder cannot independently certify its own consequential behavior or change. |
| BR-038 | Release independence | Product/engineering/AI implementers cannot issue the final release go/no-go. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-038 | AI change fails independent evaluation | model_evaluation_reviewer | qa_release_management_director | Block release; return sanitized failure classes. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
