# W14 — Quotation submission and evaluation

## Purpose

Receive, version, validate and normalize supplier quotations for fair technical and commercial comparison.

## Ownership

- **Accountable workflow owner:** `quote_evaluation_specialist`
- **Contributors:** category overlay; broad domain specialist; document_intelligence_manager
- **Independent reviewer/challenge role:** `rfq_success_specialist`
- **Criticality:** `critical`
- **Primary business object:** `quotation`
- **State profile:** `submission_review_cycle`

## Start and end

- **Start event:** Supplier submits/revises quote
- **Required end state:** Validated normalized comparison input
- **Founder boundary:** No alteration of supplier quote

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W14-S01 | Open supplier quote window | intake | quote_evaluation_specialist |  | Open quotation case. | Supplier is assigned, approved and within the valid response window. |
| 2 | W14-S02 | Receive supplier acknowledgement | execution | rfq_success_specialist |  | Supplier response state. | Response is linked to the exact assignment and cannot be forged by another supplier. |
| 3 | W14-S03 | Receive quotation revision | execution | quote_evaluation_specialist |  | Immutable quotation revision. | Supplier ownership, required fields and revision sequence are valid. |
| 4 | W14-S04 | Validate commercial completeness | review | quote_evaluation_specialist |  | Commercial completeness findings. | Missing commercial fields are explicit and quote values remain supplier-authored. |
| 5 | W14-S05 | Validate technical completeness | analysis | relevant_category_overlay |  | Technical completeness findings. | No unsupported technical conclusion is introduced and missing fields remain blockers. |
| 6 | W14-S06 | Request supplier clarification if needed | handoff | quote_evaluation_specialist |  | Clarification request and subsequent revision link. | Request is necessary, specific and version-preserving. |
| 7 | W14-S07 | Normalize comparable fields | analysis | quote_evaluation_specialist |  | Normalized quotation record. | Every normalized value traces to the original or a declared calculation. |
| 8 | W14-S08 | Approve or exclude quote from comparison | decision | quote_evaluation_specialist | rfq_success_specialist | Comparison eligibility decision. | Decision is evidence-based and customer visibility remains false until W15. |
| 9 | W14-S09 | Close quotation collection | closure | quote_evaluation_specialist |  | Closed quotation collection and W15 packet. | All assignments have a terminal response state and valid quotes are version-locked. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W14-01-02 | W14-S01 | W14-S02 | quote_evaluation_specialist | rfq_success_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W14-02-03 | W14-S02 | W14-S03 | rfq_success_specialist | quote_evaluation_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W14-04-05 | W14-S04 | W14-S05 | quote_evaluation_specialist | relevant_category_overlay | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W14-05-06 | W14-S05 | W14-S06 | relevant_category_overlay | quote_evaluation_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-014 | Supplier verification | Supplier is currently approved and capability evidence supports scope. | Exclude/block. |
| GATE-017 | Quotation completeness | Mandatory commercial/technical fields and provenance pass. | Hold/exclude. |
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
| BR-015 | Supplier approval required | Only currently approved, eligible suppliers may receive a dispatch assignment. |
| BR-018 | Supplier quote remains supplier-authored | The platform may normalize for comparison but cannot alter the supplier's original quotation revision. |
| BR-019 | Published quote visibility only | Customers may see only their own approved/published quotation comparison versions. |
| BR-027 | Evidence provenance | Every extracted document fact, normalization, score and review finding must retain source/version provenance. |
| BR-028 | Never infer unsupported technical facts | Missing technical, quantity, regulatory or document facts remain unknown and trigger clarification/escalation. |
| BR-029 | Document conflict preserved | Conflicting evidence is preserved and cannot be silently overwritten by lower-authority evidence. |
| BR-042 | Uncertainty explicit | Analysis and decisions must distinguish fact, assumption, inference, confidence and unresolved uncertainty. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-048 | Category overlays cannot dispatch | Category overlays provide qualification and comparison expertise but cannot approve suppliers, dispatch, reveal identity or change policy. |
| BR-050 | One comparison source of truth | Customer comparison uses the canonical normalized quote records and published version, not multiple conflicting comparison implementations. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-022 | Supplier quote missing mandatory fields | quote_evaluation_specialist | rfq_success_specialist | Request specific clarification/revision; exclude until complete. |
| EX-023 | Supplier quote materially conflicts with scope | relevant_category_overlay | quote_evaluation_specialist | Mark technical conflict; request clarification; do not normalize away difference. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
