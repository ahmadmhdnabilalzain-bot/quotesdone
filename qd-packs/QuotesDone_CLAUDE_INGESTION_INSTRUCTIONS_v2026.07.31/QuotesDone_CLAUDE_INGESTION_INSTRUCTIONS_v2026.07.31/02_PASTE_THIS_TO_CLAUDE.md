# Copy and Paste This Entire Prompt to Claude

You are the implementation engineer for the QuotesDone knowledge-corpus integration.

Two archives are available in the repository under `knowledge-import/`:

- `QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31.zip`
- `QuotesDone_CLAUDE_INGESTION_INSTRUCTIONS_v2026.07.31.zip`

Your task is to integrate the knowledge corpus into the existing QuotesDone codebase and Supabase architecture in a safe, idempotent and token-efficient way.

## First principles

1. Do **not** read, paste or summarize the full category masters or JSONL corpus into your conversation context.
2. Treat the archives as data files. Write code that extracts, validates and streams them directly from disk to Supabase.
3. Work in a new Git branch and staging environment/schema first.
4. Inspect the existing database schema, migrations, edge functions, agent routing, inquiry intake, supplier matching and current knowledge tables before choosing table names.
5. Adapt the supplied schemas and templates to the existing architecture rather than creating unnecessary parallel systems.
6. Do not perform destructive production changes. Stop only if a destructive conflict or missing required credential prevents safe progress.

## Corpus structure

The knowledge archive contains:

- 66 broad master knowledge-package ZIPs;
- a dedicated Lifts & Escalators knowledge supplement;
- 86 operational supplier-route manifests;
- the operational crosswalk;
- English/Arabic routing aliases;
- route tests;
- manifests, QA reports and gap registers.

The 86 live routes reference the broad packages. Do not duplicate millions of narrative records for every route.

## Required implementation

### A. Repository and database assessment

1. Identify the existing live tables and code paths for:
   - categories and subcategories;
   - category aliases;
   - agent knowledge / KB chunks;
   - qualification questions;
   - inquiry completeness;
   - decision and validation rules;
   - source lineage;
   - embeddings/vector search;
   - agent routing;
   - OpenRouter calls.
2. Produce a concise mapping from the supplied logical schema to existing tables.
3. Prefer extending compatible tables. Add new versioned tables only where the existing design cannot preserve the supplied fields safely.

### B. Staging schema and migration

Create reversible migrations supporting at minimum:

- source registry;
- broad categories and subcategories;
- aliases and bilingual glossary;
- narrative knowledge records;
- qualification questions;
- decision rules;
- validation rules;
- scenario tests;
- knowledge gaps;
- ingestion runs and file hashes;
- operational 86-category routes;
- route-to-package/subcategory crosswalk;
- operational aliases;
- route tests;
- versioning, validation status, confidence, review dates and source lineage.

Add appropriate indexes, foreign keys, unique constraints and RLS/grant controls. Do not expose private knowledge directly to anonymous users.

### C. Importer

Build one deterministic, idempotent streaming importer that:

1. Extracts the outer knowledge ZIP locally.
2. Opens one category ZIP at a time.
3. Reads manifests, taxonomy and source registry first.
4. Streams JSONL line by line in batches of 250–1,000.
5. Validates every row against the supplied JSON schema.
6. Upserts by stable record/question/rule/validation/scenario ID plus package version.
7. Preserves earlier versions and attaches every change to an `ingestion_run_id`.
8. Uses SHA-256 file hashes to skip unchanged files.
9. Records inserted, updated, skipped, rejected and duplicate counts by category and file.
10. Can resume safely after interruption.
11. Has a dry-run mode that performs extraction and validation without database writes.
12. Does not call OpenRouter or any chat model during ingestion.

### D. Knowledge storage rules

1. Import narrative/search knowledge into searchable knowledge tables.
2. Store questions, decision rules, validation rules and supplier-eligibility logic as relational deterministic data.
3. Do not embed questions/rules unless the current architecture requires a secondary search copy; relational records remain authoritative.
4. Generate embeddings only for changed narrative records, asynchronously.
5. Prefer a local or low-cost embedding model where technically appropriate.
6. Preserve each record's `validation_status`. Never mass-promote `draft`, `reviewed` or `source_verified` records to `approved`.
7. Preserve professional/legal/regulatory escalation boundaries.

### E. Operational 86-category layer

1. Query the live operational catalogue ordered by category number and verify there are exactly 86 active routes.
2. Resolve live IDs/slugs without overwriting production slugs merely because an expected slug differs.
3. Import all 86 route manifests, crosswalk rows and aliases.
4. Category 85 must map to the relevant signage/printing knowledge already present in the broad corpus.
5. Category 86 must map to the dedicated Lifts & Escalators supplement.
6. Create a coverage view/report where all 86 routes show `MAPPED` and no route has zero mapped subcategories.
7. Preserve multi-category routing where an inquiry legitimately spans multiple routes.

### F. Runtime behavior

Implement or adapt the runtime so that:

1. The customer's original wording is retained.
2. First-pass routing uses deterministic bilingual aliases, keywords, taxonomy and extracted fields.
3. The router returns ranked category/subcategory candidates, confidence and reasons.
4. If the leading routes remain close, ask one short outcome-based clarification instead of forcing a route.
5. A small model may parse ordinary customer language only when deterministic parsing is insufficient.
6. Deterministic rules choose the next missing question, completeness status, validation result and supplier eligibility whenever an applicable approved rule exists.
7. Existing trusted document extraction fills fields before the customer is asked again.
8. Supplier dispatch remains fail-closed for missing critical fields, unresolved document conflicts, failed privacy/redaction or professional/regulatory escalation.
9. Runtime retrieval sends only a few relevant approved records or exact source extracts to a model—not a whole category master.
10. Premium external AI remains only for complex drawings/images, unresolved ambiguity, conflicting documents and genuinely novel exceptions.

### G. Tests and acceptance

Run:

- all supplied JSON/schema validators;
- all 258 operational route tests;
- all category scenario tests available in the packages;
- duplicate/import-idempotency test;
- interrupted-import resume test;
- rollback test;
- routing tests in English and Arabic;
- tests proving questions are not repeated when a trusted answer already exists;
- tests proving critical missing information blocks supplier dispatch;
- regression tests for existing customer, supplier and inquiry flows.

Acceptance conditions:

- 86 live operational routes found;
- 86 routes mapped;
- zero orphan routes;
- zero invalid subcategory references;
- zero malformed records accepted;
- all failed rows listed with exact IDs/reasons;
- no full master file injected into a runtime prompt;
- no duplicate records after rerunning the importer;
- rollback is documented and tested;
- validation status and source lineage are preserved.

### H. OpenRouter reduction report

Audit every current OpenRouter call and classify it as:

1. replaceable by SQL/deterministic rules;
2. replaceable by internal retrieval/templates;
3. replaceable by a small local model;
4. still requires a premium model.

Do not remove a premium-model path until the replacement passes realistic tests. Add feature flags and fallback behavior.

## Required final deliverables

Return or create in the repository:

- migrations/schema mapping;
- importer and validators;
- configuration/environment-variable guide;
- dry-run report;
- staging ingestion report by package/file;
- operational 86-category coverage report;
- scenario and route-test report;
- OpenRouter-reduction report;
- unresolved-gap list;
- rollback procedure;
- production activation checklist;
- concise summary of all changed files.

Do not ask me to paste corpus content into chat. Use the files and programmatic importer. Proceed without pausing for routine implementation choices; ask only when a destructive schema conflict, missing database access or genuinely ambiguous business decision blocks safe progress.
