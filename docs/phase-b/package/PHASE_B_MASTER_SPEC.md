# QuotesDone Phase B — Master Business Workflow Specification

## 1. Scope

Phase A answered **who exists and who owns outcomes**.

Phase B answers **how the company works from start to finish**.

For every company process, Phase B must determine:

1. What event starts the workflow?
2. What canonical business object is created?
3. What states may the workflow enter?
4. What exact steps are required?
5. Who is accountable for every step?
6. Which roles contribute?
7. Which role independently reviews consequential work?
8. What evidence must enter each step?
9. What output must each step produce?
10. What acceptance criteria must pass?
11. What happens when evidence is missing?
12. What happens when a review rejects the work?
13. What happens when a deadline expires?
14. What happens when the workflow is cancelled?
15. What conditions allow completion?
16. What obligations remain after completion?
17. Which decisions require founder approval?
18. Which records must remain immutable?
19. Which handoffs cross departments?
20. Which current code paths are canonical, duplicate, partial, dead or missing?

## 2. Frozen Phase A dependency

The approved organizational baseline is:

- 10 active primary departments;
- 90 canonical accountable roles;
- 86 on-demand category overlays;
- zero Phase A organizational violations.

Phase B must not:

- add, remove or move departments;
- add, remove, merge or move roles;
- change primary managers;
- change reviewer independence;
- change category-overlay authority;
- change founder-reserved decisions.

Any required organization change must become a formal Phase A change request. It cannot be made inside Phase B.

## 3. Canonical workflow catalogue

| workflow_id | workflow_name | accountable_role_id | independent_reviewer_or_challenge_role | start_event | required_end_state | criticality |
| --- | --- | --- | --- | --- | --- | --- |
| W01 | Founder mandate to company objectives | ceo | founder | Founder mandate | Approved company objectives and department mandates | high |
| W02 | Company target miss and corrective management | corporate_performance_director | strategy_director | Material KPI/trajectory miss | Binding-constraint diagnosis and corrective initiative | high |
| W03 | Customer acquisition | chief_revenue_officer | corporate_performance_director | Growth objective/campaign cycle | Qualified customer pipeline and measured acquisition | medium |
| W04 | Customer registration and onboarding | customer_onboarding_specialist | compliance_privacy_officer | New invited/organic customer | Verified, accepted, usable customer account | high |
| W05 | Inquiry intake and qualification | rfq_qualification_manager | inquiry_quality_scoring_analyst | Customer starts inquiry | Structured quote-ready or explicitly blocked inquiry | critical |
| W06 | Category routing | inquiry_router | inquiry_quality_scoring_analyst | New or changed inquiry evidence | Confirmed route set or clarification request | critical |
| W07 | Document/BOQ/drawing processing | document_intelligence_manager | marketplace_content_privacy_reviewer | Document uploaded/received | Structured evidence and unresolved gaps | high |
| W08 | Supplier-safe payload and file approval | marketplace_content_privacy_reviewer | compliance_privacy_officer | Quote-ready inquiry proposed for suppliers | Approved immutable supplier-safe package or rejection | critical |
| W09 | Supplier onboarding | supplier_onboarding_specialist | supplier_verification_reviewer | Supplier invitation/registration | Complete verification file | high |
| W10 | Supplier verification | supplier_verification_reviewer | risk_governance_manager | Complete/reviewable supplier file | Independent approve/refuse/correct decision | critical |
| W11 | Supplier coverage and acquisition gaps | supplier_coverage_liquidity_specialist | marketplace_director | Coverage/liquidity KPI miss | Prioritized supplier acquisition target | medium |
| W12 | Supplier matching and dispatch | supplier_matching_dispatch_operator | marketplace_content_privacy_reviewer | Approved supplier-safe quote-ready inquiry | Idempotent selected assignments and notification records | critical |
| W13 | Supplier notification delivery | lifecycle_channel_operations_specialist | compliance_privacy_officer | Approved queued notification | Delivered/failed/suppressed state | high |
| W14 | Quotation submission and evaluation | quote_evaluation_specialist | rfq_success_specialist | Supplier submits/revises quote | Validated normalized comparison input | critical |
| W15 | Customer comparison and reveal | rfq_success_specialist | compliance_privacy_officer | Sufficient approved quotations | Customer comparison and approved reveal path | critical |
| W16 | Payment, billing and reconciliation | payments_billing_manager | risk_governance_manager | Reveal/payment event | Correct payment, invoice and reconciliation state | critical |
| W17 | Refund, dispute and fraud | trust_safety_manager | risk_governance_manager | Refund/dispute/fraud event | Evidence-based resolution/escalation | critical |
| W18 | Customer support and retention | customer_success_director | corporate_performance_director | Customer issue/churn signal | Resolved issue or measured retention action | medium |
| W19 | Supplier retention | supplier_retention_specialist | supplier_verification_reviewer | Supplier churn/response decline | Measured recovery or exit decision recommendation | medium |
| W20 | Marketing content lifecycle | marketing_director | ai_quality_assurance_reviewer | Campaign/content objective | Reviewed published asset and measured learning | high |
| W21 | Strategic partnership development | strategic_partnerships_government_relations_manager | chief_revenue_officer | Qualified partnership opportunity | Approved partnership proposal/engagement plan | high |
| W22 | Product discovery to delivery | product_manager | qa_release_management_director | Validated product need | Implemented release candidate with acceptance evidence | high |
| W23 | AI/model/prompt change | ai_director | model_evaluation_reviewer | AI capability/change request | Evaluated model/prompt/retrieval change | critical |
| W24 | Release and production approval | qa_release_management_director | risk_governance_manager | Release candidate | Go/no-go and rollback readiness | critical |
| W25 | Data reporting and forecasting | data_intelligence_director | corporate_performance_director | Reporting/forecast requirement | Decision-grade report/forecast | high |
| W26 | Knowledge creation and validation | knowledge_director | knowledge_validator | Knowledge gap/change | Validated versioned knowledge or rejection | high |
| W27 | Financial planning and accounting close | cfo | risk_governance_manager | Planning/close cycle | Budget/forecast/close with controls and exceptions | critical |
| W28 | Legal, compliance and risk review | general_counsel | ceo | Legal/compliance/risk event | Position, verdict, controls and escalation | critical |
| W29 | Security incident and reliability recovery | it_operations_site_reliability_engineer | risk_governance_manager | Incident/security signal | Contained incident, restored service and evidence | critical |
| W30 | Agent performance, remediation and organization design | agent_workforce_capability_director | ai_quality_assurance_reviewer | Capability/KPI failure | Remediated/restricted/reassigned capability and verified result | high |

## 4. Workflow architecture standard

Every workflow must contain:

- stable `workflow_id`;
- workflow name and purpose;
- one accountable workflow owner;
- canonical primary business object;
- start event;
- required end state;
- allowed states;
- allowed state transitions;
- ordered required and conditional steps;
- one accountable owner per step;
- contributor list;
- independent reviewer/challenge role where required;
- required inputs;
- required action;
- required output;
- acceptance criteria;
- closure criteria;
- blocker/failure behavior;
- idempotency scope;
- handoff contract;
- exception/escalation path;
- internal SLA policy;
- founder boundary;
- cancellation, expiry, retry and supersession rules.

## 5. Workflow states

| state | definition | terminal |
| --- | --- | --- |
| draft | Record exists but work has not been accepted into active processing. | False |
| queued | Work is accepted and waiting for its accountable owner. | False |
| active | The accountable owner is executing the current required step. | False |
| waiting_input | Required evidence or response is awaited from an identified party. | False |
| waiting_handoff | A complete handoff packet is awaiting receiving-owner acceptance. | False |
| waiting_review | An independent review or approval is pending. | False |
| blocked | A named blocker prevents progression and has an accountable resolution owner. | False |
| approved | The required decision/review passed but final closure actions remain. | False |
| rejected | The required decision/review failed; correction, appeal or closure must follow. | False |
| failed | Execution ended unsuccessfully and requires retry, escalation or closure. | False |
| expired | A configured time window ended without the required action. | False |
| cancelled | The workflow was intentionally stopped with authority and reason. | True |
| completed | The required end state and closure criteria are satisfied. | True |
| superseded | A newer approved workflow/version replaces this one while preserving history. | True |

Only declared transitions in `PHASE_B_WORKFLOW_TRANSITIONS.csv` are permitted.

A workflow cannot be treated as complete merely because one function returned successfully. It is complete only when:

- every mandatory step is completed or validly skipped;
- all reviews and gates pass;
- all handoffs are accepted;
- no unresolved blocker or obligation remains;
- the required end state exists;
- closure evidence is recorded.

## 6. Step states

| state | definition | terminal |
| --- | --- | --- |
| not_ready | Prerequisites are not satisfied. | False |
| ready | Prerequisites are satisfied and the step may start. | False |
| active | The accountable owner is executing the step. | False |
| waiting_input | The step awaits identified evidence or response. | False |
| waiting_review | The step awaits an independent review. | False |
| blocked | A named blocker prevents completion. | False |
| completed | The step output passed acceptance criteria. | True |
| failed | The step failed execution or acceptance. | True |
| cancelled | The step was intentionally cancelled. | True |
| skipped | The step is conditionally not applicable with an approved reason. | True |
| superseded | A newer step/output version replaces this one. | True |

Retries create new attempts. A failed first attempt must remain visible.

## 7. Canonical ownership rule

Every workflow and every required step has exactly one accountable owner.

Contributors may assist. Reviewers may approve or reject. Managers may escalate. None of these creates a second accountable owner.

Dynamic participants such as a relevant category overlay are allowed only where the package explicitly declares them.

## 8. Handoff rule

A handoff is complete only when it contains:

- sending workflow and step;
- sender;
- receiving role;
- source business object/version;
- accepted output;
- evidence;
- unresolved blockers;
- requested next action;
- acceptance criteria;
- deadline/SLA;
- rejection reason when refused;
- return owner;
- final acceptance or closure state.

Sending a message is not proof that a handoff was accepted.

## 9. Review rule

Independent review requires different **effective canonical identities**, not merely different aliases.

A review record must identify:

- artifact or decision reviewed;
- exact version;
- creator;
- reviewer;
- evidence inspected;
- checks performed;
- decision;
- reasons;
- correction requirements;
- time;
- supersession/re-review relationship.

## 10. Business-record rule

Business objects follow the mutation policies in `PHASE_B_BUSINESS_OBJECT_REGISTRY.csv`.

Examples:

- terms acceptances are append-only;
- supplier-safe packages are immutable after approval;
- supplier quotation revisions remain supplier-authored and immutable;
- provider events are unique and append-only;
- retries are separate attempts;
- cancellations preserve history;
- completed workflow versions may be superseded but not silently rewritten.

## 11. Business-rule hierarchy

The canonical business rules are in `PHASE_B_BUSINESS_RULE_REGISTRY.csv`.

Precedence:

1. founder-reserved decision;
2. law/regulation and approved company policy;
3. hard privacy, financial, security and authority gate;
4. canonical workflow rule;
5. workflow-specific decision;
6. operational preference.

Lower-precedence behavior cannot silently override a higher-precedence rule.

## 12. Category overlays

All 86 overlays remain on-demand and governed by the Phase A registry.

They may contribute to:

- W05 inquiry qualification;
- W06 category routing;
- W07 document interpretation;
- W10 supplier capability verification;
- W14 quotation technical evaluation.

They cannot:

- dispatch;
- approve suppliers;
- reveal customer identity;
- make payment/refund decisions;
- change commercial policy;
- issue final legal/privacy verdicts;
- issue release approval.

## 13. Existing-code reconciliation

Phase B must inventory every current workflow representation, including:

- frontend pages/actions;
- API clients;
- Edge Functions;
- database functions;
- triggers;
- cron jobs;
- event subscriptions;
- workflow tables;
- state columns;
- queues;
- notification paths;
- direct third-party calls.

Each current path must be classified:

- `CANONICAL_KEEP`
- `CANONICAL_BETTER_KEEP`
- `CANONICAL_PARTIAL`
- `DUPLICATE_PATH`
- `CONFLICTING_PATH`
- `DEAD_CODE`
- `UNOWNED`
- `OUT_OF_SCOPE`
- `PHASE_C_WIRING_GAP`

Phase B may establish the canonical workflow registry and structural constraints.

Phase B must not connect tools/models or activate automation. Runtime rewiring belongs to Phase C.

## 14. Internal SLA policy

The SLA values in `PHASE_B_SLA_POLICY.csv` are internal operational targets, not public promises.

They may later be adjusted by authorized management without reopening Phase A or the structural workflow definition, provided:

- the accountable owner remains unchanged;
- no founder-reserved promise is created;
- privacy/safety/legal gates are not weakened;
- deadline and escalation behavior remain explicit.

## 15. Phase B definition of done

Phase B is complete only when:

- all package counts reconcile;
- every workflow and step exists exactly once;
- every step has one active accountable owner;
- all 90 roles are represented in at least one workflow, review or contribution;
- all 10 departments are represented;
- all 86 overlays have the approved workflow scope;
- every workflow has start, end, states, transitions, gates, exceptions and closure;
- every owner-to-owner transition has a handoff contract;
- no workflow step violates founder boundaries;
- no creator/reviewer collision exists;
- all current code paths are classified;
- duplicate/conflicting paths are identified for Phase C;
- Phase A remains unchanged;
- zero OpenRouter or paid inference calls occur;
- no new automation is activated;
- the structural package is committed, transactionally rehearsed, deployed and reverified in production.

## 16. Later phases

- **Phase C:** technical connection map and runtime wiring.
- **Phase D:** deterministic code correctness and security.
- **Phase E:** synthetic company simulation using mocks and demo data.
- **Phase F:** controlled, budget-approved live-model tests.
- **Phase G:** independent certification.
