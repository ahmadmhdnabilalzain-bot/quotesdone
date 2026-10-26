# QuotesDone — Company Operations Corpus: What You Need to Do

You need two ZIP files:

1. `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31.zip`
2. `QuotesDone_CLAUDE_COMPANY_OPERATIONS_INGESTION_v2026.07.31.zip`

## Simple steps

1. Put both ZIP files inside your QuotesDone code repository under:
   `knowledge-import/company-operations/`
2. Open Claude Code from the repository root.
3. Open `01_PASTE_THIS_TO_CLAUDE.md` from this instructions ZIP.
4. Paste the complete prompt into Claude Code.
5. Give Claude access only to a staging Supabase project first.
6. Let Claude inspect the current repository and database schema.
7. Claude must import the files programmatically. It must not read the two-million-character master file into chat.
8. Review Claude's mapping and test report.
9. Do not activate production until the acceptance checklist passes.

## What this corpus adds

- Company core and policy
- 24 department operating packs
- Roles and authority
- SOPs and decision rules
- Exception and self-healing playbooks
- KPIs and templates
- Cross-department workflows and handoffs
- Live-data binding candidates
- Model cost/routing policy
- Audit, memory, data classification and incidents
- UAE legal, tax, privacy and security source registry

## What remains separate

The supplier-category knowledge corpus remains the technical source for the 86 supplier routes. Claude must link the two corpora by stable category and subcategory keys rather than copying all supplier knowledge into this package.
