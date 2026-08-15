# W15 — Customer comparison and reveal

## Purpose

Publish approved comparable quotations, capture customer selection and open the founder-approved reveal path.

## Ownership

- **Accountable workflow owner:** `rfq_success_specialist`
- **Contributors:** quote_evaluation_specialist; customer_success_director; payments_billing_manager
- **Independent reviewer/challenge role:** `compliance_privacy_officer`
- **Criticality:** `critical`
- **Primary business object:** `quotation_comparison`
- **State profile:** `customer_decision_cycle`

## Start and end

- **Start event:** Sufficient approved quotations
- **Required end state:** Customer comparison and approved reveal path
- **Founder boundary:** Pricing/reveal policy founder-reserved

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W15-S01 | Check comparison readiness | review | rfq_success_specialist |  | Comparison readiness decision. | Only approved, normalized quote versions are included. |
| 2 | W15-S02 | Construct customer comparison | execution | quote_evaluation_specialist |  | Versioned customer comparison. | Price, VAT, timeline, validity, exclusions and technical differences are accurate and traceable. |
| 3 | W15-S03 | Review customer visibility and privacy | review | compliance_privacy_officer |  | Comparison publication approval. | Supplier/customer identities and contact details follow the founder-approved reveal policy. |
| 4 | W15-S04 | Publish comparison to customer | execution | rfq_success_specialist |  | Customer-visible comparison. | Only the owning customer can access it and notification is linked to the published version. |
| 5 | W15-S05 | Capture customer selection | decision | rfq_success_specialist |  | Customer selection record. | Selection references an available published quote and is not silently changed. |
| 6 | W15-S06 | Calculate founder-approved reveal charge | execution | payments_billing_manager |  | Reveal charge request. | Rate, base, currency and rounding follow the approved policy. |
| 7 | W15-S07 | Complete reveal payment handoff | handoff | payments_billing_manager |  | Payment workflow reference. | No contact reveal occurs merely because checkout was opened. |
| 8 | W15-S08 | Reveal permitted contact relationship | execution | rfq_success_specialist |  | Reveal record and permitted messaging relationship. | Payment is confirmed/reconciled and the exact selected supplier is revealed. |
| 9 | W15-S09 | Close comparison and reveal cycle | closure | rfq_success_specialist |  | Closed comparison/reveal record. | Final state and any post-reveal owner are explicit. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W15-01-02 | W15-S01 | W15-S02 | rfq_success_specialist | quote_evaluation_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W15-02-03 | W15-S02 | W15-S03 | quote_evaluation_specialist | compliance_privacy_officer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W15-03-04 | W15-S03 | W15-S04 | compliance_privacy_officer | rfq_success_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W15-05-06 | W15-S05 | W15-S06 | rfq_success_specialist | payments_billing_manager | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W15-07-08 | W15-S07 | W15-S08 | payments_billing_manager | rfq_success_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-018 | Comparison publication | Comparison is approved, customer-owned and visibility/privacy policy passes. | Block publication. |
| GATE-019 | Payment reconciliation | Provider, transaction, invoice and reconciliation agree on success. | Keep reveal blocked/open exception. |
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
| BR-011 | No customer identity before reveal | Supplier-facing payloads, files, portal views and notifications may not contain customer identity before the approved reveal state. |
| BR-018 | Supplier quote remains supplier-authored | The platform may normalize for comparison but cannot alter the supplier's original quotation revision. |
| BR-019 | Published quote visibility only | Customers may see only their own approved/published quotation comparison versions. |
| BR-020 | Payment before reveal | Supplier contact identity is revealed only after the founder-approved payment state is confirmed and reconciled. |
| BR-021 | Three percent reveal policy | The reveal charge uses the current founder-approved reveal-fee policy; changing the percentage is founder-reserved. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-050 | One comparison source of truth | Customer comparison uses the canonical normalized quote records and published version, not multiple conflicting comparison implementations. |
| BR-052 | One payment source of truth | Reveal payment, billing and reconciliation use the canonical transaction lifecycle and not parallel monetary states. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-024 | Insufficient valid quotes | rfq_success_specialist | marketplace_director | Explain state; extend window, publish fewer by policy, or reopen supplier coverage/dispatch. |
| EX-025 | Payment failed or expired | payments_billing_manager | rfq_success_specialist | Do not reveal; record failure; permit approved retry. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
