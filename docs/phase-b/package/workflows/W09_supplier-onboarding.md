# W09 — Supplier onboarding

## Purpose

Collect and validate the supplier profile, capabilities, documents, terms and verification submission.

## Ownership

- **Accountable workflow owner:** `supplier_onboarding_specialist`
- **Contributors:** communications_manager; document_intelligence_manager
- **Independent reviewer/challenge role:** `supplier_verification_reviewer`
- **Criticality:** `high`
- **Primary business object:** `supplier_account`
- **State profile:** `onboarding_cycle`

## Start and end

- **Start event:** Supplier invitation/registration
- **Required end state:** Complete verification file
- **Founder boundary:** No self-approval

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W09-S01 | Open supplier onboarding case | intake | supplier_onboarding_specialist |  | Open supplier-onboarding case. | Supplier identity and invitation/registration source are explicit. |
| 2 | W09-S02 | Verify supplier contact channels | review | supplier_onboarding_specialist |  | Verified supplier contact or explicit failure. | Verification is bound to the supplier identity and cannot be reused. |
| 3 | W09-S03 | Collect company profile | execution | supplier_onboarding_specialist |  | Validated supplier profile. | Required data is complete and field validation passes. |
| 4 | W09-S04 | Collect supplier documents | execution | supplier_onboarding_specialist |  | Supplier document set. | Required documents are present, owned by the supplier and versioned. |
| 5 | W09-S05 | Map categories and capabilities | analysis | supplier_onboarding_specialist |  | Proposed supplier capability map. | Every capability has evidence and unresolved mappings remain proposed. |
| 6 | W09-S06 | Capture canonical supplier terms acceptance | execution | supplier_onboarding_specialist | compliance_privacy_officer | Immutable supplier acceptance record. | Displayed version, recorded version and document hash match. |
| 7 | W09-S07 | Check onboarding completeness | review | supplier_onboarding_specialist |  | Complete or incomplete onboarding verdict. | No incomplete supplier is submitted as verification-ready. |
| 8 | W09-S08 | Submit independent verification case | handoff | supplier_onboarding_specialist |  | W10 verification handoff. | Reviewer is not the onboarding creator and receives the complete evidence set. |
| 9 | W09-S09 | Close onboarding | closure | supplier_onboarding_specialist |  | Closed onboarding record. | Status and next owner are explicit and no supplier self-approval occurred. |

## Handoffs

No owner-to-owner handoff.

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
| GATE-009 | Exact terms acceptance | Displayed version/hash and acceptance evidence match. | Block account progression. |
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
| BR-023 | Founding supplier exemption | The founder-approved founding-supplier exemption is permanent for eligible suppliers and cannot be recalculated by mutable counts. |
| BR-024 | Subscription terms founder-reserved | Supplier subscription amount, start date and exemption policy are founder-reserved. |
| BR-025 | Exact terms acceptance | Terms acceptance must reference the exact displayed version and hash and remain append-only. |
| BR-026 | No certificate before acceptance | No legal acceptance certificate may be generated before a valid acceptance record exists. |
| BR-030 | Independent supplier verification | Supplier onboarding cannot approve its own supplier; verification is an independent review. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-006 | Terms version mismatch | compliance_privacy_officer | Block activation/verification and correct displayed/recorded version. | Exact displayed and accepted version/hash reconcile. |
| EX-014 | Supplier onboarding incomplete | supplier_onboarding_specialist | supplier_verification_reviewer | Keep pending; request exact missing fields/documents. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
