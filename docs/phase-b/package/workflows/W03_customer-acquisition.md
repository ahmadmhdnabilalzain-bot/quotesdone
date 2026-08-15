# W03 — Customer acquisition

## Purpose

Create qualified customer demand and measure acquisition through to commercial outcomes.

## Ownership

- **Accountable workflow owner:** `chief_revenue_officer`
- **Contributors:** marketing_director; business_development_manager; crm_revenue_operations_manager; marketing_performance_analyst
- **Independent reviewer/challenge role:** `corporate_performance_director`
- **Criticality:** `medium`
- **Primary business object:** `growth_program`
- **State profile:** `campaign_cycle`

## Start and end

- **Start event:** Growth objective/campaign cycle
- **Required end state:** Qualified customer pipeline and measured acquisition
- **Founder boundary:** Founder-approved budgets and commercial rules

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W03-S01 | Set acquisition objective | decision | chief_revenue_officer |  | Approved acquisition brief. | Objective links to a defined pipeline or revenue outcome and stays within founder policy. |
| 2 | W03-S02 | Develop audience and market evidence | analysis | marketing_performance_analyst |  | Audience and channel evidence pack. | Audience definition and baseline are evidence-based and measurable. |
| 3 | W03-S03 | Create campaign plan | execution | marketing_director |  | Campaign plan and content calendar. | Plan has a clear hypothesis, channel fit, budget limit and business outcome. |
| 4 | W03-S04 | Create message and creative brief | execution | brand_creative_manager |  | Approved creative brief. | Brief is consistent with brand and does not make unsupported claims. |
| 5 | W03-S05 | Produce campaign assets | execution | content_strategy_copy_specialist |  | Campaign asset set. | All required channels and formats are represented and versioned. |
| 6 | W03-S06 | Review campaign assets | review | ai_quality_assurance_reviewer |  | Approve, reject or correction request. | Reviewer did not author the artifact and all mandatory defects are resolved. |
| 7 | W03-S07 | Publish and capture lead events | execution | social_media_community_manager |  | Published campaign and attributed lead records. | Only approved assets are published and all trackable events use the canonical campaign ID. |
| 8 | W03-S08 | Measure performance and attribution | measurement | marketing_performance_analyst |  | Campaign performance analysis. | Analysis separates activity and vanity metrics from commercial outcomes. |
| 9 | W03-S09 | Optimize or close the campaign | closure | chief_revenue_officer |  | Closed campaign or approved optimization cycle. | Decision states evidence, cost, expected next result and review window. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W03-01-02 | W03-S01 | W03-S02 | chief_revenue_officer | marketing_performance_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-02-03 | W03-S02 | W03-S03 | marketing_performance_analyst | marketing_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-03-04 | W03-S03 | W03-S04 | marketing_director | brand_creative_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-04-05 | W03-S04 | W03-S05 | brand_creative_manager | content_strategy_copy_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-05-06 | W03-S05 | W03-S06 | content_strategy_copy_specialist | ai_quality_assurance_reviewer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-06-07 | W03-S06 | W03-S07 | ai_quality_assurance_reviewer | social_media_community_manager | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-07-08 | W03-S07 | W03-S08 | social_media_community_manager | marketing_performance_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W03-08-09 | W03-S08 | W03-S09 | marketing_performance_analyst | chief_revenue_officer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-021 | Marketing artifact approval | Exact final asset passes brand and independent artifact review. | Reject/return correction. |
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
| EX-004 | Campaign asset contains unsupported claim | ai_quality_assurance_reviewer | compliance_privacy_officer | Reject the asset; return exact defect to creator. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
