# W20 — Marketing content lifecycle

## Purpose

Plan, create, independently review, publish and learn from marketing content against commercial objectives.

## Ownership

- **Accountable workflow owner:** `marketing_director`
- **Contributors:** brand_creative_manager; content_strategy_copy_specialist; visual_design_specialist; social_media_community_manager; marketing_performance_analyst
- **Independent reviewer/challenge role:** `ai_quality_assurance_reviewer`
- **Criticality:** `high`
- **Primary business object:** `content_campaign`
- **State profile:** `campaign_cycle`

## Start and end

- **Start event:** Campaign/content objective
- **Required end state:** Reviewed published asset and measured learning
- **Founder boundary:** Creator not sole reviewer; claims within policy

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W20-S01 | Define content objective and hypothesis | decision | marketing_director |  | Approved content objective. | Objective connects to a business or funnel outcome and is not only a publishing target. |
| 2 | W20-S02 | Develop content strategy and copy | execution | content_strategy_copy_specialist |  | Versioned copy/content package. | Copy is accurate, relevant, channel-appropriate and within claim policy. |
| 3 | W20-S03 | Create visual assets | execution | visual_design_specialist |  | Versioned visual asset set. | Required platform formats and source revisions are complete. |
| 4 | W20-S04 | Review brand and campaign alignment | review | brand_creative_manager |  | Brand approval or correction request. | Brand reviewer is not the sole technical reviewer and unsupported claims are rejected. |
| 5 | W20-S05 | Independently review final artifact | review | ai_quality_assurance_reviewer |  | Artifact pass/fail and defect list. | Actual rendered file is reviewed; creator cannot self-approve. |
| 6 | W20-S06 | Publish approved content | execution | social_media_community_manager |  | Published content record. | Only the reviewed revision is published and platform IDs are captured. |
| 7 | W20-S07 | Collect performance evidence | measurement | marketing_performance_analyst |  | Content performance dataset. | Evidence covers the declared measurement window and business outcome. |
| 8 | W20-S08 | Diagnose performance | analysis | marketing_performance_analyst |  | Performance diagnosis and next-test recommendation. | Diagnosis does not equate engagement with commercial success. |
| 9 | W20-S09 | Validate learning and close cycle | closure | marketing_director | corporate_performance_director | Closed content cycle and validated learning proposal. | Decision includes expected next result, cost and review window. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W20-01-02 | W20-S01 | W20-S02 | marketing_director | content_strategy_copy_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W20-02-03 | W20-S02 | W20-S03 | content_strategy_copy_specialist | visual_design_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W20-03-04 | W20-S03 | W20-S04 | visual_design_specialist | brand_creative_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W20-04-05 | W20-S04 | W20-S05 | brand_creative_manager | ai_quality_assurance_reviewer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W20-05-06 | W20-S05 | W20-S06 | ai_quality_assurance_reviewer | social_media_community_manager | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W20-06-07 | W20-S06 | W20-S07 | social_media_community_manager | marketing_performance_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W20-08-09 | W20-S08 | W20-S09 | marketing_performance_analyst | marketing_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-004 | Canonical identity only for new work | All new workflow ownership and state writes use canonical active identities; aliases are input/history compatibility only. |
| BR-005 | Inactive identity cannot act | Inactive, merged-away or unknown identities cannot own or execute current work. |
| BR-006 | Valid transition only | Business objects and workflow runs may move only through declared state transitions. |
| BR-007 | Prerequisite enforcement | A step cannot start or complete before all required predecessor outputs and gates pass. |
| BR-008 | Complete handoff packet | A receiving owner may reject an incomplete handoff; incomplete handoffs cannot be treated as accepted. |
| BR-009 | Closure criteria required | No workflow may close while a mandatory step, blocker, obligation or handoff remains unresolved. |
| BR-010 | History preservation | Completed decisions, reviews, acceptances, revisions and attempts are never overwritten; changes create new versions/records. |
| BR-034 | Consent and suppression enforcement | Notifications must respect consent, opt-out, suppression, frequency and sender-policy rules. |
| BR-035 | Only approved asset revision publishes | Marketing or operational content may publish only the exact independently approved revision. |
| BR-036 | Actual artifact review | Visual/video/file review must inspect the actual final artifact, not only the prompt or brief. |
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
| EX-034 | Marketing underperforms despite high engagement | marketing_performance_analyst | marketing_director | Diagnose funnel intent/conversion; do not scale on vanity metrics. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
