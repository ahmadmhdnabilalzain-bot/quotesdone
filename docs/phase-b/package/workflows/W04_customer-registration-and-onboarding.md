# W04 — Customer registration and onboarding

## Purpose

Create a verified customer account with valid acceptance evidence and guide the customer to a usable first inquiry.

## Ownership

- **Accountable workflow owner:** `customer_onboarding_specialist`
- **Contributors:** customer_support_specialist; communications_manager
- **Independent reviewer/challenge role:** `compliance_privacy_officer`
- **Criticality:** `high`
- **Primary business object:** `customer_account`
- **State profile:** `case_workflow`

## Start and end

- **Start event:** New invited/organic customer
- **Required end state:** Verified, accepted, usable customer account
- **Founder boundary:** Terms/policy remain founder-approved

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W04-S01 | Start customer registration | intake | customer_onboarding_specialist |  | Open customer-registration case. | Email/identity input is normalized and duplicate-account checks are initiated. |
| 2 | W04-S02 | Verify customer identity channel | review | customer_onboarding_specialist |  | Verified contact channel or explicit failure. | Verification belongs to the registering identity and cannot be replayed. |
| 3 | W04-S03 | Capture customer profile | execution | customer_onboarding_specialist |  | Validated customer profile. | Required fields are complete, unique constraints pass and no duplicate customer is created. |
| 4 | W04-S04 | Capture canonical terms acceptance | execution | customer_onboarding_specialist | compliance_privacy_officer | Acceptance record linked to exact document version and identity. | Displayed and accepted versions match; acceptance is not fabricated or rewritten. |
| 5 | W04-S05 | Activate usable customer account | decision | customer_onboarding_specialist |  | Active customer account. | All mandatory gates pass and no unresolved duplicate or compliance issue exists. |
| 6 | W04-S06 | Deliver first-inquiry guidance | handoff | customer_onboarding_specialist |  | Onboarding completion and inquiry-start handoff. | Customer can access the inquiry workflow and understands required next step. |
| 7 | W04-S07 | Close onboarding | closure | customer_onboarding_specialist | customer_success_director | Closed onboarding record. | Account is usable, evidence is complete and no open mandatory onboarding step remains. |

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
| BR-025 | Exact terms acceptance | Terms acceptance must reference the exact displayed version and hash and remain append-only. |
| BR-026 | No certificate before acceptance | No legal acceptance certificate may be generated before a valid acceptance record exists. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-005 | Customer duplicate identity/account | customer_onboarding_specialist | compliance_privacy_officer | Block duplicate creation; reconcile identity through approved recovery. |
| EX-006 | Terms version mismatch | compliance_privacy_officer | Block activation/verification and correct displayed/recorded version. | Exact displayed and accepted version/hash reconcile. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
