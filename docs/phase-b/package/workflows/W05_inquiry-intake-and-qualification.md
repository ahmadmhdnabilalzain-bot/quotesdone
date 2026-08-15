# W05 — Inquiry intake and qualification

## Purpose

Convert a customer request into a structured, legitimate and quote-ready inquiry or an explicit blocked/clarification state.

## Ownership

- **Accountable workflow owner:** `rfq_qualification_manager`
- **Contributors:** inquiry_router; category overlay; document_intelligence_manager
- **Independent reviewer/challenge role:** `inquiry_quality_scoring_analyst`
- **Criticality:** `critical`
- **Primary business object:** `inquiry`
- **State profile:** `qualification_cycle`

## Start and end

- **Start event:** Customer starts inquiry
- **Required end state:** Structured quote-ready or explicitly blocked inquiry
- **Founder boundary:** No dispatch before readiness/privacy gates

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W05-S01 | Open inquiry case | intake | rfq_qualification_manager |  | Open inquiry with raw request and customer ownership. | Inquiry identity, customer ownership and original content are preserved. |
| 2 | W05-S02 | Obtain route candidates | handoff | inquiry_router |  | Route-candidate set and routing status. | Uncertainty is explicit and no uncertain route is treated as confirmed. |
| 3 | W05-S03 | Load minimum qualification requirements | analysis | rfq_qualification_manager |  | Inquiry qualification requirement set. | Requirements are route-specific, versioned and do not duplicate already answered information. |
| 4 | W05-S04 | Process provided documents | handoff | document_intelligence_manager |  | Structured document evidence packet. | No unverified extraction is accepted as a confirmed mandatory answer. |
| 5 | W05-S05 | Ask minimum sufficient questions | execution | rfq_qualification_manager |  | Customer answers and updated structured inquiry. | No duplicate or irrelevant question is asked; mandatory uncertainty remains visible. |
| 6 | W05-S06 | Validate consistency and legitimacy | review | inquiry_quality_scoring_analyst |  | Quality score, blockers and evidence basis. | Score is reproducible from defined fields and blockers; no activity-only score is used. |
| 7 | W05-S07 | Decide qualification status | decision | rfq_qualification_manager | inquiry_quality_scoring_analyst | Qualification decision and next-state reason. | Quote-ready is impossible while a mandatory blocker remains. |
| 8 | W05-S08 | Freeze qualification version | execution | rfq_qualification_manager |  | Versioned qualified inquiry snapshot. | Snapshot references the exact answers, documents and route versions used. |
| 9 | W05-S09 | Close or hand off inquiry qualification | closure | rfq_qualification_manager |  | Closed qualification case or W08 handoff packet. | End state and next accountable owner are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W05-01-02 | W05-S01 | W05-S02 | rfq_qualification_manager | inquiry_router | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W05-02-03 | W05-S02 | W05-S03 | inquiry_router | rfq_qualification_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W05-03-04 | W05-S03 | W05-S04 | rfq_qualification_manager | document_intelligence_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W05-04-05 | W05-S04 | W05-S05 | document_intelligence_manager | rfq_qualification_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W05-05-06 | W05-S05 | W05-S06 | rfq_qualification_manager | inquiry_quality_scoring_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W05-06-07 | W05-S06 | W05-S07 | inquiry_quality_scoring_analyst | rfq_qualification_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-010 | Inquiry route evidence | Active route is confirmed with sufficient evidence. | Keep route proposed/blocked. |
| GATE-011 | Inquiry quote readiness | Mandatory qualification fields and evidence pass; no unresolved blocker. | Block dispatch path. |
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
| BR-042 | Uncertainty explicit | Analysis and decisions must distinguish fact, assumption, inference, confidence and unresolved uncertainty. |
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
| EX-007 | Inquiry has no supported category | inquiry_router | rfq_qualification_manager | Keep inquiry blocked; request clarification or open taxonomy gap. |
| EX-009 | Customer refuses mandatory information | rfq_qualification_manager | inquiry_quality_scoring_analyst | Mark blocked/not quote-ready; explain consequence. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
