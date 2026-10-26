# What Ahmad Should Do — Step by Step

## Option A — Claude Code, recommended

1. Download both ZIP files.
2. Make a local copy of your current QuotesDone repository.
3. Create a new Git branch:

```bash
git checkout -b feature/knowledge-corpus-import
```

4. Create this folder inside the repository:

```text
knowledge-import/
```

5. Copy both ZIP files into that folder without changing their names.
6. Open Claude Code from the repository root.
7. Upload or point Claude to the instructions ZIP.
8. Paste the full contents of `02_PASTE_THIS_TO_CLAUDE.md`.
9. Let Claude inspect the current database schema and agent runtime.
10. Claude should build a dry-run validator first.
11. Claude should import into staging, one category package at a time.
12. Review Claude's final reports before enabling production use.

## Option B — Normal Claude web chat

This is less reliable for a large engineering task. Upload both ZIPs and paste the same prompt. Tell Claude to generate the migrations/importer for you, then download those files and run them in your repository. Do not ask a normal chat to read the whole corpus conversationally.

## What you should receive from Claude

- Database migration or schema mapping
- Streaming importer
- Validation scripts
- 66 broad knowledge packages imported
- Lifts and escalators supplement imported
- 86 operational routes mapped
- Alias lexicon imported
- Route and scenario test reports
- OpenRouter-reduction report
- Rollback instructions
- List of unresolved gaps

## When you can consider it complete

Do not consider it complete merely because rows exist in Supabase. It is complete only when:

- all 86 operational categories are mapped;
- no route has zero subcategories;
- questions and rules are queryable through the application;
- all route tests pass;
- category scenario tests have been executed;
- duplicate imports do not create duplicate rows;
- an import can be rolled back by run/version;
- existing customer and supplier flows still work;
- the new system is behind a feature flag until approved.
