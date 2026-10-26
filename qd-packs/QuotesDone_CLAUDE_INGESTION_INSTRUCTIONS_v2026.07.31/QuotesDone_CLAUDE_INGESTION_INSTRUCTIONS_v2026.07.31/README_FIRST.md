# QuotesDone — Claude Ingestion Instructions

Use this ZIP together with:

`QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31.zip`

Expected SHA-256 for the knowledge ZIP:

```text
fd550722a5aa3aeaf155d92d107567ed4de3a48aff468672ade7c20f66f34e45
```

## The simplest path

1. Read `00_READ_ME_FIRST.md`.
2. Follow `01_AHMAD_STEP_BY_STEP.md`.
3. Copy the full text from `02_PASTE_THIS_TO_CLAUDE.md` into Claude Code.
4. Give Claude access to both ZIP files in the repository.
5. Require Claude to import into staging and return the acceptance reports.
6. Use `03_ACCEPTANCE_CHECKLIST.md` before production activation.

## Contents

- Plain-English setup instructions for Ahmad
- Exact copy-and-paste prompt for Claude
- Acceptance checklist
- Runtime design and cost-reduction explanation
- Troubleshooting and security notes
- Supabase schema starters
- TypeScript importers
- Python validation scripts
- Knowledge JSON schema
- Category indexes, manifests and QA reports

The importer should move bytes directly from disk to Supabase. Claude should never consume the complete knowledge corpus as conversational tokens.
