# Troubleshooting

## Claude starts summarizing the corpus

Stop it and say:

> Do not read the corpus record-by-record. Follow `02_PASTE_THIS_TO_CLAUDE.md` and build the streaming importer.

## Upload is too large

Use Claude Code and place the ZIPs directly in the local repository. Do not upload the category contents individually.

## Claude cannot connect to Supabase

Have Claude generate the migrations and importer first. Configure these through local environment variables, not chat:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
DATABASE_URL (if direct Postgres access is used)
```

Then run dry-run validation locally before enabling database writes.

## Import stops midway

The importer must resume using ingestion-run records, stable IDs and file hashes. Do not restart with a destructive truncate.

## Existing schema conflicts with supplied schema

Claude should map supplied logical fields to existing tables, document the mapping and create only the missing fields/tables. It must not silently discard source lineage, status, version or review fields.

## Embedding cost becomes high

Do not embed all data again on every import. Hash each narrative record and embed only new or changed records asynchronously. Questions and rules should remain relational and normally need no embeddings.

## Router still calls OpenRouter for every message

Ask Claude for the OpenRouter-reduction report and require alias/rule-based first-pass routing before any external model call.
