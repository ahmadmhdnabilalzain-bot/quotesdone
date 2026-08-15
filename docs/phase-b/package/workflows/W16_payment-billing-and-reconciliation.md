# W16 — Payment, billing and reconciliation

## Purpose

Process payment, billing, invoicing and independent reconciliation with idempotent provider-event handling.

## Ownership

- **Accountable workflow owner:** `payments_billing_manager`
- **Contributors:** billing_reconciliation_specialist; financial_controller
- **Independent reviewer/challenge role:** `risk_governance_manager`
- **Criticality:** `critical`
- **Primary business object:** `payment_transaction`
- **State profile:** `financial_transaction_cycle`

## Start and end

- **Start event:** Reveal/payment event
- **Required end state:** Correct payment, invoice and reconciliation state
- **Founder boundary:** No self-reconciliation of own monetary action

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W16-S01 | Create payment request | intake | payments_billing_manager |  | Open payment transaction and provider request. | Amount, currency, customer, selected supplier and idempotency key are correct. |
| 2 | W16-S02 | Present payment to customer | execution | payments_billing_manager |  | Customer payment session. | Session belongs to the correct transaction and uses the approved environment. |
| 3 | W16-S03 | Receive provider event | execution | payments_billing_manager |  | Verified provider event. | Signature, environment, event type and idempotency checks pass. |
| 4 | W16-S04 | Apply payment state transition | decision | payments_billing_manager |  | Updated payment state. | Duplicate/out-of-order events do not corrupt state. |
| 5 | W16-S05 | Create invoice or receipt evidence | execution | billing_reconciliation_specialist |  | Invoice/receipt record. | Document amount, tax treatment and transaction reference reconcile. |
| 6 | W16-S06 | Independently reconcile payment | review | billing_reconciliation_specialist | financial_controller | Reconciliation verdict. | Executor and reconciler are different effective identities and all values match. |
| 7 | W16-S07 | Quarantine discrepancy | handoff | financial_controller |  | Financial exception record. | Unknown or conflicting monetary state is visible and not treated as success. |
| 8 | W16-S08 | Confirm payment result to reveal workflow | handoff | billing_reconciliation_specialist |  | Reconciled payment result. | Only reconciled success authorizes reveal. |
| 9 | W16-S09 | Close payment cycle | closure | payments_billing_manager | risk_governance_manager | Closed payment workflow record. | Final state reconciles to provider, billing and downstream reveal state. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W16-04-05 | W16-S04 | W16-S05 | payments_billing_manager | billing_reconciliation_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W16-06-07 | W16-S06 | W16-S07 | billing_reconciliation_specialist | financial_controller | within_department | Reconciliation or provider-state discrepancy exists. Workflow record; prior accepted outputs; applicable policy. |
| H-W16-07-08 | W16-S07 | W16-S08 | financial_controller | billing_reconciliation_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W16-08-09 | W16-S08 | W16-S09 | billing_reconciliation_specialist | payments_billing_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| BR-020 | Payment before reveal | Supplier contact identity is revealed only after the founder-approved payment state is confirmed and reconciled. |
| BR-021 | Three percent reveal policy | The reveal charge uses the current founder-approved reveal-fee policy; changing the percentage is founder-reserved. |
| BR-022 | No supplier commission | QuotesDone does not charge suppliers a job-success commission unless the founder changes the commercial model. |
| BR-023 | Founding supplier exemption | The founder-approved founding-supplier exemption is permanent for eligible suppliers and cannot be recalculated by mutable counts. |
| BR-024 | Subscription terms founder-reserved | Supplier subscription amount, start date and exemption policy are founder-reserved. |
| BR-031 | Payment execution and reconciliation separation | The effective identity executing a monetary action cannot independently reconcile/approve that same action. |
| BR-032 | Provider event idempotency | External payment/refund events are unique, authenticated and safe under duplicate or out-of-order delivery. |
| BR-033 | Unknown monetary state is visible | Unknown, conflicting or unreconciled monetary states are blocked/quarantined and cannot be treated as success. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-045 | Retry is a new attempt | Retries preserve the failed first attempt and use a new attempt record linked to the original. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-052 | One payment source of truth | Reveal payment, billing and reconciliation use the canonical transaction lifecycle and not parallel monetary states. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-025 | Payment failed or expired | payments_billing_manager | rfq_success_specialist | Do not reveal; record failure; permit approved retry. |
| EX-026 | Payment provider event duplicate/out of order | payments_billing_manager | billing_reconciliation_specialist | Apply idempotency/transition rules; quarantine invalid transition. |
| EX-027 | Payment succeeded but platform update failed | billing_reconciliation_specialist | risk_governance_manager | Open critical reconciliation exception; block duplicate action and downstream inconsistency. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
