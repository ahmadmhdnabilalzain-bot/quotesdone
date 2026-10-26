# Read Me First — QuotesDone Knowledge Import

You need only two files:

1. `QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31.zip`
2. `QuotesDone_CLAUDE_INGESTION_INSTRUCTIONS_v2026.07.31.zip`

The first ZIP contains the knowledge data. The second ZIP tells Claude how to import and connect it.

## Recommended method

Use **Claude Code inside a local copy of the QuotesDone repository**. This is better than pasting files into a normal chat because Claude Code can inspect the repository, write migrations and import scripts, execute tests and read the ZIPs directly from disk.

## Safety requirements

Before starting:

- Create a fresh Git branch, for example `feature/knowledge-corpus-import`.
- Take a database backup.
- Use a staging Supabase project or staging schema first.
- Put Supabase credentials in environment variables. Never paste a service-role key into chat.
- Do not activate the new runtime in production until the import and scenario tests pass.

## What Claude must not do

- Do not paste or summarize the full corpus into its prompt.
- Do not create one giant SQL statement containing all knowledge.
- Do not duplicate the broad knowledge once for every operational category.
- Do not mark all records as `approved`.
- Do not delete or overwrite existing knowledge without versioning and rollback.
- Do not make a language model choose question order when a deterministic rule exists.

## What Claude should do

Claude should write an importer that streams the JSONL and CSV files from disk into Supabase in small batches. The importer—not Claude's language context—moves the data.
