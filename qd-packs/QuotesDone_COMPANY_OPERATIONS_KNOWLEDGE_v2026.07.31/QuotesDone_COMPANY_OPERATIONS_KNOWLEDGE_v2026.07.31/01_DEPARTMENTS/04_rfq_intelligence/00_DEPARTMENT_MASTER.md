# RFQ / Inquiry Intelligence — Operating Knowledge Pack

**Department key:** `rfq_intelligence`  
**Production mapping:** procurement  
**Implementation assessment:** `implemented`  
**Version:** 1.0.0  

## Charter
Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief.

## North-star outcome
Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth.

## Core knowledge domains
1. inquiry routing
2. supplier taxonomy
3. subcategory aliases
4. intent classification
5. ordinary-language interpretation
6. RFQ qualification
7. mandatory fields
8. conditional questions
9. missing-information detection
10. document analysis
11. drawing analysis
12. BOQ analysis
13. attachment validation
14. inquiry scoring
15. legitimacy checks
16. contact-detail redaction
17. structured brief generation
18. multi-category splitting
19. supplier requirements
20. completion confidence

## Owned workflows
1. new inquiry intake
2. intent and category routing
3. follow-up question sequencing
4. document extraction
5. drawing and BOQ analysis
6. identity redaction
7. completeness gate
8. multi-trade split
9. supplier-safe package generation
10. dispatch eligibility

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Inquiry Routing — operating knowledge
RFQ / Inquiry Intelligence must understand inquiry routing as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Inquiry Routing — how the department uses it
When work involves inquiry routing, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Inquiry Routing — controls and boundaries
For inquiry routing, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Inquiry Routing — evidence and live-data requirements
The department should prove work on inquiry routing through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Taxonomy — operating knowledge
RFQ / Inquiry Intelligence must understand supplier taxonomy as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Taxonomy — how the department uses it
When work involves supplier taxonomy, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Taxonomy — controls and boundaries
For supplier taxonomy, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Taxonomy — evidence and live-data requirements
The department should prove work on supplier taxonomy through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Subcategory Aliases — operating knowledge
RFQ / Inquiry Intelligence must understand subcategory aliases as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Subcategory Aliases — how the department uses it
When work involves subcategory aliases, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Subcategory Aliases — controls and boundaries
For subcategory aliases, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Subcategory Aliases — evidence and live-data requirements
The department should prove work on subcategory aliases through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Intent Classification — operating knowledge
RFQ / Inquiry Intelligence must understand intent classification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Intent Classification — how the department uses it
When work involves intent classification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Intent Classification — controls and boundaries
For intent classification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Intent Classification — evidence and live-data requirements
The department should prove work on intent classification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Ordinary-Language Interpretation — operating knowledge
RFQ / Inquiry Intelligence must understand ordinary-language interpretation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Ordinary-Language Interpretation — how the department uses it
When work involves ordinary-language interpretation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Ordinary-Language Interpretation — controls and boundaries
For ordinary-language interpretation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Ordinary-Language Interpretation — evidence and live-data requirements
The department should prove work on ordinary-language interpretation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Rfq Qualification — operating knowledge
RFQ / Inquiry Intelligence must understand RFQ qualification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Rfq Qualification — how the department uses it
When work involves RFQ qualification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Rfq Qualification — controls and boundaries
For RFQ qualification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Rfq Qualification — evidence and live-data requirements
The department should prove work on RFQ qualification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Mandatory Fields — operating knowledge
RFQ / Inquiry Intelligence must understand mandatory fields as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Mandatory Fields — how the department uses it
When work involves mandatory fields, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Mandatory Fields — controls and boundaries
For mandatory fields, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Mandatory Fields — evidence and live-data requirements
The department should prove work on mandatory fields through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Conditional Questions — operating knowledge
RFQ / Inquiry Intelligence must understand conditional questions as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Conditional Questions — how the department uses it
When work involves conditional questions, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Conditional Questions — controls and boundaries
For conditional questions, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Conditional Questions — evidence and live-data requirements
The department should prove work on conditional questions through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Missing-Information Detection — operating knowledge
RFQ / Inquiry Intelligence must understand missing-information detection as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Missing-Information Detection — how the department uses it
When work involves missing-information detection, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Missing-Information Detection — controls and boundaries
For missing-information detection, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Missing-Information Detection — evidence and live-data requirements
The department should prove work on missing-information detection through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Document Analysis — operating knowledge
RFQ / Inquiry Intelligence must understand document analysis as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Document Analysis — how the department uses it
When work involves document analysis, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Document Analysis — controls and boundaries
For document analysis, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Document Analysis — evidence and live-data requirements
The department should prove work on document analysis through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Drawing Analysis — operating knowledge
RFQ / Inquiry Intelligence must understand drawing analysis as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Drawing Analysis — how the department uses it
When work involves drawing analysis, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Drawing Analysis — controls and boundaries
For drawing analysis, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Drawing Analysis — evidence and live-data requirements
The department should prove work on drawing analysis through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Boq Analysis — operating knowledge
RFQ / Inquiry Intelligence must understand BOQ analysis as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Boq Analysis — how the department uses it
When work involves BOQ analysis, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Boq Analysis — controls and boundaries
For BOQ analysis, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Boq Analysis — evidence and live-data requirements
The department should prove work on BOQ analysis through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Attachment Validation — operating knowledge
RFQ / Inquiry Intelligence must understand attachment validation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Attachment Validation — how the department uses it
When work involves attachment validation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Attachment Validation — controls and boundaries
For attachment validation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Attachment Validation — evidence and live-data requirements
The department should prove work on attachment validation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Inquiry Scoring — operating knowledge
RFQ / Inquiry Intelligence must understand inquiry scoring as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Inquiry Scoring — how the department uses it
When work involves inquiry scoring, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Inquiry Scoring — controls and boundaries
For inquiry scoring, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Inquiry Scoring — evidence and live-data requirements
The department should prove work on inquiry scoring through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Legitimacy Checks — operating knowledge
RFQ / Inquiry Intelligence must understand legitimacy checks as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Legitimacy Checks — how the department uses it
When work involves legitimacy checks, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Legitimacy Checks — controls and boundaries
For legitimacy checks, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Legitimacy Checks — evidence and live-data requirements
The department should prove work on legitimacy checks through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Contact-Detail Redaction — operating knowledge
RFQ / Inquiry Intelligence must understand contact-detail redaction as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Contact-Detail Redaction — how the department uses it
When work involves contact-detail redaction, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Contact-Detail Redaction — controls and boundaries
For contact-detail redaction, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Contact-Detail Redaction — evidence and live-data requirements
The department should prove work on contact-detail redaction through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Structured Brief Generation — operating knowledge
RFQ / Inquiry Intelligence must understand structured brief generation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Structured Brief Generation — how the department uses it
When work involves structured brief generation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Structured Brief Generation — controls and boundaries
For structured brief generation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Structured Brief Generation — evidence and live-data requirements
The department should prove work on structured brief generation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Multi-Category Splitting — operating knowledge
RFQ / Inquiry Intelligence must understand multi-category splitting as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Multi-Category Splitting — how the department uses it
When work involves multi-category splitting, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Multi-Category Splitting — controls and boundaries
For multi-category splitting, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Multi-Category Splitting — evidence and live-data requirements
The department should prove work on multi-category splitting through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Requirements — operating knowledge
RFQ / Inquiry Intelligence must understand supplier requirements as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Requirements — how the department uses it
When work involves supplier requirements, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Requirements — controls and boundaries
For supplier requirements, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Requirements — evidence and live-data requirements
The department should prove work on supplier requirements through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Completion Confidence — operating knowledge
RFQ / Inquiry Intelligence must understand completion confidence as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Interpret ordinary customer language, route it to the correct supplier domain, extract available evidence, ask only necessary follow-up questions and create a complete, legitimate, privacy-safe supplier brief. — and contribute to the north-star outcome: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Completion Confidence — how the department uses it
When work involves completion confidence, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Completion Confidence — controls and boundaries
For completion confidence, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Completion Confidence — evidence and live-data requirements
The department should prove work on completion confidence through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: inquiry_intake, inquiries, inquiry_requirement, category_specs, category_quote_specs, questions, qualification_playbooks, subcategory_agent_map. Candidate execution evidence includes: inquiry_ai, inquiry_intake, inquiry_parse, intent_router, route_inquiry, doc_extract, drawing_boq, drawing_redact. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — New Inquiry Intake
This SOP governs new inquiry intake for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 02 — Intent And Category Routing
This SOP governs intent and category routing for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 03 — Follow-Up Question Sequencing
This SOP governs follow-up question sequencing for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 04 — Document Extraction
This SOP governs document extraction for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 05 — Drawing And Boq Analysis
This SOP governs drawing and BOQ analysis for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 06 — Identity Redaction
This SOP governs identity redaction for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 07 — Completeness Gate
This SOP governs completeness gate for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 08 — Multi-Trade Split
This SOP governs multi-trade split for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 09 — Supplier-Safe Package Generation
This SOP governs supplier-safe package generation for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 10 — Dispatch Eligibility
This SOP governs dispatch eligibility for RFQ / Inquiry Intelligence. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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
### RFQ / Inquiry Intelligence rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

### RFQ / Inquiry Intelligence rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The RFQ / Inquiry Intelligence agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### RFQ / Inquiry Intelligence exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### RFQ / Inquiry Intelligence exception 10 — Repeated workflow failure
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

### North-star — Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: Quote-ready inquiries with high completeness, accurate category routing and no unnecessary customer-supplier back-and-forth.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### RFQ / Inquiry Intelligence Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the rfq_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### RFQ / Inquiry Intelligence Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the rfq_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### RFQ / Inquiry Intelligence Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the rfq_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### RFQ / Inquiry Intelligence Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the rfq_intelligence knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `inquiry_ai` — found_in_production_export — functions/inquiry_ai.md
- **backend_function** `inquiry_intake` — found_in_production_export — functions/inquiry_intake.md
- **backend_function** `inquiry_parse` — found_in_production_export — functions/inquiry_parse.md
- **backend_function** `intent_router` — found_in_production_export — functions/intent_router.md
- **backend_function** `route_inquiry` — found_in_production_export — functions/route_inquiry.md
- **backend_function** `doc_extract` — found_in_production_export — functions/doc_extract.md
- **backend_function** `drawing_boq` — found_in_production_export — functions/drawing_boq.md
- **backend_function** `drawing_redact` — found_in_production_export — functions/drawing_redact.md
- **backend_function** `dispatch_inquiry` — found_in_production_export — functions/dispatch_inquiry.md
- **backend_function** `category_reqs` — found_in_production_export — functions/category_reqs.md
- **database_object** `inquiry_intake` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `inquiries` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `inquiry_requirement` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `category_specs` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `category_quote_specs` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `questions` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `qualification_playbooks` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `subcategory_agent_map` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `category_agent_map` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `kb_category_aliases` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `quote_requirements` — found_in_schema — database/schema-tables-and-views.md
- **migration** `20260706021848_executive_intelligence_layer` — found_in_production_export — migrations/20260706021848_executive_intelligence_layer.md
- **migration** `20260706102534_document_intelligence_registry` — found_in_production_export — migrations/20260706102534_document_intelligence_registry.md
- **migration** `20260706105057_rfq_archive_lifecycle` — found_in_production_export — migrations/20260706105057_rfq_archive_lifecycle.md
- **migration** `20260706110043_rfq_inquiry_versioning` — found_in_production_export — migrations/20260706110043_rfq_inquiry_versioning.md
- **migration** `20260706115127_rfq_completeness_gate_v2` — found_in_production_export — migrations/20260706115127_rfq_completeness_gate_v2.md
- **migration** `20260708114138_erp_ws_rfq_360` — found_in_production_export — migrations/20260708114138_erp_ws_rfq_360.md
- **migration** `20260708131431_rfq_qualification_gate_and_clarify` — found_in_production_export — migrations/20260708131431_rfq_qualification_gate_and_clarify.md
- **migration** `20260710214222_marketplace_intelligence_views` — found_in_production_export — migrations/20260710214222_marketplace_intelligence_views.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.