# QuotesDone Knowledge Corpus — Production Specification

**Version:** 1.0  
**Purpose:** Define how 86 supplier-category knowledge packs will be researched, structured, validated, and handed to Claude for Supabase ingestion.

## 1. Objective

Create one authoritative, versioned knowledge package for every production supplier category. Each package must cover every mapped subcategory and contain both:

1. **Human-readable professional knowledge** for review and governance.
2. **Machine-executable knowledge** for deterministic inquiry qualification, supplier matching, validation, document requirements, regulatory triggers, and response generation.

The goal is to make Supabase and code the operational brain of QuotesDone, with external or high-cost AI used only for language interpretation, difficult document/image analysis, low-confidence exceptions, and scheduled knowledge maintenance.

## 2. Canonical Taxonomy Policy

- Use the **86-category production catalogue** as the single source of truth.
- Map every category to all canonical subcategories in production.
- Preserve stable IDs/slugs; names may be versioned without changing IDs.
- Each subcategory must belong to at least one category and one responsible agent.
- No category is marked complete merely because a generic summary exists.

## 3. Deliverable Per Category

Each category is delivered as one ZIP package:

```text
QD-KB-###-category-slug-vYYYY.MM.DD/
├── 00_README.md
├── 01_manifest.json
├── 02_category_master.md
├── 03_taxonomy.json
├── 04_glossary_en_ar.jsonl
├── 05_products_services.jsonl
├── 06_technical_knowledge.jsonl
├── 07_brands_manufacturers.jsonl
├── 08_supplier_ecosystem.jsonl
├── 09_quotation_knowledge.jsonl
├── 10_document_requirements.jsonl
├── 11_uae_regulations_authorities.jsonl
├── 12_inquiry_questions.jsonl
├── 13_decision_rules.jsonl
├── 14_validation_rules.jsonl
├── 15_pricing_cost_drivers.jsonl
├── 16_risks_common_mistakes.jsonl
├── 17_troubleshooting.jsonl
├── 18_scenarios_tests.jsonl
├── 19_source_registry.csv
├── 20_gap_register.csv
├── 21_ingestion_manifest.json
└── 22_QA_report.md
```

`02_category_master.md` is the large consolidated file requested by the founder. The JSONL/JSON/CSV files are the canonical ingestion format for Claude and Supabase.

## 4. Required Knowledge Modules Per Subcategory

Every subcategory must contain:

1. Industry knowledge and UAE market context
2. Products and services taxonomy
3. Technical knowledge
4. Brands and manufacturers
5. Supplier types and ecosystem
6. Commercial and pricing drivers
7. Customer requirements and trade-offs
8. Quotation knowledge
9. Documents knowledge
10. UAE regulations, authorities, approvals, and jurisdiction differences
11. Risk assessment
12. Troubleshooting and diagnostics
13. Best practices and common mistakes
14. Inquiry qualification logic
15. Terminology and synonyms in English and Arabic
16. Supplier capability and eligibility rules
17. Validation rules and completeness criteria
18. Scenario-based tests

## 5. Knowledge Record Schema

Every atomic record must include:

- `record_id`
- `category_slug`
- `subcategory_slug`
- `module`
- `record_type`
- `title`
- `content`
- `structured_data`
- `jurisdiction`
- `authority`
- `source_ids`
- `effective_date`
- `superseded_date`
- `version`
- `confidence`
- `validation_status`
- `review_after`
- `keywords_en`
- `keywords_ar`
- `applies_when`
- `exceptions`
- `escalation_rule`

## 6. Inquiry Question Record

Each question must specify:

- Stable question ID
- Customer-facing English and Arabic wording
- Technical/internal explanation
- Why the question matters
- Expected answer type
- Allowed values and units
- Mandatory/optional status
- Conditions that activate it
- Questions it depends on
- Validation rules
- Missing-answer behavior
- Price/delivery/installation impact
- Regulatory trigger, if any
- Documents that may answer it automatically
- Supplier-facing field generated from the answer
- Confidence contribution
- Escalation condition

## 7. Decision Rule Record

Rules must be deterministic whenever possible:

```json
{
  "rule_id": "example-rule",
  "subcategory_slug": "example-subcategory",
  "priority": 100,
  "when": {"all": [{"field": "example", "operator": "equals", "value": true}]},
  "then": [
    {"action": "ask_question", "question_id": "example-question"},
    {"action": "activate_requirement", "requirement_id": "example-requirement"}
  ],
  "source_ids": ["SRC-001"],
  "confidence": 0.95,
  "requires_human_review": false
}
```

## 8. Source Hierarchy

Use sources in this order:

1. UAE federal and emirate government authorities
2. Official regulator, municipality, utility, civil defence, and free-zone publications
3. Official legislation portals and gazettes
4. Official manufacturer documentation and product datasheets
5. Standards bodies and licensed standards
6. Accredited certification/testing bodies
7. Reputable professional and industry associations
8. Reputable technical references used only as supplementary context

Blogs, reseller pages, and unsourced AI-generated text must never be the primary authority for legal, regulatory, safety, or technical requirements.

## 9. Copyright and Licensing Rules

- Public official legislation may be indexed with source metadata and permitted excerpts.
- Paid standards such as ISO, IEC, NFPA, ASTM, BS, EN, UL, or proprietary manuals must not be reproduced in full without a licence.
- For protected standards, store applicability logic, approved summaries, clause references, and the location of the licensed source.
- Manufacturer catalogues should be converted into structured product facts with official links, version dates, and source IDs rather than copied indiscriminately.

## 10. Completeness Gate

A category is certified only when:

- Every canonical subcategory is covered.
- Every mandatory module is populated.
- Every factual regulatory statement is tied to a source ID.
- Every inquiry path has a deterministic question flow.
- Mandatory fields and validation rules are complete.
- Supplier eligibility rules exist.
- Document requirements and extraction mappings exist.
- English/Arabic terminology and synonyms exist.
- Scenario tests pass.
- Gaps are explicitly recorded rather than guessed.
- Stale or uncertain content is marked for review.

Character count is reported but is not the completion standard. Content must not be padded merely to reach a size target.

## 11. QA Metrics Reported Per Category

- Number of subcategories
- Number of knowledge records
- Number of authoritative sources
- Number of regulatory sources
- Number of brands/manufacturers covered
- Number of products/service families
- Number of qualification questions
- Number of decision rules
- Number of validation rules
- Number of document types
- Number of scenario tests
- English/Arabic glossary size
- Total characters and words
- Source freshness distribution
- Open gaps and risk rating

## 12. Runtime Cost-Control Design

- Do not load the entire category corpus into a model prompt.
- Retrieve only the relevant records by category, subcategory, field, jurisdiction, and current inquiry state.
- Use SQL and deterministic rules for question sequencing, completeness, validation, matching, and regulatory triggers.
- Use a small model only to parse natural language into structured fields and phrase approved questions.
- Use a high-end model only when confidence is below a threshold or for complex documents/images.
- Never allow a model to override an authoritative rule without an explicit escalation path.

## 13. Claude/Supabase Ingestion Contract

Claude should:

1. Validate every package against the JSON schema.
2. Upsert taxonomy, sources, records, questions, and rules using stable IDs.
3. Preserve source lineage and version history.
4. Generate embeddings only for narrative/searchable records, not for deterministic rules that can be queried directly.
5. Keep regulatory records versioned by jurisdiction and effective date.
6. Reject incomplete records rather than silently inserting malformed data.
7. Produce an ingestion report with inserted, updated, rejected, and duplicate counts.
8. Run scenario tests after ingestion.

## 14. Production Sequence

Each category follows this cycle:

1. Lock taxonomy and subcategories.
2. Build source map.
3. Collect authoritative sources.
4. Draft human-readable knowledge.
5. Convert knowledge into atomic records.
6. Build question and decision logic.
7. Create scenario tests.
8. Perform contradiction, freshness, and citation checks.
9. Deliver ZIP and QA report.
10. Claude ingests and reports schema/runtime issues before the next category.

## 15. First Production Category

**Category 01 — Construction, Civil & Building Materials**

Initial subcategory scope from the founder’s taxonomy:

- Structural steel and reinforcement
- Cement, concrete, and ready-mix
- Aggregates, sand, gravel, blocks, and bricks
- Precast concrete products
- Formwork, scaffolding, and shoring
- Waterproofing and damp-proofing systems
- Thermal, acoustic, and fire insulation
- Roofing systems and materials
- Earthworks, foundations, and piling materials
- Road and infrastructure materials
- Geotextiles and geosynthetics
- Mining and quarry products
- Mining equipment
- Modular buildings
- Prefabricated villas
- Container offices
- Portable cabins

The final mapping must be reconciled with the production Supabase subcategory catalogue before ingestion.

## 16. Definition of Done

The knowledge pack is not called complete because it is long. It is complete when a QuotesDone inquiry can be routed, qualified, validated, and converted into a supplier-ready brief for every mapped subcategory without routine internet research and without inventing technical or regulatory facts.
