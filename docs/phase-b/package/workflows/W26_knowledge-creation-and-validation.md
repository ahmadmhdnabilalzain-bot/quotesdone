# W26 — Knowledge creation and validation

## Purpose

Create, independently validate, version, publish and retire company or category knowledge.

## Ownership

- **Accountable workflow owner:** `knowledge_director`
- **Contributors:** knowledge_engineer; category_knowledge_curator; taxonomy_governance_manager
- **Independent reviewer/challenge role:** `knowledge_validator`
- **Criticality:** `high`
- **Primary business object:** `knowledge_change`
- **State profile:** `knowledge_cycle`

## Start and end

- **Start event:** Knowledge gap/change
- **Required end state:** Validated versioned knowledge or rejection
- **Founder boundary:** Author cannot self-validate

## Ordered steps

| step_no | step_id | step_name | step_type | accountable_role_id | independent_reviewer_role_id | required_output | acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | W26-S01 | Open knowledge gap or change | intake | knowledge_director |  | Open knowledge-change case. | Affected roles, categories, workflows and risk are identified. |
| 2 | W26-S02 | Define source and evidence plan | decision | knowledge_director |  | Knowledge source plan. | Source hierarchy and prohibited unsupported inference are explicit. |
| 3 | W26-S03 | Collect and register sources | execution | knowledge_engineer |  | Source registry entries. | Sources are traceable and confidential/unsupported material is excluded. |
| 4 | W26-S04 | Create or update knowledge | execution | knowledge_engineer |  | Draft versioned knowledge records. | Records preserve lineage, scope, effective date and stable identity. |
| 5 | W26-S05 | Review taxonomy and category fit | review | taxonomy_governance_manager |  | Taxonomy/category review findings. | No record is mapped to an invalid or ambiguous taxonomy identity. |
| 6 | W26-S06 | Independently validate knowledge | review | knowledge_validator |  | Approve, reject or correction decision. | Validator did not author the record and rejected content cannot enter approved retrieval. |
| 7 | W26-S07 | Publish approved knowledge version | execution | knowledge_director |  | Published knowledge version. | Only independently approved records become runtime-eligible. |
| 8 | W26-S08 | Set review and expiry conditions | decision | knowledge_director |  | Knowledge maintenance schedule. | Time-sensitive knowledge cannot remain indefinitely current. |
| 9 | W26-S09 | Close knowledge-change cycle | closure | knowledge_director |  | Closed knowledge-change record. | All draft records have a final governed state. |

## Handoffs

| handoff_id | from_step_id | to_step_id | sending_role_id | receiving_role_id | handoff_type | receiving_acceptance_criteria |
| --- | --- | --- | --- | --- | --- | --- |
| H-W26-02-03 | W26-S02 | W26-S03 | knowledge_director | knowledge_engineer | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W26-04-05 | W26-S04 | W26-S05 | knowledge_engineer | taxonomy_governance_manager | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W26-05-06 | W26-S05 | W26-S06 | taxonomy_governance_manager | knowledge_validator | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |
| H-W26-06-07 | W26-S06 | W26-S07 | knowledge_validator | knowledge_director | within_department | Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy. |

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
| GATE-026 | Knowledge validation | Independent source/freshness/contradiction review passes. | Reject/keep draft. |
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
| BR-027 | Evidence provenance | Every extracted document fact, normalization, score and review finding must retain source/version provenance. |
| BR-043 | No silent exception | Policy exceptions require an explicit authorized decision and cannot bypass privacy, safety or founder boundaries. |
| BR-044 | Timers have escalation | Every externally waiting or time-bound step has a deadline, reminder/escalation owner and terminal state. |
| BR-046 | Cancelled is not deleted | Cancellation preserves the business record, reason, authority and prior evidence. |
| BR-053 | No workflow activation in Phase B | Phase B may define and reconcile workflows but cannot activate new automation, provider calls or autonomous execution. |
| BR-054 | Zero paid inference in Phase B | Phase B uses no OpenRouter or paid model calls. |

## Known exception patterns

| exception_id | exception_name | detection_owner_role_id | escalation_owner_role_id | required_response |
| --- | --- | --- | --- | --- |
| EX-042 | Knowledge source stale/contradictory | knowledge_validator | knowledge_director | Reject or expire record; open refresh/contradiction work. |
| EX-050 | Workflow owner inactive/unknown | chief_of_staff | coo | Block assignment; resolve to active canonical owner or raise structure defect. |

## Phase boundary

This document defines business-process structure only. Runtime tools, models, traces, UI/API connections and execution behavior must be implemented and proven in later phases.
