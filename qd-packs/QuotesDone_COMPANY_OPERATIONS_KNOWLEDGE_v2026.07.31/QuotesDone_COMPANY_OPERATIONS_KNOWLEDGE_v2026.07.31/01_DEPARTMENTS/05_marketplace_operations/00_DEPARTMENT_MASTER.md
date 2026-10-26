# Marketplace Operations — Operating Knowledge Pack

**Department key:** `marketplace_operations`  
**Production mapping:** procurement  
**Implementation assessment:** `implemented`  
**Version:** 1.0.0  

## Charter
Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality.

## North-star outcome
Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons.

## Core knowledge domains
1. inquiry lifecycle
2. supplier matching
3. fan-out rules
4. supplier eligibility
5. quote lifecycle
6. quotation extraction
7. technical normalization
8. commercial normalization
9. quote completeness
10. deviation detection
11. supplier ranking
12. top-three recommendation
13. award workflow
14. marketplace policies
15. customer ranking
16. supplier response rates
17. duplicate dispatch prevention
18. coverage gaps
19. reveal workflow
20. marketplace quality

## Owned workflows
1. supplier matching
2. inquiry dispatch
3. quotation receipt
4. quotation extraction
5. technical review
6. comparison and scoring
7. top-three recommendation
8. award and reveal
9. marketplace exception review
10. coverage-gap escalation

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Inquiry Lifecycle — operating knowledge
Marketplace Operations must understand inquiry lifecycle as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Inquiry Lifecycle — how the department uses it
When work involves inquiry lifecycle, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Inquiry Lifecycle — controls and boundaries
For inquiry lifecycle, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Inquiry Lifecycle — evidence and live-data requirements
The department should prove work on inquiry lifecycle through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Matching — operating knowledge
Marketplace Operations must understand supplier matching as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Matching — how the department uses it
When work involves supplier matching, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Matching — controls and boundaries
For supplier matching, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Matching — evidence and live-data requirements
The department should prove work on supplier matching through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Fan-Out Rules — operating knowledge
Marketplace Operations must understand fan-out rules as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Fan-Out Rules — how the department uses it
When work involves fan-out rules, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Fan-Out Rules — controls and boundaries
For fan-out rules, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Fan-Out Rules — evidence and live-data requirements
The department should prove work on fan-out rules through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Eligibility — operating knowledge
Marketplace Operations must understand supplier eligibility as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Eligibility — how the department uses it
When work involves supplier eligibility, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Eligibility — controls and boundaries
For supplier eligibility, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Eligibility — evidence and live-data requirements
The department should prove work on supplier eligibility through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Quote Lifecycle — operating knowledge
Marketplace Operations must understand quote lifecycle as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Quote Lifecycle — how the department uses it
When work involves quote lifecycle, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Quote Lifecycle — controls and boundaries
For quote lifecycle, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Quote Lifecycle — evidence and live-data requirements
The department should prove work on quote lifecycle through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Quotation Extraction — operating knowledge
Marketplace Operations must understand quotation extraction as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Quotation Extraction — how the department uses it
When work involves quotation extraction, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Quotation Extraction — controls and boundaries
For quotation extraction, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Quotation Extraction — evidence and live-data requirements
The department should prove work on quotation extraction through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Technical Normalization — operating knowledge
Marketplace Operations must understand technical normalization as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Technical Normalization — how the department uses it
When work involves technical normalization, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Technical Normalization — controls and boundaries
For technical normalization, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Technical Normalization — evidence and live-data requirements
The department should prove work on technical normalization through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Commercial Normalization — operating knowledge
Marketplace Operations must understand commercial normalization as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Commercial Normalization — how the department uses it
When work involves commercial normalization, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Commercial Normalization — controls and boundaries
For commercial normalization, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Commercial Normalization — evidence and live-data requirements
The department should prove work on commercial normalization through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Quote Completeness — operating knowledge
Marketplace Operations must understand quote completeness as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Quote Completeness — how the department uses it
When work involves quote completeness, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Quote Completeness — controls and boundaries
For quote completeness, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Quote Completeness — evidence and live-data requirements
The department should prove work on quote completeness through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Deviation Detection — operating knowledge
Marketplace Operations must understand deviation detection as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Deviation Detection — how the department uses it
When work involves deviation detection, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Deviation Detection — controls and boundaries
For deviation detection, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Deviation Detection — evidence and live-data requirements
The department should prove work on deviation detection through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Ranking — operating knowledge
Marketplace Operations must understand supplier ranking as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Ranking — how the department uses it
When work involves supplier ranking, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Ranking — controls and boundaries
For supplier ranking, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Ranking — evidence and live-data requirements
The department should prove work on supplier ranking through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Top-Three Recommendation — operating knowledge
Marketplace Operations must understand top-three recommendation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Top-Three Recommendation — how the department uses it
When work involves top-three recommendation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Top-Three Recommendation — controls and boundaries
For top-three recommendation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Top-Three Recommendation — evidence and live-data requirements
The department should prove work on top-three recommendation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Award Workflow — operating knowledge
Marketplace Operations must understand award workflow as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Award Workflow — how the department uses it
When work involves award workflow, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Award Workflow — controls and boundaries
For award workflow, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Award Workflow — evidence and live-data requirements
The department should prove work on award workflow through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Marketplace Policies — operating knowledge
Marketplace Operations must understand marketplace policies as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Marketplace Policies — how the department uses it
When work involves marketplace policies, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Marketplace Policies — controls and boundaries
For marketplace policies, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Marketplace Policies — evidence and live-data requirements
The department should prove work on marketplace policies through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Customer Ranking — operating knowledge
Marketplace Operations must understand customer ranking as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Customer Ranking — how the department uses it
When work involves customer ranking, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Customer Ranking — controls and boundaries
For customer ranking, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Customer Ranking — evidence and live-data requirements
The department should prove work on customer ranking through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Response Rates — operating knowledge
Marketplace Operations must understand supplier response rates as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Response Rates — how the department uses it
When work involves supplier response rates, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Response Rates — controls and boundaries
For supplier response rates, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Response Rates — evidence and live-data requirements
The department should prove work on supplier response rates through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Duplicate Dispatch Prevention — operating knowledge
Marketplace Operations must understand duplicate dispatch prevention as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Duplicate Dispatch Prevention — how the department uses it
When work involves duplicate dispatch prevention, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Duplicate Dispatch Prevention — controls and boundaries
For duplicate dispatch prevention, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Duplicate Dispatch Prevention — evidence and live-data requirements
The department should prove work on duplicate dispatch prevention through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Coverage Gaps — operating knowledge
Marketplace Operations must understand coverage gaps as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Coverage Gaps — how the department uses it
When work involves coverage gaps, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Coverage Gaps — controls and boundaries
For coverage gaps, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Coverage Gaps — evidence and live-data requirements
The department should prove work on coverage gaps through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Reveal Workflow — operating knowledge
Marketplace Operations must understand reveal workflow as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Reveal Workflow — how the department uses it
When work involves reveal workflow, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Reveal Workflow — controls and boundaries
For reveal workflow, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Reveal Workflow — evidence and live-data requirements
The department should prove work on reveal workflow through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Marketplace Quality — operating knowledge
Marketplace Operations must understand marketplace quality as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Run matching, quotation collection, comparison, ranking, award and reveal operations fairly, transparently and with measurable marketplace quality. — and contribute to the north-star outcome: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Marketplace Quality — how the department uses it
When work involves marketplace quality, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Marketplace Quality — controls and boundaries
For marketplace quality, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Marketplace Quality — evidence and live-data requirements
The department should prove work on marketplace quality through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_matches, quotes, quote_items, quote_committed_items, quote_reviews, quote_comparisons, qd_compare_cache, match_eval_runs. Candidate execution evidence includes: match, match_eval, dispatch_inquiry, quote_extract, quote_review, quote_quality, quote_compare, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — Supplier Matching
This SOP governs supplier matching for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 02 — Inquiry Dispatch
This SOP governs inquiry dispatch for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 03 — Quotation Receipt
This SOP governs quotation receipt for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 04 — Quotation Extraction
This SOP governs quotation extraction for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 05 — Technical Review
This SOP governs technical review for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 06 — Comparison And Scoring
This SOP governs comparison and scoring for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 07 — Top-Three Recommendation
This SOP governs top-three recommendation for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 08 — Award And Reveal
This SOP governs award and reveal for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 09 — Marketplace Exception Review
This SOP governs marketplace exception review for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

### SOP 10 — Coverage-Gap Escalation
This SOP governs coverage-gap escalation for Marketplace Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

Steps:
1. Receive or detect the triggering event and assign a stable case or entity identifier.
2. Confirm the current workflow state, owner, service level and any open duplicate task.
3. Retrieve the minimum required live data and documents using least-privilege access.
4. Validate mandatory fields, evidence freshness, consent and applicable policy or jurisdiction.
5. Apply deterministic rules first; use an AI model only for language interpretation or an uncovered exception.
6. Produce the defined output in a structured format and attach evidence, assumptions, confidence and unresolved gaps.
7. If authority, confidence or evidence is insufficient, hold the action and create an escalation with a specific decision request.
8. Execute only within the department's authority tier and approved thresholds.
9. Record the action, result, downstream handoff and rollback reference in the audit trail.
10. Measure the outcome, close or retry the task, and propose a knowledge or process improvement when a recurring gap is found.

## Decision rules
### Marketplace Operations rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Marketplace Operations rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The Marketplace Operations agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### Marketplace Operations exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Marketplace Operations exception 10 — Repeated workflow failure
Open an incident and root-cause task, disable unsafe automation if needed, use the manual safe path and update tests before re-enabling. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

## KPI definitions
### Work completion rate
Completed owned tasks divided by tasks due in the period. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### SLA compliance
Cases completed within the department SLA divided by completed cases. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### Rework rate
Cases reopened, corrected or overridden after completion divided by completed cases. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### Exception rate
Cases requiring escalation divided by cases processed; interpret with severity and policy context. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### Automation coverage
Eligible cases completed through approved automation divided by eligible cases. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### Evidence completeness
Completed cases with all mandatory evidence and audit references divided by completed cases. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### Cost per completed case
Direct provider, model and operational cost divided by completed cases. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### Outcome quality
Department-specific outcome score linked to the stated north-star metric. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

### North-star — Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: Relevant suppliers respond quickly and customers receive auditable apples-to-apples comparisons.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### Marketplace Operations Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the marketplace_operations knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Marketplace Operations Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the marketplace_operations knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Marketplace Operations Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the marketplace_operations knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Marketplace Operations Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the marketplace_operations knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `match` — found_in_production_export — functions/match.md
- **backend_function** `match_eval` — found_in_production_export — functions/match_eval.md
- **backend_function** `dispatch_inquiry` — found_in_production_export — functions/dispatch_inquiry.md
- **backend_function** `quote_extract` — found_in_production_export — functions/quote_extract.md
- **backend_function** `quote_review` — found_in_production_export — functions/quote_review.md
- **backend_function** `quote_quality` — found_in_production_export — functions/quote_quality.md
- **backend_function** `quote_compare` — found_in_production_export — functions/quote_compare.md
- **backend_function** `quote_pdf` — found_in_production_export — functions/quote_pdf.md
- **backend_function** `rate_dims` — found_in_production_export — functions/rate_dims.md
- **backend_function** `stripe_checkout` — found_in_production_export — functions/stripe_checkout.md
- **database_object** `inquiry_matches` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quotes` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_items` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_committed_items` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_reviews` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_comparisons` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `qd_compare_cache` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `match_eval_runs` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `reviews` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `supplier_score` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `customer_score` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `reveal_invoices` — found_in_schema — database/schema-tables-and-views.md
- **migration** `20260607093502_marketplace_core_schema` — found_in_production_export — migrations/20260607093502_marketplace_core_schema.md
- **migration** `20260706003936_marketplace_analytics` — found_in_production_export — migrations/20260706003936_marketplace_analytics.md
- **migration** `20260706102146_marketplace_health_index` — found_in_production_export — migrations/20260706102146_marketplace_health_index.md
- **migration** `20260709100208_ws_operations_add_security_block` — found_in_production_export — migrations/20260709100208_ws_operations_add_security_block.md
- **migration** `20260709100608_operations_kpis_and_agent` — found_in_production_export — migrations/20260709100608_operations_kpis_and_agent.md
- **migration** `20260709100715_ws_operations_add_ops_block` — found_in_production_export — migrations/20260709100715_ws_operations_add_ops_block.md
- **migration** `20260710214222_marketplace_intelligence_views` — found_in_production_export — migrations/20260710214222_marketplace_intelligence_views.md
- **migration** `20260728193744_reputation_maturity_energy_and_marketplace_health` — found_in_production_export — migrations/20260728193744_reputation_maturity_energy_and_marketplace_health.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.