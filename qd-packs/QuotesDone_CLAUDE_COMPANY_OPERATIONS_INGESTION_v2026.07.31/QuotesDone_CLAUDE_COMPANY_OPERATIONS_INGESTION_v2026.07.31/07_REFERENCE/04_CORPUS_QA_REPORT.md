# QuotesDone Company Operations Corpus — QA Report

**Build date:** 2026-07-31
**Version:** 1.0.0
**Certification status:** Structurally validated production operating draft; not production-approved.

## Coverage
- Departments: **24**
- Cross-department workflows: **18**
- Workflow handoffs: **132**
- Event subscription records: **100**
- Target role records: **96**
- Total atomic records: **3,959**
- Master document characters: **2,057,246**
- Registered sources: **21**
- Code-evidence rows: **569**
- JSON Schema validation errors: **0**
- Duplicate canonical record IDs: **0**
- Unresolved source IDs: **0**

## Record types
- `agent_role`: 96
- `anonymity_principle`: 1
- `audit_requirement`: 8
- `auditability`: 1
- `authoritative_source`: 21
- `automation_first`: 1
- `bilingual_customer_experience`: 1
- `company_identity`: 1
- `control_requirements`: 480
- `cross_department_workflow`: 18
- `data_and_evidence`: 480
- `data_classification`: 5
- `decision_rule`: 240
- `decision_tiers`: 1
- `department_scenario`: 192
- `event_subscription`: 100
- `exception_playbook`: 240
- `four_layers`: 1
- `hard_gate`: 10
- `incident_priority`: 4
- `knowledge_domain`: 480
- `live_data_binding`: 268
- `marketplace_model`: 1
- `memory_policy`: 6
- `metric_definition`: 216
- `mission`: 1
- `model_routing_policy`: 5
- `operating_principle`: 20
- `operational_application`: 480
- `operational_template`: 120
- `reveal_fee`: 1
- `standard_operating_procedure`: 236
- `supplier_category_corpus`: 1
- `vision`: 1
- `workflow_handoff`: 132
- `workflow_scenario`: 90

## Implementation status
- `implemented`: 1325
- `partial`: 1317
- `target_state`: 1317

## Validation status
- `draft`: 6
- `reviewed`: 3651
- `source_verified`: 302

## Automated checks passed
- Every canonical record has a unique stable ID.
- Every canonical record passed the Draft 2020-12 JSON Schema.
- Every source ID resolves to the source registry.
- All 24 department folders contain master, knowledge, role, SOP, rule, exception, KPI, template, scenario, binding, evidence and gap files.
- All 18 cross-department workflows contain ordered department-owned steps and hard-gate metadata.
- Live-data candidates distinguish exact export matches from unresolved concepts.
- Implementation and validation status are preserved and are not mass-promoted to approved.
- The aggregate JSONL is a convenience copy and is excluded from duplicate validation against modular canonical files.

## Acceptance blockers
- **OPS-GAP-001 (critical) — production activation:** The corpus is a production operating draft and has not been imported, mapped or tested against the current GitHub repository and live staging database. Closure: Claude must implement staging import, map objects, run all scenario tests and produce a signed acceptance report before production.
- **OPS-GAP-002 (high) — frontend:** The supplied production export explicitly excludes the Next.js frontend, so user-facing permissions, states, notices, Arabic coverage and controls are not verified. Closure: Inspect the current frontend repository and add end-to-end UI acceptance tests for every high-risk workflow.
- **OPS-GAP-003 (critical) — legal and tax:** Official sources are registered and operational summaries are provided, but the corpus is not a substitute for qualified UAE legal, tax or accounting advice. Closure: Designate qualified reviewers, acquire current source copies where needed and approve regulated records before autonomous use.
- **OPS-GAP-004 (high) — security and secrets:** The corpus intentionally excludes actual credentials and secret values. Current provider connections, permissions, key rotation and least-privilege state are not proven by this package. Closure: Claude and the security owner must inspect the live secret store, IAM, webhook configuration and grants without exposing values in reports.
- **OPS-GAP-005 (high) — department structure:** Several blueprint departments have partial capabilities but no one-to-one org_departments row confirmed in the export, including Sales, HR, Admin, QA, Business Development and Communications. Closure: Map them to current teams or create explicit target departments, agents, authority and health views in staging.
- **OPS-GAP-006 (high) — live data bindings:** Some conceptual table names in the department packs do not exist by exact name in the supplied export. Closure: Use the implementation evidence registry to map each concept to the current table/view/function and keep unresolved bindings disabled.
- **OPS-GAP-007 (high) — supplier knowledge dependency:** The company-operations corpus references the separate 86-category supplier corpus; it does not duplicate or independently validate that technical corpus. Closure: Import and validate the supplier corpus first or in parallel, then enforce stable category/subcategory references.
- **OPS-GAP-008 (medium) — integrations:** Provider integrations may be represented in code but their current connection, permissions, quotas and production status are dynamic. A specific OpenArt connection was not proven from the backend export. Closure: Build an integration inventory from live configuration, verify each provider, document fallbacks and mark unverified integrations unavailable.
- **OPS-GAP-009 (high) — metrics:** KPI definitions are operational specifications; many still require exact production SQL, data-owner approval and reconciled baselines. Closure: Create metric queries, test against source records and version the definitions before dashboard use.
- **OPS-GAP-010 (high) — autonomy:** Target-state SOPs and rules must not be interpreted as new authority merely because they are imported. Closure: Preserve implementation and validation status, apply existing constitutional hard caps and require explicit approval for authority changes.
- **OPS-GAP-011 (medium) — external sources:** The ZIP registers official source URLs and summaries but does not bundle every full law, regulation, tax guide or licensed standard. Closure: Acquire authorised current copies, store hashes and versions, and ingest selectively with licensing controls.
- **OPS-GAP-012 (high) — business continuity:** Runbooks are defined, but real recovery time, backup restoration and provider fallback performance must be demonstrated. Closure: Run scheduled disaster-recovery and provider-outage drills in staging and controlled production windows.
- **OPS-GAP-013 (medium) — organizational ownership:** The founder blueprint defines capabilities more broadly than the production org, and some responsibilities overlap. Closure: Approve the department crosswalk and RACI matrix, then resolve duplicate ownership and missing escalation paths.
- **OPS-GAP-014 (high) — data retention:** Retention periods are intentionally not hard-coded because they depend on data type, law, tax, contract and current policy. Closure: Legal, Finance, Security and Data owners must approve a live retention schedule and link every table/data class.

## Required acceptance sequence
1. Import into a staging schema only.
2. Map existing production objects and do not create duplicates without review.
3. Validate all records, sources and department mappings.
4. Run department and workflow scenarios.
5. Verify hard gates and permissions with adversarial tests.
6. Verify the current frontend and user-visible states.
7. Obtain Legal, Finance/Tax, Security and departmental owner approvals.
8. Activate one low-risk department or workflow at a time.
9. Monitor quality, cost, overrides and incidents before broader activation.