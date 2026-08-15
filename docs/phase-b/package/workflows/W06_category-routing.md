# W06 — Category routing

## Purpose

Determine and confirm the correct category/route set without silently activating uncertain scope.

## Ownership

- **Accountable workflow owner:** `inquiry_router`
- **Contributors:** rfq_qualification_manager; category overlays; broad domain specialists
- **Independent reviewer/challenge role:** `inquiry_quality_scoring_analyst`
- **Criticality:** `critical`
- **Primary business object:** `inquiry_route_set`
- **State profile:** `classification_cycle`

## Start and end

- **Start event:** New or changed inquiry evidence
- **Required end state:** Confirmed route set or clarification request
- **Founder boundary:** No silent uncertain activation

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W06-S01 | Normalize routing evidence | intake | inquiry_router |  | Routing evidence set. | Every evidence item retains source, language and authority. |
| 2 | W06-S02 | Generate route candidates | analysis | inquiry_router |  | Candidate routes with evidence and ambiguity. | No route outside the canonical taxonomy is created. |
| 3 | W06-S03 | Evaluate ambiguity and exclusions | analysis | inquiry_router |  | Routing disposition analysis. | Excluded or uncertain scope cannot silently become active. |
| 4 | W06-S04 | Request customer clarification | execution | rfq_qualification_manager |  | Customer clarification or unresolved routing state. | Clarification is specific, necessary and not a generic questionnaire. |
| 5 | W06-S05 | Confirm route set | decision | inquiry_router | inquiry_quality_scoring_analyst | Versioned confirmed/proposed/rejected route set. | Every active route has sufficient evidence and every unresolved route remains non-dispatchable. |
| 6 | W06-S06 | Resolve multi-category coordination | handoff | rfq_qualification_manager |  | Cross-category coordination note. | One inquiry owner remains accountable and broad specialists do not replace specific overlays. |
| 7 | W06-S07 | Publish routing result to inquiry | closure | inquiry_router |  | Closed routing cycle and route-set reference. | The inquiry consumes one canonical route version and routing history remains readable. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W06-03-04 | W06-S03 | W06-S04 | inquiry_router | rfq_qualification_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W06-04-05 | W06-S04 | W06-S05 | rfq_qualification_manager | inquiry_router | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W06-05-06 | W06-S05 | W06-S06 | inquiry_router | rfq_qualification_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W06-06-07 | W06-S06 | W06-S07 | rfq_qualification_manager | inquiry_router | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-014 | Confirmed route required for dispatch | Proposed, ambiguous, rejected or excluded routes cannot independently authorize supplier dispatch. |
| BR-028 | Never infer unsupported technical facts | Missing technical, quantity, regulatory or document facts remain unknown and trigger clarification/escalation. |
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
| EX-008 | Inquiry route ambiguous | inquiry_router | rfq_qualification_manager | Ask targeted clarification; do not activate uncertain routes. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
