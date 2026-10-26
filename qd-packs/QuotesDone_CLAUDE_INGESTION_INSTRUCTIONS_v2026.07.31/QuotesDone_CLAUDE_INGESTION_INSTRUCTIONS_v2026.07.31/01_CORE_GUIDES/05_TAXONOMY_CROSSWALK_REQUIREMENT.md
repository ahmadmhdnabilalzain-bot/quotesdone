# Taxonomy Crosswalk Requirement

The founder source file contains two related taxonomies:

1. **66 broad knowledge domains** with subcategories. The category knowledge packages use this sequence because Category 01 was approved in that form.
2. A separate **84-item realistic supplier list**.
3. The production code/export has been described as an **86-category catalogue**.

These are not automatically interchangeable.

## Required implementation

Claude must create a versioned crosswalk table with:

- `knowledge_domain_slug`
- `knowledge_subcategory_slug`
- `production_category_id`
- `production_category_slug`
- `relationship_type` (`primary`, `secondary`, `overlap`, `fallback`)
- `routing_priority`
- `effective_from`
- `review_status`

One knowledge subcategory may map to more than one production category, and one production category may retrieve knowledge from several domains. Runtime routing must use stable slugs/IDs, never the display sequence number.

Until the crosswalk is reviewed, ingest into staging and do not replace the live category router.
