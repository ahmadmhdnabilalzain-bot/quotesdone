# W12 — Supplier matching and dispatch

## Purpose

Select eligible suppliers and create idempotent assignments and exactly one notification record per selected supplier.

## Ownership

- **Accountable workflow owner:** `supplier_matching_dispatch_operator`
- **Contributors:** marketplace_director; inquiry_router; category overlay; lifecycle_channel_operations_specialist
- **Independent reviewer/challenge role:** `marketplace_content_privacy_reviewer`
- **Criticality:** `critical`
- **Primary business object:** `dispatch_batch`
- **State profile:** `transaction_cycle`

## Start and end

- **Start event:** Approved supplier-safe quote-ready inquiry
- **Required end state:** Idempotent selected assignments and notification records
- **Founder boundary:** No gate bypass or unapproved supplier

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W12-S01 | Accept dispatch-ready package | intake | supplier_matching_dispatch_operator |  | Open dispatch batch. | Inquiry, route, safe package and approval versions are exact and current. |
| 2 | W12-S02 | Build eligible supplier pool | analysis | supplier_matching_dispatch_operator |  | Eligible supplier pool with exclusion reasons. | Every included supplier passes mandatory gates; every exclusion is reasoned. |
| 3 | W12-S03 | Apply fairness and capacity policy | analysis | supplier_matching_dispatch_operator |  | Proposed selected supplier set. | Selection follows approved policy and does not silently override a mandatory gate. |
| 4 | W12-S04 | Review policy exception if needed | review | marketplace_director |  | Dispatch exception decision. | Exception does not bypass privacy, approval, completeness or founder-reserved policy. |
| 5 | W12-S05 | Revalidate immediately before assignment | review | supplier_matching_dispatch_operator |  | Final validated supplier set. | No supplier whose status changed after selection is assigned. |
| 6 | W12-S06 | Create idempotent supplier assignments | execution | supplier_matching_dispatch_operator |  | Supplier assignment records. | Duplicate execution creates no duplicate assignment and refused inserts are not counted successful. |
| 7 | W12-S07 | Create exactly one notification per assignment | handoff | supplier_matching_dispatch_operator |  | Notification queue records. | Notification count equals successful assignment count and excludes refused suppliers. |
| 8 | W12-S08 | Record selection and exclusion evidence | execution | supplier_matching_dispatch_operator |  | Dispatch audit record. | Every considered supplier has a visible selected/excluded result. |
| 9 | W12-S09 | Close dispatch batch | closure | supplier_matching_dispatch_operator | marketplace_content_privacy_reviewer | Closed dispatch batch and next-state handoff. | Counts reconcile and terminal failures have an accountable escalation owner. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W12-03-04 | W12-S03 | W12-S04 | supplier_matching_dispatch_operator | marketplace_director | within_department | A documented exception to ordinary dispatch policy is requested. Workflow record; prior accepted outputs; applicable policy. |
| H-W12-04-05 | W12-S04 | W12-S05 | marketplace_director | supplier_matching_dispatch_operator | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-014 | Supplier verification | Supplier is currently approved and capability evidence supports scope. | Exclude/block. |
| GATE-015 | Dispatch idempotency | No existing assignment for same supplier, inquiry version and dispatch scope. | Return existing/refuse duplicate. |
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
| BR-013 | Quote-ready inquiry required | No inquiry may be dispatched while mandatory qualification, route, document or readiness blockers remain. |
| BR-014 | Confirmed route required for dispatch | Proposed, ambiguous, rejected or excluded routes cannot independently authorize supplier dispatch. |
| BR-015 | Supplier approval required | Only currently approved, eligible suppliers may receive a dispatch assignment. |
| BR-016 | Idempotent assignment | One supplier may receive at most one assignment for the same inquiry version and dispatch scope. |
| BR-017 | Notification count equals successful assignments | Refused or failed assignments are not counted as contacted and do not create success notifications. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-048 | Category overlays cannot dispatch | Category overlays provide qualification and comparison expertise but cannot approve suppliers, dispatch, reveal identity or change policy. |
| BR-051 | One dispatch source of truth | All supplier assignments and notifications originate from the canonical W12 dispatch batch. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-013 | Supplier-safe package changes after approval | marketplace_content_privacy_reviewer | risk_governance_manager | Invalidate dispatch eligibility; require new version and review. |
| EX-017 | No eligible suppliers | supplier_matching_dispatch_operator | marketplace_director | Close dispatch as no-eligible-suppliers; open coverage gap and inform customer owner. |
| EX-018 | Supplier status changes during dispatch | supplier_matching_dispatch_operator | supplier_verification_reviewer | Exclude supplier at final revalidation; do not count as assigned/notified. |
| EX-019 | Duplicate dispatch request | supplier_matching_dispatch_operator | marketplace_director | Return existing batch/assignment result; create no duplicates. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
