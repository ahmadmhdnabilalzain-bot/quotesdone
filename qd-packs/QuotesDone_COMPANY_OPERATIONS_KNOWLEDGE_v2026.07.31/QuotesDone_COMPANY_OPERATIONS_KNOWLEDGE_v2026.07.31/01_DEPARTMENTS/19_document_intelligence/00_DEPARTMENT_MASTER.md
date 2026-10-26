# Document Intelligence — Operating Knowledge Pack

**Department key:** `document_intelligence`  
**Production mapping:** procurement, knowledge_eng  
**Implementation assessment:** `partial`  
**Version:** 1.0.0  

## Charter
Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows.

## North-star outcome
Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls.

## Core knowledge domains
1. document classification
2. PDF extraction
3. OCR
4. BOQ extraction
5. CAD and drawing handling
6. image understanding
7. datasheets
8. technical specifications
9. contracts
10. quotation extraction
11. version control
12. document validation
13. metadata
14. malware and file safety
15. contact-detail redaction
16. duplicate detection
17. confidence scoring
18. human review
19. source lineage
20. archiving

## Owned workflows
1. file intake
2. file classification
3. text extraction
4. BOQ extraction
5. drawing analysis
6. quotation extraction
7. redaction
8. version comparison
9. document review
10. archive and retrieval

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Document Classification — operating knowledge
Document Intelligence must understand document classification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Document Classification — how the department uses it
When work involves document classification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Document Classification — controls and boundaries
For document classification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Document Classification — evidence and live-data requirements
The department should prove work on document classification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Pdf Extraction — operating knowledge
Document Intelligence must understand PDF extraction as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Pdf Extraction — how the department uses it
When work involves PDF extraction, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Pdf Extraction — controls and boundaries
For PDF extraction, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Pdf Extraction — evidence and live-data requirements
The department should prove work on PDF extraction through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Ocr — operating knowledge
Document Intelligence must understand OCR as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Ocr — how the department uses it
When work involves OCR, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Ocr — controls and boundaries
For OCR, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Ocr — evidence and live-data requirements
The department should prove work on OCR through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Boq Extraction — operating knowledge
Document Intelligence must understand BOQ extraction as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Boq Extraction — how the department uses it
When work involves BOQ extraction, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Boq Extraction — controls and boundaries
For BOQ extraction, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Boq Extraction — evidence and live-data requirements
The department should prove work on BOQ extraction through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Cad And Drawing Handling — operating knowledge
Document Intelligence must understand CAD and drawing handling as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Cad And Drawing Handling — how the department uses it
When work involves CAD and drawing handling, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Cad And Drawing Handling — controls and boundaries
For CAD and drawing handling, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Cad And Drawing Handling — evidence and live-data requirements
The department should prove work on CAD and drawing handling through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Image Understanding — operating knowledge
Document Intelligence must understand image understanding as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Image Understanding — how the department uses it
When work involves image understanding, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Image Understanding — controls and boundaries
For image understanding, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Image Understanding — evidence and live-data requirements
The department should prove work on image understanding through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Datasheets — operating knowledge
Document Intelligence must understand datasheets as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Datasheets — how the department uses it
When work involves datasheets, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Datasheets — controls and boundaries
For datasheets, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Datasheets — evidence and live-data requirements
The department should prove work on datasheets through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Technical Specifications — operating knowledge
Document Intelligence must understand technical specifications as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Technical Specifications — how the department uses it
When work involves technical specifications, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Technical Specifications — controls and boundaries
For technical specifications, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Technical Specifications — evidence and live-data requirements
The department should prove work on technical specifications through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Contracts — operating knowledge
Document Intelligence must understand contracts as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Contracts — how the department uses it
When work involves contracts, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Contracts — controls and boundaries
For contracts, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Contracts — evidence and live-data requirements
The department should prove work on contracts through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Quotation Extraction — operating knowledge
Document Intelligence must understand quotation extraction as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Quotation Extraction — how the department uses it
When work involves quotation extraction, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Quotation Extraction — controls and boundaries
For quotation extraction, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Quotation Extraction — evidence and live-data requirements
The department should prove work on quotation extraction through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Version Control — operating knowledge
Document Intelligence must understand version control as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Version Control — how the department uses it
When work involves version control, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Version Control — controls and boundaries
For version control, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Version Control — evidence and live-data requirements
The department should prove work on version control through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Document Validation — operating knowledge
Document Intelligence must understand document validation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Document Validation — how the department uses it
When work involves document validation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Document Validation — controls and boundaries
For document validation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Document Validation — evidence and live-data requirements
The department should prove work on document validation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Metadata — operating knowledge
Document Intelligence must understand metadata as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Metadata — how the department uses it
When work involves metadata, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Metadata — controls and boundaries
For metadata, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Metadata — evidence and live-data requirements
The department should prove work on metadata through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Malware And File Safety — operating knowledge
Document Intelligence must understand malware and file safety as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Malware And File Safety — how the department uses it
When work involves malware and file safety, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Malware And File Safety — controls and boundaries
For malware and file safety, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Malware And File Safety — evidence and live-data requirements
The department should prove work on malware and file safety through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Contact-Detail Redaction — operating knowledge
Document Intelligence must understand contact-detail redaction as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Contact-Detail Redaction — how the department uses it
When work involves contact-detail redaction, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Contact-Detail Redaction — controls and boundaries
For contact-detail redaction, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Contact-Detail Redaction — evidence and live-data requirements
The department should prove work on contact-detail redaction through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Duplicate Detection — operating knowledge
Document Intelligence must understand duplicate detection as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Duplicate Detection — how the department uses it
When work involves duplicate detection, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Duplicate Detection — controls and boundaries
For duplicate detection, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Duplicate Detection — evidence and live-data requirements
The department should prove work on duplicate detection through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Confidence Scoring — operating knowledge
Document Intelligence must understand confidence scoring as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Confidence Scoring — how the department uses it
When work involves confidence scoring, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Confidence Scoring — controls and boundaries
For confidence scoring, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Confidence Scoring — evidence and live-data requirements
The department should prove work on confidence scoring through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Human Review — operating knowledge
Document Intelligence must understand human review as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Human Review — how the department uses it
When work involves human review, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Human Review — controls and boundaries
For human review, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Human Review — evidence and live-data requirements
The department should prove work on human review through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Source Lineage — operating knowledge
Document Intelligence must understand source lineage as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Source Lineage — how the department uses it
When work involves source lineage, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Source Lineage — controls and boundaries
For source lineage, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Source Lineage — evidence and live-data requirements
The department should prove work on source lineage through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Archiving — operating knowledge
Document Intelligence must understand archiving as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Classify, extract, validate, compare, redact and version documents so information can move safely into operational workflows. — and contribute to the north-star outcome: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Archiving — how the department uses it
When work involves archiving, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Archiving — controls and boundaries
For archiving, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Archiving — evidence and live-data requirements
The department should prove work on archiving through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: documents, doc_versions, doc_reviews, doc_backups, dropbox_files, quote_items, quote_reviews, rfq_archives. Candidate execution evidence includes: doc_extract, extract_text, drawing_boq, drawing_redact, quote_extract, doc_render, cad_convert, pdf_native. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — File Intake
This SOP governs file intake for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 02 — File Classification
This SOP governs file classification for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 03 — Text Extraction
This SOP governs text extraction for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 04 — Boq Extraction
This SOP governs BOQ extraction for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 05 — Drawing Analysis
This SOP governs drawing analysis for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 06 — Quotation Extraction
This SOP governs quotation extraction for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 07 — Redaction
This SOP governs redaction for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 08 — Version Comparison
This SOP governs version comparison for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 09 — Document Review
This SOP governs document review for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 10 — Archive And Retrieval
This SOP governs archive and retrieval for Document Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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
### Document Intelligence rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### Document Intelligence rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The Document Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### Document Intelligence exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Document Intelligence exception 10 — Repeated workflow failure
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

### North-star — Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: Uploaded files become trustworthy structured data with preserved lineage, version and privacy controls.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### Document Intelligence Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the document_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Document Intelligence Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the document_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Document Intelligence Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the document_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Document Intelligence Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the document_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `doc_extract` — found_in_production_export — functions/doc_extract.md
- **backend_function** `extract_text` — found_in_production_export — functions/extract_text.md
- **backend_function** `drawing_boq` — found_in_production_export — functions/drawing_boq.md
- **backend_function** `drawing_redact` — found_in_production_export — functions/drawing_redact.md
- **backend_function** `quote_extract` — found_in_production_export — functions/quote_extract.md
- **backend_function** `doc_render` — found_in_production_export — functions/doc_render.md
- **backend_function** `cad_convert` — found_in_production_export — functions/cad_convert.md
- **backend_function** `pdf_native` — found_in_production_export — functions/pdf_native.md
- **backend_function** `dropbox_sync` — found_in_production_export — functions/dropbox_sync.md
- **backend_function** `compliance_archive` — found_in_production_export — functions/compliance_archive.md
- **database_object** `documents` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `doc_versions` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `doc_reviews` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `doc_backups` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `dropbox_files` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_items` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_reviews` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `rfq_archives` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `legal_documents` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `pdpl_erase_files` — found_in_schema — database/schema-tables-and-views.md
- **migration** `20260706102534_document_intelligence_registry` — found_in_production_export — migrations/20260706102534_document_intelligence_registry.md
- **migration** `20260706021848_executive_intelligence_layer` — found_in_production_export — migrations/20260706021848_executive_intelligence_layer.md
- **migration** `20260706105544_document_versioning` — found_in_production_export — migrations/20260706105544_document_versioning.md
- **migration** `20260709102030_document_controller_inventory_kpis` — found_in_production_export — migrations/20260709102030_document_controller_inventory_kpis.md
- **migration** `20260709102127_fn_document_controller_agent` — found_in_production_export — migrations/20260709102127_fn_document_controller_agent.md
- **migration** `20260709102238_ws_documents_add_controller_block` — found_in_production_export — migrations/20260709102238_ws_documents_add_controller_block.md
- **migration** `20260710214222_marketplace_intelligence_views` — found_in_production_export — migrations/20260710214222_marketplace_intelligence_views.md
- **migration** `20260726232912_innovation_and_intelligence` — found_in_production_export — migrations/20260726232912_innovation_and_intelligence.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.