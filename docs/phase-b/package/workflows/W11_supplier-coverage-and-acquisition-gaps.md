# W11 — Supplier coverage and acquisition gaps

## Purpose

Measure supplier liquidity gaps and create prioritized acquisition targets tied to inquiry demand and revenue.

## Ownership

- **Accountable workflow owner:** `supplier_coverage_liquidity_specialist`
- **Contributors:** supplier_intelligence_analyst; business_development_manager; category_knowledge_curator
- **Independent reviewer/challenge role:** `marketplace_director`
- **Criticality:** `medium`
- **Primary business object:** `supplier_coverage_case`
- **State profile:** `improvement_cycle`

## Start and end

- **Start event:** Coverage/liquidity KPI miss
- **Required end state:** Prioritized supplier acquisition target
- **Founder boundary:** No unapproved outreach/spend

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W11-S01 | Measure inquiry demand | measurement | supplier_coverage_liquidity_specialist |  | Demand profile. | Demand uses canonical routes and excludes duplicate/invalid inquiries. |
| 2 | W11-S02 | Measure usable supplier supply | measurement | supplier_intelligence_analyst |  | Usable supply profile. | Count distinguishes registered, approved, available and responsive suppliers. |
| 3 | W11-S03 | Calculate coverage and liquidity gap | analysis | supplier_coverage_liquidity_specialist |  | Coverage-gap analysis. | Gap is quantified by route/location and tied to an operational consequence. |
| 4 | W11-S04 | Prioritize acquisition targets | decision | marketplace_director |  | Approved supplier-acquisition target list. | Priorities are evidence-based and within outreach/spend authority. |
| 5 | W11-S05 | Handoff acquisition target | handoff | business_development_manager |  | Acquisition work plan. | Every target has one owner, channel, expected result and budget boundary. |
| 6 | W11-S06 | Measure supplier acquisition outcome | measurement | supplier_coverage_liquidity_specialist |  | Coverage intervention result. | Outcome measures marketplace liquidity, not only outreach volume. |
| 7 | W11-S07 | Close or revise coverage case | closure | marketplace_director |  | Closed/revised supplier-coverage case. | Residual risk and next review date are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W11-01-02 | W11-S01 | W11-S02 | supplier_coverage_liquidity_specialist | supplier_intelligence_analyst | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W11-02-03 | W11-S02 | W11-S03 | supplier_intelligence_analyst | supplier_coverage_liquidity_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W11-03-04 | W11-S03 | W11-S04 | supplier_coverage_liquidity_specialist | marketplace_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W11-04-05 | W11-S04 | W11-S05 | marketplace_director | business_development_manager | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W11-05-06 | W11-S05 | W11-S06 | business_development_manager | supplier_coverage_liquidity_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W11-06-07 | W11-S06 | W11-S07 | supplier_coverage_liquidity_specialist | marketplace_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-004 | Canonical identity only for new work | All new workflow ownership and state writes use canonical active identities; aliases are input/history compatibility only. |
| BR-005 | Inactive identity cannot act | Inactive, merged-away or unknown identities cannot own or execute current work. |
| BR-006 | Valid transition only | Business objects and workflow runs may move only through declared state transitions. |
| BR-007 | Prerequisite enforcement | A step cannot start or complete before all required predecessor outputs and gates pass. |
| BR-008 | Complete handoff packet | A receiving owner may reject an incomplete handoff; incomplete handoffs cannot be treated as accepted. |
| BR-009 | Closure criteria required | No workflow may close while a mandatory step, blocker, obligation or handoff remains unresolved. |
| BR-010 | History preservation | Completed decisions, reviews, acceptances, revisions and attempts are never overwritten; changes create new versions/records. |
| BR-040 | Metric definition consistency | Reports and forecasts use canonical metric definitions and source lineage. |
| BR-041 | Activity is not outcome | Managers may not declare success solely from activity or vanity metrics when a business outcome is defined. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-017 | No eligible suppliers | supplier_matching_dispatch_operator | marketplace_director | Close dispatch as no-eligible-suppliers; open coverage gap and inform customer owner. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
