# Claude Code implementation request — QuotesDone company operating knowledge

You are the implementation engineer for the existing QuotesDone repository.

Two packages are available under `knowledge-import/company-operations/`:

- `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31.zip`
- `QuotesDone_CLAUDE_COMPANY_OPERATIONS_INGESTION_v2026.07.31.zip`

The supplier-category corpus for the 86 operational supplier routes is a separate dependency and may already be present.

## Objective

Integrate the company and department operating corpus into QuotesDone so that agents understand:

- company core knowledge and policies;
- department responsibilities, professional knowledge and authority;
- SOPs, decision rules and exceptions;
- cross-department workflows and accepted handoffs;
- live business data sources;
- KPIs, audit, memory, incident and model-routing policy;
- how the internal operating corpus links to the supplier-category corpus.

Do this without loading the full corpus into the Claude conversation and without weakening existing security or governance.

## Non-negotiable rules

1. Work on a new branch and a staging Supabase project first.
2. Do not paste or summarize the full `00_COMPANY_OPERATIONS_MASTER.md` into context.
3. Validate the outer ZIP, `00_PACKAGE_MANIFEST.json`, `99_CHECKSUMS_SHA256.txt` and every JSONL line programmatically.
4. Inspect the current repository, migrations and database schema before creating new objects.
5. Reuse or extend existing objects where appropriate, including:
   - `org_departments`, `org_agents`, `org_authority`, `org_objectives`, `org_tasks`, `org_memory`
   - `employee_knowledge`, `employee_knowledge_standard`, `employee_workflow`, `employee_authority`, `employee_kpi`
   - `dept_library`, `agent_knowledge`, `agent_memory`, `institutional_memory`
   - `decision_policy`, `decision_record`, `delegation_rule`, `governance_policy`, `governance_rule`
   - `integration_matrix`, `implementation_map`, `agent_action_log`, `os_audit_log`
   - `scenario_library`, `risk_register`, `company_event`, `event_subscription`
6. Do not create duplicate sources of truth. If an existing object already owns a concept, map the new records to it or extend it through a versioned migration.
7. Preserve every record's:
   - stable `record_id`
   - scope and module
   - `source_ids`
   - `implementation_status`
   - `validation_status`
   - authority tier and risk level
   - version, effective date and review date
   - dependencies and escalation rule
8. `target_state` and `partial` records do not become implemented simply because they are imported.
9. Do not promote any record to `approved` automatically.
10. Legal, tax, privacy, security, identity, money movement, destructive operations, production deployment, public claims and authority changes remain hard-gated.
11. Never place secret values, credentials, full payment data or private identity documents into knowledge tables, logs, model prompts or reports.
12. Keep current customer, supplier, inquiry, quotation, payment, task and KPI state in live operational tables. Static knowledge may reference those bindings but must not duplicate volatile values.
13. Questions, SOP state, decision rules, authority, handoffs, validations and KPIs must be deterministic relational data. Use embeddings only for narrative retrieval.
14. The supplier-category corpus remains the technical source for category inquiry and quote-comparison expertise. Link by stable category/subcategory key.
15. Do not make OpenRouter or any premium model the default when deterministic code, SQL, templates, internal retrieval or an approved small model can safely perform the task.
16. No production activation in this session. Stop after staging import, mapping, test execution and a compact implementation report.

## Required implementation sequence

### Phase 1 — Inspect and map

1. Extract both ZIP files locally.
2. Read only:
   - `START_HERE.md`
   - `00_PACKAGE_MANIFEST.json`
   - `05_QA_AND_REPORTS/05_QA_REPORT.md`
   - `04_AGENT_RUNTIME_AND_GOVERNANCE/07_PRODUCTION_TO_TARGET_DEPARTMENT_CROSSWALK.csv`
   - the record schema and source registry
3. Inspect current migrations, functions, frontend, environment configuration and Supabase objects.
4. Produce a mapping table for every target object:
   - reuse existing object;
   - extend existing object;
   - create staging-only object;
   - unresolved / needs decision.
5. Report material conflicts before modifying production-shaped structures.

### Phase 2 — Staging schema and importer

1. Adapt the supplied staging SQL to the current architecture.
2. Implement a streaming importer:
   - one file at a time;
   - one JSON object per line;
   - batches of 250–1,000;
   - upsert by stable ID;
   - record file hash and package version;
   - resume safely after interruption;
   - reject malformed or unknown records;
   - produce inserted/updated/skipped/rejected counts.
3. Import in this order:
   - source registry and schema;
   - company core;
   - department index and crosswalk;
   - roles and authority;
   - department knowledge;
   - SOPs, rules and exceptions;
   - workflows, handoffs and events;
   - live-data bindings;
   - KPIs, templates and scenarios;
   - narrative embeddings after relational validation.

### Phase 3 — Runtime integration

Implement or adapt:

1. Agent context assembly:
   - company core;
   - department knowledge;
   - current live entity data;
   - applicable authoritative external source;
   - relevant institutional memory.
2. Department routing and workflow ownership.
3. Deterministic rule execution and authority checks.
4. Accepted handoffs with sender/receiver accountability.
5. Audit records with evidence and concise decision summaries.
6. Model-routing policy and fallback.
7. Knowledge review dates, supersession, quarantine and recertification.
8. Supplier-corpus link for RFQ Intelligence, Marketplace Operations, Supplier Knowledge and Document Intelligence.

### Phase 4 — Tests

Run:

- package validation and checksum tests;
- all department scenarios;
- all cross-department workflow scenarios;
- hard-gate adversarial tests;
- permissions and least-privilege tests;
- idempotency and duplicate-event tests;
- outage and recovery tests;
- English and Arabic customer-facing tests where applicable;
- supplier-corpus integration tests;
- current frontend workflow tests;
- rollback and restoration tests.

### Phase 5 — Report and stop

Return a concise report containing:

- branch and staging environment used;
- schema changes;
- existing objects reused;
- new staging objects;
- inserted/updated/skipped/rejected records by file and department;
- unresolved mappings;
- scenario pass/fail counts;
- security, legal, finance and privacy blockers;
- front-end gaps;
- OpenRouter calls replaceable by deterministic/internal paths;
- estimated remaining model calls and why;
- rollback plan;
- recommended controlled activation order.

Do not activate production. Do not mass-promote validation status. Do not claim complete implementation where the code or tests do not prove it.
