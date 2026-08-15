# W07 — Document/BOQ/drawing processing

## Purpose

Classify, extract and structure uploaded documents, BOQs and drawings while preserving provenance and unresolved gaps.

## Ownership

- **Accountable workflow owner:** `document_intelligence_manager`
- **Contributors:** boq_specification_analyst; drawing_cad_analyst; category overlay
- **Independent reviewer/challenge role:** `marketplace_content_privacy_reviewer`
- **Criticality:** `high`
- **Primary business object:** `inquiry_document`
- **State profile:** `document_cycle`

## Start and end

- **Start event:** Document uploaded/received
- **Required end state:** Structured evidence and unresolved gaps
- **Founder boundary:** No invented values

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W07-S01 | Register document and provenance | intake | document_intelligence_manager |  | Registered document revision. | Owner and source are explicit and the file is not treated as trusted content merely because it uploaded. |
| 2 | W07-S02 | Classify document type and handling path | decision | document_intelligence_manager |  | Document handling plan. | Exactly one primary handling path and any secondary analysis needs are identified. |
| 3 | W07-S03 | Validate document usability | review | document_intelligence_manager |  | Usable, quarantined or rejected document state. | Unsupported, corrupt or unsafe files do not proceed. |
| 4 | W07-S04 | Extract BOQ/specification evidence | analysis | boq_specification_analyst |  | Versioned BOQ/specification extraction. | Every extracted value has provenance and uncertain values remain unconfirmed. |
| 5 | W07-S05 | Extract drawing/CAD evidence | analysis | drawing_cad_analyst |  | Versioned drawing/CAD extraction. | No dimension or technical fact is invented; unavailable views remain explicit. |
| 6 | W07-S06 | Resolve document conflicts | review | document_intelligence_manager |  | Resolved evidence, corroboration or unresolved conflict. | Conflicting evidence is not silently overwritten. |
| 7 | W07-S07 | Return structured evidence to inquiry | handoff | document_intelligence_manager |  | Document-evidence handoff packet. | Packet identifies exact document revisions and no rejected content is marked accepted. |
| 8 | W07-S08 | Close document-processing cycle | closure | document_intelligence_manager |  | Closed document-processing record. | Status matches evidence and any next accountable owner is explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W07-03-04 | W07-S03 | W07-S04 | document_intelligence_manager | boq_specification_analyst | within_department | Document classified as BOQ or specification. Workflow record; prior accepted outputs; applicable policy. |
| H-W07-04-05 | W07-S04 | W07-S05 | boq_specification_analyst | drawing_cad_analyst | within_department | Document classified as drawing or CAD. Workflow record; prior accepted outputs; applicable policy. |
| H-W07-05-06 | W07-S05 | W07-S06 | drawing_cad_analyst | document_intelligence_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-012 | Document usability | Document is supported, readable, owned and safe for processing. | Quarantine/reject. |
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
| BR-013 | Quote-ready inquiry required | No inquiry may be dispatched while mandatory qualification, route, document or readiness blockers remain. |
| BR-027 | Evidence provenance | Every extracted document fact, normalization, score and review finding must retain source/version provenance. |
| BR-028 | Never infer unsupported technical facts | Missing technical, quantity, regulatory or document facts remain unknown and trigger clarification/escalation. |
| BR-029 | Document conflict preserved | Conflicting evidence is preserved and cannot be silently overwritten by lower-authority evidence. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-048 | Category overlays cannot dispatch | Category overlays provide qualification and comparison expertise but cannot approve suppliers, dispatch, reveal identity or change policy. |
| BR-049 | One inquiry owner remains accountable | Specialist and document handoffs do not transfer overall inquiry accountability away from RFQ Qualification Manager unless an explicit approved workflow says so. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-010 | Document unreadable/corrupt/unsupported | document_intelligence_manager | customer_support_specialist | Quarantine/reject document and request a usable revision. |
| EX-011 | Document contains conflicting values | document_intelligence_manager | rfq_qualification_manager | Preserve conflict; request customer/authoritative clarification. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
