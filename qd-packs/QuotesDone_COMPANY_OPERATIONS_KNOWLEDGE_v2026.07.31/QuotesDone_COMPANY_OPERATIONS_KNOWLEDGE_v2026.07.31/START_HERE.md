# QuotesDone Company & Department Operations Knowledge Corpus

## What this package is

This is the internal operating knowledge for QuotesDone. It is separate from the supplier-category knowledge corpus.

It covers:

- Company core knowledge and operating principles
- 24 target departments
- Roles, responsibilities, skills, limits and performance measures
- Department SOPs
- Decision rules and authority boundaries
- Exception and recovery playbooks
- Cross-department workflows and handoffs
- Live-data binding candidates
- Model-routing and cost-control policy
- Memory, audit, data classification and incident policy
- UAE legal, tax, privacy and security source registry
- Implementation evidence from the supplied production export
- QA, gap and acceptance reports

## What this package is not

- It is not a replacement for the 86-category supplier knowledge corpus.
- It is not proof that every target department is already implemented.
- It does not contain passwords, secret values or private founder identity documents.
- It does not grant new authority merely by being imported.
- It is not legal, tax, accounting, engineering or cybersecurity professional approval.

## Package metrics

- Departments: 24
- Cross-department workflows: 18
- Atomic records: 3,959
- Target role records: 96
- Master document characters: 2,057,246
- Registered sources: 21
- Code evidence rows: 569

## Start here

1. Read `05_QA_AND_REPORTS/05_QA_REPORT.md`.
2. Review `04_AGENT_RUNTIME_AND_GOVERNANCE/07_PRODUCTION_TO_TARGET_DEPARTMENT_CROSSWALK.csv`.
3. Give this ZIP and the separate Claude ingestion-instructions ZIP to Claude Code inside the QuotesDone repository.
4. Import into staging only.
5. Preserve every record's `implementation_status`, `validation_status`, authority tier, sources and review date.
6. Do not read the two-million-character master file into Claude's conversation. Use the streaming importer.
7. Link this corpus to the already prepared supplier-category corpus by stable category/subcategory keys.

## Recommended import order

1. Source registry and record schema
2. Company core
3. Department registry and crosswalk
4. Roles and authority
5. Department knowledge
6. SOPs, decision rules and exception playbooks
7. Cross-department workflows, handoffs and event subscriptions
8. Live-data bindings
9. KPIs and scenario tests
10. Narrative embeddings only after structured imports pass
11. Staging QA and acceptance report
12. Controlled activation

## Critical principle

Static knowledge explains how the company works. Live customer, supplier, inquiry, quotation, payment, task and KPI state must still be retrieved from the current operational database.
