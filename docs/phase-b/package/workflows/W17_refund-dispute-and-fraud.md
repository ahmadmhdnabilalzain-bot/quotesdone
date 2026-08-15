# W17 — Refund, dispute and fraud

## Purpose

Resolve refund, dispute and fraud cases through evidence, authority, execution, reconciliation and appeal paths.

## Ownership

- **Accountable workflow owner:** `trust_safety_manager`
- **Contributors:** payments_billing_manager; fraud_reviewer; general_counsel; customer_support_specialist
- **Independent reviewer/challenge role:** `risk_governance_manager`
- **Criticality:** `critical`
- **Primary business object:** `refund_dispute_case`
- **State profile:** `case_workflow`

## Start and end

- **Start event:** Refund/dispute/fraud event
- **Required end state:** Evidence-based resolution/escalation
- **Founder boundary:** Money movement and legal commitments gated

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W17-S01 | Open refund/dispute/fraud case | intake | trust_safety_manager |  | Open classified case. | Case type, parties, transaction and source evidence are identified. |
| 2 | W17-S02 | Triage jurisdiction and authority | analysis | trust_safety_manager |  | Case handling plan. | Money, legal and enforcement decisions are routed to authorized roles. |
| 3 | W17-S03 | Collect transaction and communication evidence | execution | customer_support_specialist |  | Evidence packet. | Evidence is complete enough for review or missing items are explicit. |
| 4 | W17-S04 | Conduct fraud review when triggered | review | fraud_reviewer |  | Fraud verdict and recommended controls. | Verdict states evidence, uncertainty and block/allow recommendation. |
| 5 | W17-S05 | Conduct legal/compliance review when triggered | review | general_counsel |  | Legal/compliance position. | Position distinguishes legal fact, interpretation, uncertainty and founder-reserved commitment. |
| 6 | W17-S06 | Decide case outcome | decision | trust_safety_manager | risk_governance_manager | Case decision with required actions. | Decision has one accountable owner and no reviewer executes the same monetary action. |
| 7 | W17-S07 | Execute approved financial action | execution | payments_billing_manager | billing_reconciliation_specialist | Financial execution result. | No action occurs without an approved case and no duplicate refund is possible. |
| 8 | W17-S08 | Apply trust/supplier/customer enforcement | execution | trust_safety_manager |  | Enforcement state changes. | Enforcement matches the case decision and supports appeal where required. |
| 9 | W17-S09 | Reconcile and notify | handoff | billing_reconciliation_specialist |  | Reconciliation and notification records. | Parties receive the correct outcome and no private internal evidence is leaked. |
| 10 | W17-S10 | Handle appeal or escalation | review | risk_governance_manager |  | Appeal/escalation result. | Reviewer is independent of the original execution and any founder gate is explicit. |
| 11 | W17-S11 | Close case | closure | trust_safety_manager |  | Closed refund/dispute/fraud case. | All required actions are complete or explicitly handed to an accountable open workflow. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W17-02-03 | W17-S02 | W17-S03 | trust_safety_manager | customer_support_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-03-04 | W17-S03 | W17-S04 | customer_support_specialist | fraud_reviewer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-04-05 | W17-S04 | W17-S05 | fraud_reviewer | general_counsel | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-05-06 | W17-S05 | W17-S06 | general_counsel | trust_safety_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-06-07 | W17-S06 | W17-S07 | trust_safety_manager | payments_billing_manager | cross_department | Approved refund/financial action exists. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-07-08 | W17-S07 | W17-S08 | payments_billing_manager | trust_safety_manager | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-08-09 | W17-S08 | W17-S09 | trust_safety_manager | billing_reconciliation_specialist | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-09-10 | W17-S09 | W17-S10 | billing_reconciliation_specialist | risk_governance_manager | cross_department | Appeal, unresolved material risk or founder-reserved issue exists. Workflow record; prior accepted outputs; applicable policy. |
| H-W17-10-11 | W17-S10 | W17-S11 | risk_governance_manager | trust_safety_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-020 | Refund authority and idempotency | Approved case decision and unique financial action key exist. | Block/return existing. |
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
| BR-022 | No supplier commission | QuotesDone does not charge suppliers a job-success commission unless the founder changes the commercial model. |
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
| EX-016 | Supplier fraud risk | fraud_reviewer | risk_governance_manager | Block relevant account/transaction pending independent decision. |
| EX-028 | Refund approved but provider fails | payments_billing_manager | trust_safety_manager | Do not mark refunded; preserve request and provider error. |
| EX-029 | Refund money moved but ledger failed | billing_reconciliation_specialist | cfo | Open critical financial exception; prevent duplicate refund; correct records under control. |
| EX-030 | Customer dispute lacks evidence | trust_safety_manager | customer_support_specialist | Request missing evidence and keep case pending; no unsupported financial action. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
