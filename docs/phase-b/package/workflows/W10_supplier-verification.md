# W10 — Supplier verification

## Purpose

Issue an independent, evidence-based supplier approval, correction, refusal or suspension decision.

## Ownership

- **Accountable workflow owner:** `supplier_verification_reviewer`
- **Contributors:** supplier_onboarding_specialist; fraud_reviewer; compliance_privacy_officer
- **Independent reviewer/challenge role:** `risk_governance_manager`
- **Criticality:** `critical`
- **Primary business object:** `supplier_verification_case`
- **State profile:** `independent_review_cycle`

## Start and end

- **Start event:** Complete/reviewable supplier file
- **Required end state:** Independent approve/refuse/correct decision
- **Founder boundary:** No approval without evidence

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W10-S01 | Accept verification case | intake | supplier_verification_reviewer |  | Open verification case. | Reviewer is independent and all required evidence is versioned. |
| 2 | W10-S02 | Verify legal identity and licence | review | supplier_verification_reviewer |  | Licence/identity verification findings. | Every finding cites the document/version used. |
| 3 | W10-S03 | Verify capability claims | review | supplier_verification_reviewer |  | Capability verification findings. | Approved capabilities are evidence-supported and unsupported claims are excluded. |
| 4 | W10-S04 | Perform fraud/risk challenge where triggered | handoff | fraud_reviewer |  | Fraud/risk verdict. | Verdict is evidence-based and any block reason is explicit. |
| 5 | W10-S05 | Issue verification decision | decision | supplier_verification_reviewer | risk_governance_manager | Independent supplier verification decision. | Decision follows evidence, policy and reviewer independence; no onboarding self-approval. |
| 6 | W10-S06 | Open correction window if applicable | execution | supplier_verification_reviewer |  | Supplier correction case. | Correction requirements and deadline are visible and actionable. |
| 7 | W10-S07 | Notify supplier and internal owners | handoff | supplier_onboarding_specialist |  | Notification delivery record. | Supplier receives the correct decision without internal/private evidence leakage. |
| 8 | W10-S08 | Close verification case | closure | supplier_verification_reviewer |  | Closed or active correction verification record. | Supplier operational status is consistent with the final verification state. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W10-03-04 | W10-S03 | W10-S04 | supplier_verification_reviewer | fraud_reviewer | cross_department | Fraud or material risk trigger exists. Workflow record; prior accepted outputs; applicable policy. |
| H-W10-04-05 | W10-S04 | W10-S05 | fraud_reviewer | supplier_verification_reviewer | cross_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W10-06-07 | W10-S06 | W10-S07 | supplier_verification_reviewer | supplier_onboarding_specialist | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W10-07-08 | W10-S07 | W10-S08 | supplier_onboarding_specialist | supplier_verification_reviewer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-014 | Supplier verification | Supplier is currently approved and capability evidence supports scope. | Exclude/block. |
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
| BR-015 | Supplier approval required | Only currently approved, eligible suppliers may receive a dispatch assignment. |
| BR-023 | Founding supplier exemption | The founder-approved founding-supplier exemption is permanent for eligible suppliers and cannot be recalculated by mutable counts. |
| BR-027 | Evidence provenance | Every extracted document fact, normalization, score and review finding must retain source/version provenance. |
| BR-029 | Document conflict preserved | Conflicting evidence is preserved and cannot be silently overwritten by lower-authority evidence. |
| BR-030 | Independent supplier verification | Supplier onboarding cannot approve its own supplier; verification is an independent review. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-015 | Supplier licence invalid/expired | supplier_verification_reviewer | risk_governance_manager | Refuse, suspend or open correction window according to policy. |
| EX-016 | Supplier fraud risk | fraud_reviewer | risk_governance_manager | Block relevant account/transaction pending independent decision. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
