# Notification & Communications — Operating Knowledge Pack

**Department key:** `communications`  
**Production mapping:** No one-to-one production department key confirmed  
**Implementation assessment:** `partial`  
**Version:** 1.0.0  

## Charter
Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging.

## North-star outcome
Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls.

## Core knowledge domains
1. email operations
2. inbound email
3. outbound email
4. WhatsApp
5. SMS
6. push notifications
7. in-app messages
8. templates
9. localization
10. Arabic communication
11. consent
12. opt-out and suppression
13. bounce handling
14. complaint handling
15. rate limits
16. business hours
17. delivery status
18. retries
19. duplicate prevention
20. communication audit

## Owned workflows
1. transactional email
2. inbound email triage
3. WhatsApp send and receive
4. SMS send
5. template approval
6. suppression handling
7. delivery retry
8. campaign throttling
9. notification escalation
10. channel outage

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Email Operations — operating knowledge
Notification & Communications must understand email operations as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Email Operations — how the department uses it
When work involves email operations, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Email Operations — controls and boundaries
For email operations, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Email Operations — evidence and live-data requirements
The department should prove work on email operations through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Inbound Email — operating knowledge
Notification & Communications must understand inbound email as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Inbound Email — how the department uses it
When work involves inbound email, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Inbound Email — controls and boundaries
For inbound email, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Inbound Email — evidence and live-data requirements
The department should prove work on inbound email through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Outbound Email — operating knowledge
Notification & Communications must understand outbound email as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Outbound Email — how the department uses it
When work involves outbound email, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Outbound Email — controls and boundaries
For outbound email, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Outbound Email — evidence and live-data requirements
The department should prove work on outbound email through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Whatsapp — operating knowledge
Notification & Communications must understand WhatsApp as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Whatsapp — how the department uses it
When work involves WhatsApp, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Whatsapp — controls and boundaries
For WhatsApp, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Whatsapp — evidence and live-data requirements
The department should prove work on WhatsApp through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Sms — operating knowledge
Notification & Communications must understand SMS as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Sms — how the department uses it
When work involves SMS, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Sms — controls and boundaries
For SMS, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Sms — evidence and live-data requirements
The department should prove work on SMS through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Push Notifications — operating knowledge
Notification & Communications must understand push notifications as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Push Notifications — how the department uses it
When work involves push notifications, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Push Notifications — controls and boundaries
For push notifications, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Push Notifications — evidence and live-data requirements
The department should prove work on push notifications through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### In-App Messages — operating knowledge
Notification & Communications must understand in-app messages as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### In-App Messages — how the department uses it
When work involves in-app messages, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### In-App Messages — controls and boundaries
For in-app messages, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### In-App Messages — evidence and live-data requirements
The department should prove work on in-app messages through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Templates — operating knowledge
Notification & Communications must understand templates as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Templates — how the department uses it
When work involves templates, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Templates — controls and boundaries
For templates, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Templates — evidence and live-data requirements
The department should prove work on templates through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Localization — operating knowledge
Notification & Communications must understand localization as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Localization — how the department uses it
When work involves localization, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Localization — controls and boundaries
For localization, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Localization — evidence and live-data requirements
The department should prove work on localization through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Arabic Communication — operating knowledge
Notification & Communications must understand Arabic communication as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Arabic Communication — how the department uses it
When work involves Arabic communication, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Arabic Communication — controls and boundaries
For Arabic communication, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Arabic Communication — evidence and live-data requirements
The department should prove work on Arabic communication through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Consent — operating knowledge
Notification & Communications must understand consent as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Consent — how the department uses it
When work involves consent, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Consent — controls and boundaries
For consent, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Consent — evidence and live-data requirements
The department should prove work on consent through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Opt-Out And Suppression — operating knowledge
Notification & Communications must understand opt-out and suppression as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Opt-Out And Suppression — how the department uses it
When work involves opt-out and suppression, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Opt-Out And Suppression — controls and boundaries
For opt-out and suppression, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Opt-Out And Suppression — evidence and live-data requirements
The department should prove work on opt-out and suppression through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Bounce Handling — operating knowledge
Notification & Communications must understand bounce handling as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Bounce Handling — how the department uses it
When work involves bounce handling, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Bounce Handling — controls and boundaries
For bounce handling, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Bounce Handling — evidence and live-data requirements
The department should prove work on bounce handling through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Complaint Handling — operating knowledge
Notification & Communications must understand complaint handling as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Complaint Handling — how the department uses it
When work involves complaint handling, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Complaint Handling — controls and boundaries
For complaint handling, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Complaint Handling — evidence and live-data requirements
The department should prove work on complaint handling through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Rate Limits — operating knowledge
Notification & Communications must understand rate limits as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Rate Limits — how the department uses it
When work involves rate limits, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Rate Limits — controls and boundaries
For rate limits, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Rate Limits — evidence and live-data requirements
The department should prove work on rate limits through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Business Hours — operating knowledge
Notification & Communications must understand business hours as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Business Hours — how the department uses it
When work involves business hours, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Business Hours — controls and boundaries
For business hours, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Business Hours — evidence and live-data requirements
The department should prove work on business hours through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Delivery Status — operating knowledge
Notification & Communications must understand delivery status as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Delivery Status — how the department uses it
When work involves delivery status, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Delivery Status — controls and boundaries
For delivery status, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Delivery Status — evidence and live-data requirements
The department should prove work on delivery status through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Retries — operating knowledge
Notification & Communications must understand retries as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Retries — how the department uses it
When work involves retries, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Retries — controls and boundaries
For retries, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Retries — evidence and live-data requirements
The department should prove work on retries through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Duplicate Prevention — operating knowledge
Notification & Communications must understand duplicate prevention as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Duplicate Prevention — how the department uses it
When work involves duplicate prevention, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Duplicate Prevention — controls and boundaries
For duplicate prevention, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Duplicate Prevention — evidence and live-data requirements
The department should prove work on duplicate prevention through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Communication Audit — operating knowledge
Notification & Communications must understand communication audit as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Deliver accurate, consent-aware, traceable and resilient communications through email, WhatsApp, SMS, push and in-app messaging. — and contribute to the north-star outcome: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Communication Audit — how the department uses it
When work involves communication audit, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Communication Audit — controls and boundaries
For communication audit, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Communication Audit — evidence and live-data requirements
The department should prove work on communication audit through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: messages, inbound_messages, notifications, email_suppressions, email_block_pattern, event_delivery, outreach, response_template. Candidate execution evidence includes: inbound_email, email_triage, email_cron, send_whatsapp, send_sms, messages_api, pending_digest. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — Transactional Email
This SOP governs transactional email for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 02 — Inbound Email Triage
This SOP governs inbound email triage for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 03 — Whatsapp Send And Receive
This SOP governs WhatsApp send and receive for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 04 — Sms Send
This SOP governs SMS send for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 05 — Template Approval
This SOP governs template approval for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 06 — Suppression Handling
This SOP governs suppression handling for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 07 — Delivery Retry
This SOP governs delivery retry for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 08 — Campaign Throttling
This SOP governs campaign throttling for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 09 — Notification Escalation
This SOP governs notification escalation for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 10 — Channel Outage
This SOP governs channel outage for Notification & Communications. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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
### Notification & Communications rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

### Notification & Communications rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The Notification & Communications agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### Notification & Communications exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Notification & Communications exception 10 — Repeated workflow failure
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

### North-star — Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: Critical messages are delivered once, through the correct channel, with suppression, consent and audit controls.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### Notification & Communications Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the communications knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Notification & Communications Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the communications knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Notification & Communications Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the communications knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Notification & Communications Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the communications knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `inbound_email` — found_in_production_export — functions/inbound_email.md
- **backend_function** `email_triage` — found_in_production_export — functions/email_triage.md
- **backend_function** `email_cron` — found_in_production_export — functions/email_cron.md
- **backend_function** `send_whatsapp` — found_in_production_export — functions/send_whatsapp.md
- **backend_function** `send_sms` — found_in_production_export — functions/send_sms.md
- **backend_function** `messages_api` — found_in_production_export — functions/messages_api.md
- **backend_function** `pending_digest` — found_in_production_export — functions/pending_digest.md
- **database_object** `messages` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `inbound_messages` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `notifications` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `email_suppressions` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `email_block_pattern` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `event_delivery` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `outreach` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `response_template` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `templates` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `chat_threads` — found_in_schema — database/schema-tables-and-views.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.