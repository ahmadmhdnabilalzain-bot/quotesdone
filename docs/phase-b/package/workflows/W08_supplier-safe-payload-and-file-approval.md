# W08 — Supplier-safe payload and file approval

## Purpose

Create and independently approve the immutable supplier-facing brief and file set with no customer identity leakage.

## Ownership

- **Accountable workflow owner:** `marketplace_content_privacy_reviewer`
- **Contributors:** rfq_qualification_manager; document_intelligence_manager; compliance_privacy_officer
- **Independent reviewer/challenge role:** `compliance_privacy_officer`
- **Criticality:** `critical`
- **Primary business object:** `supplier_safe_package`
- **State profile:** `independent_review_cycle`

## Start and end

- **Start event:** Quote-ready inquiry proposed for suppliers
- **Required end state:** Approved immutable supplier-safe package or rejection
- **Founder boundary:** No customer identity leakage

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W08-S01 | Create supplier-safe brief candidate | execution | rfq_qualification_manager |  | Candidate supplier-safe brief version. | Candidate references one qualified inquiry version and contains only allowed fields. |
| 2 | W08-S02 | Prepare supplier-facing files | execution | document_intelligence_manager |  | Candidate supplier-facing file set. | Every file has a source revision and no original unsafe file is substituted. |
| 3 | W08-S03 | Run privacy and identity review | review | marketplace_content_privacy_reviewer |  | Privacy review findings. | Name, email, phone, URLs, messenger identifiers, hidden metadata and disallowed identifiers are absent. |
| 4 | W08-S04 | Run content fidelity review | review | marketplace_content_privacy_reviewer |  | Fidelity review findings. | Supplier-facing content matches the approved inquiry version and all redactions are non-material to quoteability. |
| 5 | W08-S05 | Return corrections when required | handoff | marketplace_content_privacy_reviewer |  | Correction request with failed checks. | Each correction has one owner and the rejected revision remains immutable. |
| 6 | W08-S06 | Approve immutable supplier-safe package | decision | marketplace_content_privacy_reviewer | compliance_privacy_officer | Approved immutable supplier-safe package. | Reviewer is independent of creators and all mandatory privacy/fidelity checks pass. |
| 7 | W08-S07 | Publish safe-package eligibility | handoff | marketplace_content_privacy_reviewer |  | W12 handoff packet with approved package ID. | Only the approved version is dispatchable and any later change requires a new review. |
| 8 | W08-S08 | Close supplier-safe review | closure | marketplace_content_privacy_reviewer |  | Closed review record. | Final status, reviewer, evidence and exact artifact revisions are recorded. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W08-01-02 | W08-S01 | W08-S02 | rfq_qualification_manager | document_intelligence_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W08-02-03 | W08-S02 | W08-S03 | document_intelligence_manager | marketplace_content_privacy_reviewer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-013 | Supplier-safe approval | Exact brief and file revisions independently pass privacy/fidelity review. | Block dispatch. |
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
| BR-012 | Approved safe package required | No supplier assignment or notification may be created without an approved immutable supplier-safe package. |
| BR-027 | Evidence provenance | Every extracted document fact, normalization, score and review finding must retain source/version provenance. |
| BR-036 | Actual artifact review | Visual/video/file review must inspect the actual final artifact, not only the prompt or brief. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-012 | Redaction/privacy review fails | marketplace_content_privacy_reviewer | compliance_privacy_officer | Reject package; block dispatch; assign correction. |
| EX-013 | Supplier-safe package changes after approval | marketplace_content_privacy_reviewer | risk_governance_manager | Invalidate dispatch eligibility; require new version and review. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
