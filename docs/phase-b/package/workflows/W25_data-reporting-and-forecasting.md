# W25 — Data reporting and forecasting

## Purpose

Create reliable metrics, reports and forecasts with provenance, uncertainty and decision relevance.

## Ownership

- **Accountable workflow owner:** `data_intelligence_director`
- **Contributors:** business_intelligence_analyst; data_engineer; forecasting_analyst; market_intelligence_analyst
- **Independent reviewer/challenge role:** `corporate_performance_director`
- **Criticality:** `high`
- **Primary business object:** `intelligence_product`
- **State profile:** `reporting_cycle`

## Start and end

- **Start event:** Reporting/forecast requirement
- **Required end state:** Decision-grade report/forecast
- **Founder boundary:** No unsupported causal claim

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W25-S01 | Open intelligence request or cadence | intake | data_intelligence_director |  | Open intelligence work item. | The business decision the output must support is explicit. |
| 2 | W25-S02 | Define metrics and source contract | decision | data_intelligence_director |  | Metric/source specification. | Definitions are canonical and do not conflict with existing approved metrics. |
| 3 | W25-S03 | Validate and prepare data | execution | data_engineer |  | Validated analytical dataset. | Lineage, completeness, freshness and known limitations are recorded. |
| 4 | W25-S04 | Construct analysis and report | analysis | business_intelligence_analyst |  | Draft intelligence report. | Claims are supported and correlation is not presented as causation. |
| 5 | W25-S05 | Construct forecast and uncertainty | analysis | forecasting_analyst |  | Forecast/scenario component. | Forecast states uncertainty and does not conceal weak data. |
| 6 | W25-S06 | Review decision relevance and integrity | review | data_intelligence_director | corporate_performance_director | Approved or corrected intelligence product. | Output is relevant, reproducible and fit for the target audience. |
| 7 | W25-S07 | Publish and capture decision usage | handoff | data_intelligence_director |  | Published intelligence product and usage link. | Access is authorized and the product is not orphaned in an unread table. |
| 8 | W25-S08 | Close or schedule refresh | closure | data_intelligence_director |  | Final intelligence lifecycle state. | Review date and supersession conditions are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W25-02-03 | W25-S02 | W25-S03 | data_intelligence_director | data_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W25-03-04 | W25-S03 | W25-S04 | data_engineer | business_intelligence_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W25-04-05 | W25-S04 | W25-S05 | business_intelligence_analyst | forecasting_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W25-05-06 | W25-S05 | W25-S06 | forecasting_analyst | data_intelligence_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-025 | Data integrity | Metric/source definitions, lineage and quality pass. | Reject/correct. |
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
| BR-027 | Evidence provenance | Every extracted document fact, normalization, score and review finding must retain source/version provenance. |
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
| EX-041 | Report uses inconsistent metric definition | data_intelligence_director | corporate_performance_director | Reject report; correct metric/source contract. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
