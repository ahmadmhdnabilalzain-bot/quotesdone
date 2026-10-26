# Trust & Safety — Operating Knowledge Pack

**Department key:** `trust_safety`  
**Production mapping:** supplier_success, customer_success, legal  
**Implementation assessment:** `partial`  
**Version:** 1.0.0  

## Charter
Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes.

## North-star outcome
High marketplace trust with low fraud, low false-positive harm and traceable enforcement.

## Core knowledge domains
1. fraud detection
2. spam prevention
3. identity verification
4. supplier verification
5. customer verification
6. fake RFQs
7. fake suppliers
8. content moderation
9. abuse detection
10. risk scoring
11. disposable domains
12. duplicate accounts
13. suspicious payments
14. document fraud
15. sanctions and restrictions
16. appeals
17. audit logs
18. privacy
19. enforcement consistency
20. incident reporting

## Owned workflows
1. signup risk screening
2. supplier document fraud check
3. inquiry legitimacy screening
4. content moderation
5. payment fraud review
6. account restriction
7. supplier suspension
8. appeal review
9. abuse incident
10. risk-model review

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Fraud Detection — operating knowledge
Trust & Safety must understand fraud detection as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Fraud Detection — how the department uses it
When work involves fraud detection, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Fraud Detection — controls and boundaries
For fraud detection, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Fraud Detection — evidence and live-data requirements
The department should prove work on fraud detection through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Spam Prevention — operating knowledge
Trust & Safety must understand spam prevention as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Spam Prevention — how the department uses it
When work involves spam prevention, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Spam Prevention — controls and boundaries
For spam prevention, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Spam Prevention — evidence and live-data requirements
The department should prove work on spam prevention through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Identity Verification — operating knowledge
Trust & Safety must understand identity verification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Identity Verification — how the department uses it
When work involves identity verification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Identity Verification — controls and boundaries
For identity verification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Identity Verification — evidence and live-data requirements
The department should prove work on identity verification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Verification — operating knowledge
Trust & Safety must understand supplier verification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Verification — how the department uses it
When work involves supplier verification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Verification — controls and boundaries
For supplier verification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Verification — evidence and live-data requirements
The department should prove work on supplier verification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Customer Verification — operating knowledge
Trust & Safety must understand customer verification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Customer Verification — how the department uses it
When work involves customer verification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Customer Verification — controls and boundaries
For customer verification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Customer Verification — evidence and live-data requirements
The department should prove work on customer verification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Fake Rfqs — operating knowledge
Trust & Safety must understand fake RFQs as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Fake Rfqs — how the department uses it
When work involves fake RFQs, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Fake Rfqs — controls and boundaries
For fake RFQs, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Fake Rfqs — evidence and live-data requirements
The department should prove work on fake RFQs through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Fake Suppliers — operating knowledge
Trust & Safety must understand fake suppliers as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Fake Suppliers — how the department uses it
When work involves fake suppliers, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Fake Suppliers — controls and boundaries
For fake suppliers, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Fake Suppliers — evidence and live-data requirements
The department should prove work on fake suppliers through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Content Moderation — operating knowledge
Trust & Safety must understand content moderation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Content Moderation — how the department uses it
When work involves content moderation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Content Moderation — controls and boundaries
For content moderation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Content Moderation — evidence and live-data requirements
The department should prove work on content moderation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Abuse Detection — operating knowledge
Trust & Safety must understand abuse detection as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Abuse Detection — how the department uses it
When work involves abuse detection, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Abuse Detection — controls and boundaries
For abuse detection, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Abuse Detection — evidence and live-data requirements
The department should prove work on abuse detection through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Risk Scoring — operating knowledge
Trust & Safety must understand risk scoring as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Risk Scoring — how the department uses it
When work involves risk scoring, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Risk Scoring — controls and boundaries
For risk scoring, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Risk Scoring — evidence and live-data requirements
The department should prove work on risk scoring through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Disposable Domains — operating knowledge
Trust & Safety must understand disposable domains as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Disposable Domains — how the department uses it
When work involves disposable domains, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Disposable Domains — controls and boundaries
For disposable domains, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Disposable Domains — evidence and live-data requirements
The department should prove work on disposable domains through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Duplicate Accounts — operating knowledge
Trust & Safety must understand duplicate accounts as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Duplicate Accounts — how the department uses it
When work involves duplicate accounts, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Duplicate Accounts — controls and boundaries
For duplicate accounts, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Duplicate Accounts — evidence and live-data requirements
The department should prove work on duplicate accounts through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Suspicious Payments — operating knowledge
Trust & Safety must understand suspicious payments as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Suspicious Payments — how the department uses it
When work involves suspicious payments, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Suspicious Payments — controls and boundaries
For suspicious payments, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Suspicious Payments — evidence and live-data requirements
The department should prove work on suspicious payments through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Document Fraud — operating knowledge
Trust & Safety must understand document fraud as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Document Fraud — how the department uses it
When work involves document fraud, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Document Fraud — controls and boundaries
For document fraud, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Document Fraud — evidence and live-data requirements
The department should prove work on document fraud through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Sanctions And Restrictions — operating knowledge
Trust & Safety must understand sanctions and restrictions as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Sanctions And Restrictions — how the department uses it
When work involves sanctions and restrictions, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Sanctions And Restrictions — controls and boundaries
For sanctions and restrictions, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Sanctions And Restrictions — evidence and live-data requirements
The department should prove work on sanctions and restrictions through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Appeals — operating knowledge
Trust & Safety must understand appeals as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Appeals — how the department uses it
When work involves appeals, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Appeals — controls and boundaries
For appeals, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Appeals — evidence and live-data requirements
The department should prove work on appeals through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Audit Logs — operating knowledge
Trust & Safety must understand audit logs as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Audit Logs — how the department uses it
When work involves audit logs, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Audit Logs — controls and boundaries
For audit logs, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Audit Logs — evidence and live-data requirements
The department should prove work on audit logs through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Privacy — operating knowledge
Trust & Safety must understand privacy as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Privacy — how the department uses it
When work involves privacy, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Privacy — controls and boundaries
For privacy, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Privacy — evidence and live-data requirements
The department should prove work on privacy through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Enforcement Consistency — operating knowledge
Trust & Safety must understand enforcement consistency as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Enforcement Consistency — how the department uses it
When work involves enforcement consistency, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Enforcement Consistency — controls and boundaries
For enforcement consistency, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Enforcement Consistency — evidence and live-data requirements
The department should prove work on enforcement consistency through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Incident Reporting — operating knowledge
Trust & Safety must understand incident reporting as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Prevent fraud, spam, fake suppliers, fake inquiries, abuse and unsafe content while preserving fair access and documented appeal routes. — and contribute to the north-star outcome: High marketplace trust with low fraud, low false-positive harm and traceable enforcement. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Incident Reporting — how the department uses it
When work involves incident reporting, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Incident Reporting — controls and boundaries
For incident reporting, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Incident Reporting — evidence and live-data requirements
The department should prove work on incident reporting through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: fraud_flags, chat_violations, app_blocked_domains, security_events, customer_score, supplier_score, reviews, audit_logs. Candidate execution evidence includes: kyc, inquiry_dedup_check, match_eval, supplier_review, qa_suite, customer_api, supplier_api. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — Signup Risk Screening
This SOP governs signup risk screening for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 02 — Supplier Document Fraud Check
This SOP governs supplier document fraud check for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 03 — Inquiry Legitimacy Screening
This SOP governs inquiry legitimacy screening for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 04 — Content Moderation
This SOP governs content moderation for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 05 — Payment Fraud Review
This SOP governs payment fraud review for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 06 — Account Restriction
This SOP governs account restriction for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 07 — Supplier Suspension
This SOP governs supplier suspension for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 08 — Appeal Review
This SOP governs appeal review for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 09 — Abuse Incident
This SOP governs abuse incident for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 10 — Risk-Model Review
This SOP governs risk-model review for Trust & Safety. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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
### Trust & Safety rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

### Trust & Safety rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The Trust & Safety agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### Trust & Safety exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Trust & Safety exception 10 — Repeated workflow failure
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

### North-star — High marketplace trust with low fraud, low false-positive harm and traceable enforcement.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: High marketplace trust with low fraud, low false-positive harm and traceable enforcement.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### Trust & Safety Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the trust_safety knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Trust & Safety Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the trust_safety knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Trust & Safety Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the trust_safety knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Trust & Safety Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the trust_safety knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `kyc` — found_in_production_export — functions/kyc.md
- **backend_function** `inquiry_dedup_check` — found_in_production_export — functions/inquiry_dedup_check.md
- **backend_function** `match_eval` — found_in_production_export — functions/match_eval.md
- **backend_function** `supplier_review` — found_in_production_export — functions/supplier_review.md
- **backend_function** `qa_suite` — found_in_production_export — functions/qa_suite.md
- **backend_function** `customer_api` — found_in_production_export — functions/customer_api.md
- **backend_function** `supplier_api` — found_in_production_export — functions/supplier_api.md
- **database_object** `fraud_flags` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `chat_violations` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `app_blocked_domains` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `security_events` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `customer_score` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `supplier_score` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `reviews` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `audit_logs` — not_found_by_exact_name — unresolved
- **database_object** `kyc` — not_found_by_exact_name — unresolved
- **database_object** `user_roles` — found_in_schema — database/schema-tables-and-views.md
- **migration** `20260727002128_trust_governance_ai_board_culture` — found_in_production_export — migrations/20260727002128_trust_governance_ai_board_culture.md
- **migration** `20260729141025_rfq_required_gate_keyless_field_safety` — found_in_production_export — migrations/20260729141025_rfq_required_gate_keyless_field_safety.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.