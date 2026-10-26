# Final Claude Instruction — Ingest the Complete QuotesDone Corpus

You are the implementation engineer. Do not read the category master files or paste JSONL into chat. Treat all category ZIPs as data files.

1. Read only this control folder, each category `01_manifest.json`, `21_ingestion_manifest.json`, `22_QA_report.md` and gap register.
2. Adapt the supplied staging schema and streaming importer to the current QuotesDone/Supabase schema.
3. Extract one category ZIP at a time and stream JSONL line-by-line in batches of 250–1,000.
4. Validate every record locally against the schema; upsert by stable ID and package version; preserve source lineage, confidence, status and review dates.
5. Import taxonomy and source registry before records. Build a many-to-many crosswalk from the 66 research domains/subcategories to all live production category IDs. Match by stable slug and intent evidence, never display number alone.
6. Store qualification questions, decision rules, validations and scenarios in relational tables. Do not embed them and do not ask an LLM to decide sequencing when an approved rule exists.
7. Embed only changed narrative/search records asynchronously. Use file SHA-256 and ingestion manifests to skip unchanged content.
8. Keep privacy/redaction, supplier eligibility, professional-boundary and authority-confidence gates fail-closed.
9. Run scenario tests category-by-category in staging, then produce compact counts and failing IDs only.
10. Do not mark `draft`, `reviewed` or `source_verified` records as `approved` without the required SME/legal/regulatory sign-off.
11. Produce an OpenRouter-reduction report identifying calls replaceable by routing aliases, SQL, deterministic rules, internal retrieval or a small local parser.
12. Provide rollback by ingestion run and package version.

Required deliverables: migrations/schema mapping, importer, category crosswalk, ingestion report, scenario report, unresolved gaps, OpenRouter-reduction report and rollback procedure.
