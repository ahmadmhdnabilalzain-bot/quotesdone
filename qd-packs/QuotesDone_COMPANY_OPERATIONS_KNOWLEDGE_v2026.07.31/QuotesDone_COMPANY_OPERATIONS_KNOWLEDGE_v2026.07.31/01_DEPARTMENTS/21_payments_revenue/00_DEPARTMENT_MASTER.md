# Payments & Revenue Operations — Operating Knowledge Pack

**Department key:** `payments_revenue`  
**Production mapping:** finance, customer_success  
**Implementation assessment:** `partial`  
**Version:** 1.0.0  

## Charter
Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence.

## North-star outcome
Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority.

## Core knowledge domains
1. payment gateway
2. Stripe events
3. checkout
4. payment confirmation
5. reveal fee
6. VAT presentation
7. invoicing
8. supplier subscriptions
9. refunds
10. payment disputes
11. idempotency
12. webhook verification
13. failed payments
14. reconciliation
15. commission management
16. chargebacks
17. financial controls
18. payment security
19. customer communication
20. provider outage

## Owned workflows
1. reveal checkout
2. payment confirmation
3. invoice generation
4. webhook processing
5. failed-payment recovery
6. refund request
7. payment dispute
8. subscription billing
9. daily reconciliation
10. provider incident

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Payment Gateway — operating knowledge
Payments & Revenue Operations must understand payment gateway as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Payment Gateway — how the department uses it
When work involves payment gateway, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Payment Gateway — controls and boundaries
For payment gateway, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Payment Gateway — evidence and live-data requirements
The department should prove work on payment gateway through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Stripe Events — operating knowledge
Payments & Revenue Operations must understand Stripe events as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Stripe Events — how the department uses it
When work involves Stripe events, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Stripe Events — controls and boundaries
For Stripe events, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Stripe Events — evidence and live-data requirements
The department should prove work on Stripe events through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Checkout — operating knowledge
Payments & Revenue Operations must understand checkout as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Checkout — how the department uses it
When work involves checkout, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Checkout — controls and boundaries
For checkout, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Checkout — evidence and live-data requirements
The department should prove work on checkout through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Payment Confirmation — operating knowledge
Payments & Revenue Operations must understand payment confirmation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Payment Confirmation — how the department uses it
When work involves payment confirmation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Payment Confirmation — controls and boundaries
For payment confirmation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Payment Confirmation — evidence and live-data requirements
The department should prove work on payment confirmation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Reveal Fee — operating knowledge
Payments & Revenue Operations must understand reveal fee as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Reveal Fee — how the department uses it
When work involves reveal fee, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Reveal Fee — controls and boundaries
For reveal fee, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Reveal Fee — evidence and live-data requirements
The department should prove work on reveal fee through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Vat Presentation — operating knowledge
Payments & Revenue Operations must understand VAT presentation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Vat Presentation — how the department uses it
When work involves VAT presentation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Vat Presentation — controls and boundaries
For VAT presentation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Vat Presentation — evidence and live-data requirements
The department should prove work on VAT presentation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Invoicing — operating knowledge
Payments & Revenue Operations must understand invoicing as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Invoicing — how the department uses it
When work involves invoicing, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Invoicing — controls and boundaries
For invoicing, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Invoicing — evidence and live-data requirements
The department should prove work on invoicing through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Subscriptions — operating knowledge
Payments & Revenue Operations must understand supplier subscriptions as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Subscriptions — how the department uses it
When work involves supplier subscriptions, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Subscriptions — controls and boundaries
For supplier subscriptions, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Subscriptions — evidence and live-data requirements
The department should prove work on supplier subscriptions through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Refunds — operating knowledge
Payments & Revenue Operations must understand refunds as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Refunds — how the department uses it
When work involves refunds, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Refunds — controls and boundaries
For refunds, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Refunds — evidence and live-data requirements
The department should prove work on refunds through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Payment Disputes — operating knowledge
Payments & Revenue Operations must understand payment disputes as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Payment Disputes — how the department uses it
When work involves payment disputes, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Payment Disputes — controls and boundaries
For payment disputes, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Payment Disputes — evidence and live-data requirements
The department should prove work on payment disputes through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Idempotency — operating knowledge
Payments & Revenue Operations must understand idempotency as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Idempotency — how the department uses it
When work involves idempotency, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Idempotency — controls and boundaries
For idempotency, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Idempotency — evidence and live-data requirements
The department should prove work on idempotency through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Webhook Verification — operating knowledge
Payments & Revenue Operations must understand webhook verification as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Webhook Verification — how the department uses it
When work involves webhook verification, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Webhook Verification — controls and boundaries
For webhook verification, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Webhook Verification — evidence and live-data requirements
The department should prove work on webhook verification through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Failed Payments — operating knowledge
Payments & Revenue Operations must understand failed payments as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Failed Payments — how the department uses it
When work involves failed payments, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Failed Payments — controls and boundaries
For failed payments, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Failed Payments — evidence and live-data requirements
The department should prove work on failed payments through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Reconciliation — operating knowledge
Payments & Revenue Operations must understand reconciliation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Reconciliation — how the department uses it
When work involves reconciliation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Reconciliation — controls and boundaries
For reconciliation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Reconciliation — evidence and live-data requirements
The department should prove work on reconciliation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Commission Management — operating knowledge
Payments & Revenue Operations must understand commission management as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Commission Management — how the department uses it
When work involves commission management, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Commission Management — controls and boundaries
For commission management, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Commission Management — evidence and live-data requirements
The department should prove work on commission management through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Chargebacks — operating knowledge
Payments & Revenue Operations must understand chargebacks as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Chargebacks — how the department uses it
When work involves chargebacks, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Chargebacks — controls and boundaries
For chargebacks, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Chargebacks — evidence and live-data requirements
The department should prove work on chargebacks through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Financial Controls — operating knowledge
Payments & Revenue Operations must understand financial controls as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Financial Controls — how the department uses it
When work involves financial controls, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Financial Controls — controls and boundaries
For financial controls, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Financial Controls — evidence and live-data requirements
The department should prove work on financial controls through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Payment Security — operating knowledge
Payments & Revenue Operations must understand payment security as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Payment Security — how the department uses it
When work involves payment security, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Payment Security — controls and boundaries
For payment security, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Payment Security — evidence and live-data requirements
The department should prove work on payment security through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Customer Communication — operating knowledge
Payments & Revenue Operations must understand customer communication as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Customer Communication — how the department uses it
When work involves customer communication, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Customer Communication — controls and boundaries
For customer communication, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Customer Communication — evidence and live-data requirements
The department should prove work on customer communication through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Provider Outage — operating knowledge
Payments & Revenue Operations must understand provider outage as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Operate reveal payments, subscriptions, invoices, refunds and disputes safely, reconcile provider events and maintain complete transaction evidence. — and contribute to the north-star outcome: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Provider Outage — how the department uses it
When work involves provider outage, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Provider Outage — controls and boundaries
For provider outage, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Provider Outage — evidence and live-data requirements
The department should prove work on provider outage through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: transactions, stripe_events, reveal_invoices, payment_dispute, refunds, supplier_dues, pricing_config, gl_journal. Candidate execution evidence includes: stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay, refund_flow, refunds_api, money_tests, quote_pdf. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — Reveal Checkout
This SOP governs reveal checkout for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 02 — Payment Confirmation
This SOP governs payment confirmation for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 03 — Invoice Generation
This SOP governs invoice generation for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 04 — Webhook Processing
This SOP governs webhook processing for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 05 — Failed-Payment Recovery
This SOP governs failed-payment recovery for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 06 — Refund Request
This SOP governs refund request for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 07 — Payment Dispute
This SOP governs payment dispute for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 08 — Subscription Billing
This SOP governs subscription billing for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 09 — Daily Reconciliation
This SOP governs daily reconciliation for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 10 — Provider Incident
This SOP governs provider incident for Payments & Revenue Operations. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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
### Payments & Revenue Operations rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

### Payments & Revenue Operations rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The Payments & Revenue Operations agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### Payments & Revenue Operations exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Payments & Revenue Operations exception 10 — Repeated workflow failure
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

### North-star — Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: Every payment state is accurate, reconcilable and recoverable without exposing secrets or moving funds outside authority.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### Payments & Revenue Operations Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the payments_revenue knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Payments & Revenue Operations Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the payments_revenue knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Payments & Revenue Operations Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the payments_revenue knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Payments & Revenue Operations Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the payments_revenue knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `stripe_checkout` — found_in_production_export — functions/stripe_checkout.md
- **backend_function** `stripe_confirm` — found_in_production_export — functions/stripe_confirm.md
- **backend_function** `stripe_webhook` — found_in_production_export — functions/stripe_webhook.md
- **backend_function** `supplier_pay` — found_in_production_export — functions/supplier_pay.md
- **backend_function** `refund_flow` — found_in_production_export — functions/refund_flow.md
- **backend_function** `refunds_api` — found_in_production_export — functions/refunds_api.md
- **backend_function** `money_tests` — found_in_production_export — functions/money_tests.md
- **backend_function** `quote_pdf` — found_in_production_export — functions/quote_pdf.md
- **database_object** `transactions` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `stripe_events` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `reveal_invoices` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `payment_dispute` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `refunds` — not_found_by_exact_name — unresolved
- **database_object** `supplier_dues` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `pricing_config` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `gl_journal` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `notifications` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `os_audit_log` — found_in_schema — database/schema-tables-and-views.md
- **migration** `20260719003740_gl_reverse_phantom_test_revenue` — found_in_production_export — migrations/20260719003740_gl_reverse_phantom_test_revenue.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.