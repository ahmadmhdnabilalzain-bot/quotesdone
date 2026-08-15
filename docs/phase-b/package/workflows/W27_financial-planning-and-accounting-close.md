# W27 — Financial planning and accounting close

## Purpose

Complete planning, accounting close, reconciliation, tax coordination, variance analysis and controlled reporting.

## Ownership

- **Accountable workflow owner:** `cfo`
- **Contributors:** financial_controller; fp_a_analyst; accounts_payable_specialist; collections_revenue_assurance_specialist
- **Independent reviewer/challenge role:** `risk_governance_manager`
- **Criticality:** `critical`
- **Primary business object:** `financial_close`
- **State profile:** `close_cycle`

## Start and end

- **Start event:** Planning/close cycle
- **Required end state:** Budget/forecast/close with controls and exceptions
- **Founder boundary:** Founder approves above limits/equity/funding

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W27-S01 | Open planning/close cycle | intake | cfo |  | Open financial planning/close cycle. | Period, entities, currency, policies and accountable roles are explicit. |
| 2 | W27-S02 | Collect and classify financial evidence | execution | financial_controller |  | Complete financial evidence set. | Sources reconcile to controlled systems or discrepancies are listed. |
| 3 | W27-S03 | Reconcile cash, payments and billing | review | billing_reconciliation_specialist |  | Reconciliation result and exception list. | Unknown amounts and mismatches remain visible and owned. |
| 4 | W27-S04 | Validate payables and accruals | review | accounts_payable_specialist |  | Approved payable/accrual schedule. | No payment is scheduled without evidence and authority. |
| 5 | W27-S05 | Validate revenue and collections | review | collections_revenue_assurance_specialist |  | Revenue-assurance schedule. | Revenue and collections states reconcile to platform events. |
| 6 | W27-S06 | Apply accounting close and controls | decision | financial_controller |  | Closed ledger period and control exception register. | Entries are balanced, supported and independently reviewable. |
| 7 | W27-S07 | Coordinate UAE tax compliance | review | financial_controller |  | Tax coordination checklist and escalation record. | Complex, disputed, material or current-law interpretation is escalated externally. |
| 8 | W27-S08 | Prepare forecast and variance | analysis | fp_a_analyst |  | Financial forecast and variance report. | Assumptions and confidence are explicit and reconcile to the closed period. |
| 9 | W27-S09 | Review and approve financial report | decision | cfo | risk_governance_manager | Approved financial report and actions. | Material exceptions and founder-reserved decisions are escalated. |
| 10 | W27-S10 | Close financial cycle | closure | cfo |  | Closed financial planning/close record. | No unreconciled critical issue is silently closed. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W27-01-02 | W27-S01 | W27-S02 | cfo | financial_controller | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W27-02-03 | W27-S02 | W27-S03 | financial_controller | billing_reconciliation_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W27-03-04 | W27-S03 | W27-S04 | billing_reconciliation_specialist | accounts_payable_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W27-04-05 | W27-S04 | W27-S05 | accounts_payable_specialist | collections_revenue_assurance_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W27-05-06 | W27-S05 | W27-S06 | collections_revenue_assurance_specialist | financial_controller | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W27-07-08 | W27-S07 | W27-S08 | financial_controller | fp_a_analyst | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W27-08-09 | W27-S08 | W27-S09 | fp_a_analyst | cfo | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-027 | Financial close integrity | Critical reconciliations, control exceptions and tax coordination pass. | Block close. |
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
| BR-022 | No supplier commission | QuotesDone does not charge suppliers a job-success commission unless the founder changes the commercial model. |
| BR-023 | Founding supplier exemption | The founder-approved founding-supplier exemption is permanent for eligible suppliers and cannot be recalculated by mutable counts. |
| BR-024 | Subscription terms founder-reserved | Supplier subscription amount, start date and exemption policy are founder-reserved. |
| BR-031 | Payment execution and reconciliation separation | The effective identity executing a monetary action cannot independently reconcile/approve that same action. |
| BR-033 | Unknown monetary state is visible | Unknown, conflicting or unreconciled monetary states are blocked/quarantined and cannot be treated as success. |
| BR-040 | Metric definition consistency | Reports and forecasts use canonical metric definitions and source lineage. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-052 | One payment source of truth | Reveal payment, billing and reconciliation use the canonical transaction lifecycle and not parallel monetary states. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-043 | Financial close contains unreconciled critical balance | financial_controller | cfo | Block close; create exception owner and due date. |
| EX-044 | Tax matter requires current professional interpretation | financial_controller | general_counsel | Escalate to current authoritative source/external UAE tax professional. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
