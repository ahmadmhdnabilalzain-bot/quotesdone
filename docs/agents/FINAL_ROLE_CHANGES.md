# Role changes — what moved, and the measurement that justified each one

Written 15 August 2026. Ten departments and ~90 canonical roles are unchanged in count. Nothing was
renamed to make a name match an instruction; each change below closes a gap that was measured
first.

## Kept as they are, with evidence

### Department keys — `EXISTING_BETTER_KEEP`

The instruction names departments as `marketplace_supplier_network`, `legal_compliance_risk_trust`,
`people_company_operations`, `independent_assurance_security_reliability`. Those are the department
**names**, and `org_departments.name` already carries them verbatim: "Marketplace & Supplier
Network", "Legal, Compliance, Risk & Trust", "People & Company Operations", "Independent Assurance,
Security & Reliability".

The keys `marketplace` / `legal` / `people_ops` / `assurance` are physical identifiers referenced by
`org_agents.department`, `agent_tool.authorised_departments`, `org_action_executor.department`,
`delegation_rule`, `fn_pick_reviewer` and 59 executor rows. Renaming them buys a cosmetic match and
risks the exact failure recorded on 14 August, when a merged-away department key silently emptied a
`where dept_key = …` scope and made the spend meter blind to 64% of the money.

### Physical `agent_key` values — `EXISTING_BETTER_KEEP`

`role_id` is the clear name and `agent_key` is the physical one; `fn_org_agent_resolve` resolves
both, plus every alias and every job title. Renaming `agent_key` would cascade through seven foreign
keys and five tables with no FK, to change a string the resolver already handles. What *did* change
is `org_agents.title`, because that is the arm of the resolver that makes a job title an identifier
— and the founder's standing rule is to address employees by title.

Verified after the change — old and new both resolve to one employee:

| Passed | Resolves to |
|---|---|
| `Supplier Matching & Dispatch Operator` / `supplier_matching_dispatch_operator` / `Commercial Services Specialist` | `spec_commercial` |
| `Marketplace Content & Privacy Reviewer` / `Content Moderation Reviewer` | `moderation_specialist` |
| `Agent Workforce & Capability Director` / `HR Director` | `hr_director` |
| `Visual Design Specialist` / `Visual Design Director` | `marketing_design` |

### The four broad technical specialists — `EXISTING_BETTER_KEEP`

MEP, Construction & Civil, Interior & Fit-Out, Industrial & Energy were **already**
`on_demand_specialist` with `advisory` authority — exactly what the instruction asks for. What was
missing was the fence. Their forbidden lists now name: duplicating a category question bank an
overlay owns, replacing the category specialist for a single-category question, dispatching,
overriding an authoritative category rule, silently activating a route. Their purpose is stated as
cross-category and multi-trade analysis only.

### Supplier re-validation at assignment — `EXISTING_BETTER_KEEP`

The instruction requires every supplier to be validated **immediately before assignment**, not only
at routing. `a00_unsafe_match_eligibility` → `fn_unsafe_match_eligibility_guard()` already did this,
at the layer every writer passes through. Proven on staging in an aborted transaction:

| Case | Rows landed |
|---|---|
| ineligible supplier (banned / blocked / closed / expired licence), rfq-ready inquiry | **0** |
| eligible supplier, rfq-ready inquiry | **1** |
| eligible supplier, inquiry **not** rfq-ready | **0** |

### The founder settings channel — `EXISTING_BETTER_KEEP`

`fn_founder_apply_setting` accepts only the sixteen keys `fn_founder_settings()` returns, all of
them operational caps and switches. No reserved commercial decision is reachable from it.

## Changed

### 1. `spec_commercial` → `supplier_matching_dispatch_operator` — REPURPOSE

Class **O**, `event_driven_operator`, `marketplace`, manager Marketplace Director, `execute_low`.

**Why.** `workflow_step` `rfq_handling` #5 "Select suppliers" named `domain specialist`, which
resolves to no employee. `dispatch_inquiry` was doing the work and recording it against
`agent_runs.agent = 'dispatch_inquiry'` (a code runner) and `agent_actions.agent = 'operations_ai'`
(which resolves to `ops_director` — a different department from the work).

**Why it is safe.** All ten commercial trade families this seat carried — accounting, cleaning,
facilities management, HR/recruitment, IT, legal, logistics, consulting, marketing, security — each
already have their own category overlay. Verified 10/10 on production. The trade knowledge stays
exactly where the instruction wants it: on demand, in the 86 overlays.

- Tools: `supplier_approve_clean` **removed** — an operator that can approve a supplier can
  manufacture its own eligible set. `supplier_verify` kept, because reading a supplier's standing
  immediately before assignment is what the instruction requires.
- Knowledge: the ten `cat:` scopes went with the overlays; the matching and dispatch rulebook stays.
- Model policy: `routine_employee_reasoning` — the cheapest tier. Eligibility, capability filtering,
  fairness and idempotency are code; `route_inquiry` does the adjudication. What is left for a model
  is summarising a refusal.
- Forbidden: setting dispatch policy (Marketplace Director's), bypassing RFQ qualification,
  bypassing supplier-safe review, approving a supplier, changing customer identity policy,
  overriding a category or regulatory gate.

### 2. `moderation_specialist` → `marketplace_content_privacy_reviewer` — REPURPOSE

Class **R**, `independent_reviewer`, `legal`, manager Trust & Safety Manager, `stop_authority`.
Placement reasoning and evidence: see `FINAL_REVIEWER_INDEPENDENCE.md`.

**Why.** `rfq_handling` had no supplier-safe payload or privacy review step at all. The brief and
the redaction were dispatched with no independent check that the customer's identity had left the
payload.

It inspects the artefact itself — the frozen supplier-safe snapshot, the supplier-facing file
revisions, the redacted drawings — and records the evidence, the revisions seen, the checks
performed and the reason. Trust & Safety keeps general moderation policy, disputes and enforcement.

### 3. Broad technical specialists — fence added (see above)

### 4. `organization_designer` → `people_ops` — REPURPOSE

Already `on_demand_specialist`; only the department and reporting line moved. Organisation design is
a workforce function and now sits beside the workforce director that commissions it. Still invocable
by the CEO, Chief of Staff, COO, Chief Performance Officer and the Agent Workforce & Capability
Director. Not continuously active.

### 5. `visual_design` → Visual Design Specialist — REPURPOSE

Class **S**. Authority `execute_low` → `advisory`. `artifact.review` **removed from its tools**.

**Why.** `artifact_review` defaulted `reviewer_agent` to `'marketing_design'`, this agent's own
runtime key, and both self-review guards compared identities raw. The guards now resolve; removing
the tool removes the capability as well as the loophole.

Approval boundaries now explicit in its forbidden list: brand/campaign/audience/message → Brand &
Creative Manager; privacy and supplier/customer safety → Marketplace Content & Privacy Reviewer;
the rendered artifact's alignment, crop, text, logo, dimensions and safe zones → AI Quality
Assurance Reviewer.

### 6. `test_automation_engineer` → Test Automation Engineer — REPURPOSE

Class **R** → **O**. `independent_reviewer` → `event_driven_operator`. `stop_authority` →
`execute_low`.

**Why.** The `role_id` was already correct; the title, class and authority still said reviewer. It
held `stop_authority` and owned "blocking a release on failing or missing tests" — the same decision
`quality_and_release_director` owns. A test author holding the release veto is the author ruling on
its own evidence. `change_deployment` now separates producing the evidence (#5, this role) from
ruling on it (#7, the director).

### 7. `hr_director` → `agent_workforce_capability_director` — REPURPOSE

Agent Workforce & Capability Director. The seat governs an AI workforce — canonical role
capabilities, workforce planning, the performance framework, role lifecycle, capability gaps and
remediation, restriction and reactivation, agent-role creation, human recruitment where genuinely
needed. "HR Director" described the smallest part of it. Culture & Performance, Learning &
Development and Recruitment are retained under it, on scheduled or on-demand modes.

### 8. UAE tax — scope extension plus one overlay, **not** a new employee

`financial_controller`'s approved scope now names UAE VAT, corporate-tax coordination, invoice tax
compliance, revenue recognition, taxable-supply treatment, statutory reconciliation, the filing
calendar and supporting-document controls, and requires escalation to a current authoritative source
or an external professional where the answer turns on current law. Knowledge scope `tax_uae` added.

`tax_overlay_uae` is a `knowledge_overlay` in the same shape as the 86 category overlays — no
runtime agent, invoked on demand, advisory only, forbidden from filing a return or committing the
company to a tax position without the CFO.

**Active employee count before: 90. After: 90.** Asserted by test.

### 9. Reviewer boundaries — six distinct scopes

See `FINAL_REVIEWER_INDEPENDENCE.md`.

## Roles that gained a caller

The census searches seven surfaces for each of the 90 roles: `pg_proc` bodies, `pg_cron` commands,
edge function source, `org_action_executor`, `workflow_step`, `employee_workflow`, `agent_tool`
grants.

| | roles named by nothing |
|---|---|
| before | **20 of 90** |
| after step-level ownership | 8 |
| after `org_align_04`/`05` | **0** |

The eight closed last were not redundant — each did work the company needs and was simply absent
from the step registry: Model Evaluation Reviewer and Test Automation Engineer (no offline-evaluation
or suite-building step existed in `change_deployment`), Engineering Manager (nothing said the change
gets implemented), Business Intelligence Analyst (`metric_lifecycle` measured but never reported),
Category Knowledge Curator and Taxonomy Governance Manager (no step for a stale module or a category
merge), Communications Manager (nothing owned whether an approved template existed), Government &
Enterprise Relations Manager (no step for a government counterparty), and then AI Director, AI
Quality Assurance Reviewer, Organisation Design Lead, Payments & Billing Manager and Agent & Prompt
Engineer.

## Defect found and fixed along the way

**A refused supplier was counted as a notified one.** `a00_unsafe_match_eligibility` returns `null`
on refusal. A `BEFORE` trigger returning null is not an error — PostgREST answers 201 with no row —
so `dispatch_inquiry`'s `if (!error) inserted++` counted the refusal as a contact. `routing.fanout`
over-reported the reach of the RFQ, and because `fn_rfq_redispatch_sweep` only retries a fanout
**recorded as 0**, an RFQ whose every match was refused looked dispatched and could never be
retried. The insert now selects back what landed, and the refusals are kept as the exclusion ledger.

## Necessity verdicts

All 90 roles carry a verdict in `FINAL_ROLE_NECESSITY_MATRIX.csv`:

| Verdict | Count |
|---|---|
| REQUIRED_CORE | 32 |
| REQUIRED_ON_DEMAND | 27 |
| REQUIRED_MANAGER | 12 |
| REQUIRED_REVIEWER | 8 |
| REPURPOSE | 7 |
| EXISTING_BETTER_KEEP | 4 |
| MERGE / DEFER / OBSOLETE | 0 |

No role was retained only because a row already exists: every one of the 90 has at least one real
caller, tools, knowledge scopes, an active KPI, an authority level and a forbidden-decision set —
each asserted by test on both projects.
