# Token-Efficient Claude / Supabase Ingestion

## Core rule

Claude writes and executes an importer; Claude does not read the corpus record-by-record. File bytes move from disk/object storage to Supabase directly.

## Procedure

1. Place all category ZIPs in a local or CI workspace.
2. Claude reads only this control pack, category `01_manifest.json`, `21_ingestion_manifest.json`, schemas and compact QA/gap summaries.
3. Validate JSONL locally with code and return only counts and affected IDs.
4. Import source registry and taxonomy first, then atomic records in each package load order.
5. Stream line-by-line in batches of 250–1,000; never create a giant prompt or SQL string.
6. Upsert by stable ID plus package version. Use file SHA-256 to skip unchanged files.
7. Preserve source lineage, validation status, confidence, review dates and ingestion run ID.
8. Store questions, decision rules and validations relationally. They need no embeddings or chat-model calls.
9. Embed only changed narrative records asynchronously, preferably with a local/low-cost embedding model.
10. Run scenario tests in staging and return one compact pass/fail report.
11. Compare live OpenRouter calls with deterministic rules and internal retrieval; replace only tested paths.
12. Promote records only after relevant SME, legal/regulatory and bilingual review.

## Runtime

- A small router/classifier interprets ordinary customer language and returns candidate category/subcategory plus fields and confidence.
- SQL/rules choose the next missing question, completeness and supplier eligibility.
- Retrieval returns only a few relevant approved records or exact internal source extracts.
- Premium external models are reserved for low-confidence exceptions, complex documents, drawings and genuinely novel cases.
