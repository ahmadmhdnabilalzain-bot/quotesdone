# QuotesDone — Complete Knowledge Corpus

## What this ZIP contains

This is the **single knowledge-data ZIP** for the work completed so far.

It contains:

- **66 broad, deeply researched knowledge packages** covering the full master category hierarchy.
- **1 dedicated Lifts & Escalators supplement** created for operational route 86.
- **86 operational route manifests** matching the live supplier-category catalogue.
- The **crosswalk** that tells QuotesDone which broad knowledge packages and subcategories support each of the 86 live categories.
- English/Arabic routing aliases, route tests, manifests, QA reports and open-gap records.

## Important clarification

The application has **86 operational supplier routes**, but the knowledge itself is stored in **66 broad master packages** to avoid duplicating the same laws, products, questions and technical material many times.

For example, the MEP master package supports several live routes such as MEP, HVAC, Electrical and Plumbing. Each live route has its own manifest pointing to the applicable knowledge.

Therefore:

- `01_CATEGORY_KNOWLEDGE_PACKAGES/` contains the full knowledge.
- `02_OPERATIONAL_86_ROUTING/` connects that knowledge to all 86 live categories.
- `03_MANIFESTS_QA/` contains coverage, gaps and audit metadata.

## Folder structure

```text
QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31/
├── README_FIRST.md
├── FILE_INDEX.csv
├── SHA256SUMS.txt
├── 01_CATEGORY_KNOWLEDGE_PACKAGES/
│   ├── QD-KB-001-....zip
│   ├── ...
│   ├── QD-KB-066-....zip
│   └── QD-KB-086-lifts-and-escalators-....zip
├── 02_OPERATIONAL_86_ROUTING/
│   ├── 01_OPERATIONAL_CATEGORY_INDEX_001-086.csv
│   ├── 02_OPERATIONAL_CROSSWALK.jsonl
│   ├── 03_OPERATIONAL_ALIAS_LEXICON.jsonl
│   ├── 04_OPERATIONAL_ROUTE_TESTS.jsonl
│   └── route_manifests/ (86 JSON files)
└── 03_MANIFESTS_QA/
    ├── 00_FINAL_MANIFEST.json
    ├── 01_OPERATIONAL_86_QA_REPORT.md
    ├── 02_OPERATIONAL_86_GAP_REGISTER.csv
    └── 03_BROAD_PACKAGES_NOT_DIRECTLY_ROUTED.json
```

## Do not do this

Do **not** paste the category master files or JSONL records into a Claude chat. The corpus is too large and that would waste tokens.

Use the separate **Claude Ingestion Instructions ZIP**. Claude should build a streaming importer and move the files directly from disk into Supabase.

## Validation status

This is a production research corpus, not a blanket legal or engineering approval. Each record keeps its own source, confidence, validation status, review date, professional boundary and escalation rule. Claude must preserve those fields.
