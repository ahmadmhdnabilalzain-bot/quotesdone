# Finance — Operating Knowledge Pack

**Department key:** `finance`  
**Production mapping:** finance  
**Implementation assessment:** `implemented`  
**Version:** 1.0.0  

## Charter
Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful.

## North-star outcome
Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure.

## Core knowledge domains
1. chart of accounts
2. general ledger
3. accounts payable
4. accounts receivable
5. expense ingestion
6. receipt controls
7. budgeting
8. forecasting
9. cash flow
10. revenue recognition
11. reveal-fee accounting
12. supplier subscriptions
13. VAT
14. corporate tax
15. bank reconciliation
16. payment reconciliation
17. refund accounting
18. payroll coordination
19. management reports
20. financial audit trail

## Owned workflows
1. expense email to ledger
2. supplier invoice processing
3. payment reconciliation
4. reveal-fee recognition
5. refund accounting
6. monthly close
7. VAT review
8. corporate-tax evidence retention
9. cash forecast
10. spend optimization

## Authority and operating boundary
The department may act only within the live authority matrix. Legal judgment, material money movement, identity/authentication, secrets, destructive data operations, production deployment, public claims and changes to the autonomy framework remain hard-gated.

## Knowledge records
### Chart Of Accounts — operating knowledge
Finance must understand chart of accounts as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Chart Of Accounts — how the department uses it
When work involves chart of accounts, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Chart Of Accounts — controls and boundaries
For chart of accounts, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Chart Of Accounts — evidence and live-data requirements
The department should prove work on chart of accounts through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### General Ledger — operating knowledge
Finance must understand general ledger as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### General Ledger — how the department uses it
When work involves general ledger, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### General Ledger — controls and boundaries
For general ledger, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### General Ledger — evidence and live-data requirements
The department should prove work on general ledger through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Accounts Payable — operating knowledge
Finance must understand accounts payable as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Accounts Payable — how the department uses it
When work involves accounts payable, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Accounts Payable — controls and boundaries
For accounts payable, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Accounts Payable — evidence and live-data requirements
The department should prove work on accounts payable through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Accounts Receivable — operating knowledge
Finance must understand accounts receivable as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Accounts Receivable — how the department uses it
When work involves accounts receivable, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Accounts Receivable — controls and boundaries
For accounts receivable, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Accounts Receivable — evidence and live-data requirements
The department should prove work on accounts receivable through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Expense Ingestion — operating knowledge
Finance must understand expense ingestion as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Expense Ingestion — how the department uses it
When work involves expense ingestion, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Expense Ingestion — controls and boundaries
For expense ingestion, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Expense Ingestion — evidence and live-data requirements
The department should prove work on expense ingestion through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Receipt Controls — operating knowledge
Finance must understand receipt controls as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Receipt Controls — how the department uses it
When work involves receipt controls, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Receipt Controls — controls and boundaries
For receipt controls, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Receipt Controls — evidence and live-data requirements
The department should prove work on receipt controls through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Budgeting — operating knowledge
Finance must understand budgeting as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Budgeting — how the department uses it
When work involves budgeting, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Budgeting — controls and boundaries
For budgeting, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Budgeting — evidence and live-data requirements
The department should prove work on budgeting through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Forecasting — operating knowledge
Finance must understand forecasting as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Forecasting — how the department uses it
When work involves forecasting, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Forecasting — controls and boundaries
For forecasting, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Forecasting — evidence and live-data requirements
The department should prove work on forecasting through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Cash Flow — operating knowledge
Finance must understand cash flow as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Cash Flow — how the department uses it
When work involves cash flow, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Cash Flow — controls and boundaries
For cash flow, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Cash Flow — evidence and live-data requirements
The department should prove work on cash flow through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Revenue Recognition — operating knowledge
Finance must understand revenue recognition as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Revenue Recognition — how the department uses it
When work involves revenue recognition, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Revenue Recognition — controls and boundaries
For revenue recognition, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Revenue Recognition — evidence and live-data requirements
The department should prove work on revenue recognition through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Reveal-Fee Accounting — operating knowledge
Finance must understand reveal-fee accounting as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Reveal-Fee Accounting — how the department uses it
When work involves reveal-fee accounting, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Reveal-Fee Accounting — controls and boundaries
For reveal-fee accounting, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Reveal-Fee Accounting — evidence and live-data requirements
The department should prove work on reveal-fee accounting through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Supplier Subscriptions — operating knowledge
Finance must understand supplier subscriptions as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Supplier Subscriptions — how the department uses it
When work involves supplier subscriptions, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Supplier Subscriptions — controls and boundaries
For supplier subscriptions, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Supplier Subscriptions — evidence and live-data requirements
The department should prove work on supplier subscriptions through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Vat — operating knowledge
Finance must understand VAT as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Vat — how the department uses it
When work involves VAT, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Vat — controls and boundaries
For VAT, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Vat — evidence and live-data requirements
The department should prove work on VAT through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Corporate Tax — operating knowledge
Finance must understand corporate tax as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Corporate Tax — how the department uses it
When work involves corporate tax, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Corporate Tax — controls and boundaries
For corporate tax, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Corporate Tax — evidence and live-data requirements
The department should prove work on corporate tax through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Bank Reconciliation — operating knowledge
Finance must understand bank reconciliation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Bank Reconciliation — how the department uses it
When work involves bank reconciliation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Bank Reconciliation — controls and boundaries
For bank reconciliation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Bank Reconciliation — evidence and live-data requirements
The department should prove work on bank reconciliation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Payment Reconciliation — operating knowledge
Finance must understand payment reconciliation as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Payment Reconciliation — how the department uses it
When work involves payment reconciliation, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Payment Reconciliation — controls and boundaries
For payment reconciliation, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Payment Reconciliation — evidence and live-data requirements
The department should prove work on payment reconciliation through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Refund Accounting — operating knowledge
Finance must understand refund accounting as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Refund Accounting — how the department uses it
When work involves refund accounting, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Refund Accounting — controls and boundaries
For refund accounting, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Refund Accounting — evidence and live-data requirements
The department should prove work on refund accounting through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Payroll Coordination — operating knowledge
Finance must understand payroll coordination as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Payroll Coordination — how the department uses it
When work involves payroll coordination, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Payroll Coordination — controls and boundaries
For payroll coordination, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Payroll Coordination — evidence and live-data requirements
The department should prove work on payroll coordination through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Management Reports — operating knowledge
Finance must understand management reports as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Management Reports — how the department uses it
When work involves management reports, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Management Reports — controls and boundaries
For management reports, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Management Reports — evidence and live-data requirements
The department should prove work on management reports through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

### Financial Audit Trail — operating knowledge
Finance must understand financial audit trail as an operational capability, not as a generic definition. The knowledge must identify the business purpose, owners, inputs, outputs, evidence, decision thresholds, failure conditions and downstream effects. It must preserve the department charter — Keep financial records complete, cash visible, budgets controlled, tax obligations tracked and management reporting decision-useful. — and contribute to the north-star outcome: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure. Knowledge records should distinguish stable policy from live operational facts and should point to live tables rather than copying values that change.

### Financial Audit Trail — how the department uses it
When work involves financial audit trail, the department should first establish the entity and workflow state, then retrieve current operational data, then apply the approved SOP and decision rules. The output must be structured for the next department rather than left as an informal narrative. The agent should identify what is known, what is inferred, what is missing and what evidence supports the conclusion. Repeated work should update reusable templates or rules only through the knowledge-change process.

### Financial Audit Trail — controls and boundaries
For financial audit trail, the department must apply least privilege, data minimisation, audit logging, version control and the relevant authority tier. It must not treat a generated answer as proof. Where the topic affects legal rights, money, identity, privacy, security, production deployment or public claims, execution is blocked until the required approval and evidence are present. Conflicts between live data and static knowledge are resolved in favour of the authorised live source, with the discrepancy logged for review.

### Financial Audit Trail — evidence and live-data requirements
The department should prove work on financial audit trail through the authoritative record for the entity, relevant documents, event history, approvals and outcome metrics. Candidate live sources include: expenses, expense_entries, gl_accounts, gl_journal, gl_journal_lines, ap_bills, budgets, budget_lines. Candidate execution evidence includes: finance_ingest, finance_doc, cost_snapshot, money_tests, stripe_webhook, refund_flow, report_body. These names come from the supplied production export or the target design; Claude must map them to the current repository and schema, confirm permissions and record any mismatch instead of silently inventing a binding.

## Standard operating procedures
### SOP 01 — Expense Email To Ledger
This SOP governs expense email to ledger for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 02 — Supplier Invoice Processing
This SOP governs supplier invoice processing for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 03 — Payment Reconciliation
This SOP governs payment reconciliation for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 04 — Reveal-Fee Recognition
This SOP governs reveal-fee recognition for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 05 — Refund Accounting
This SOP governs refund accounting for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 06 — Monthly Close
This SOP governs monthly close for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 07 — Vat Review
This SOP governs VAT review for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 08 — Corporate-Tax Evidence Retention
This SOP governs corporate-tax evidence retention for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 09 — Cash Forecast
This SOP governs cash forecast for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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

### SOP 10 — Spend Optimization
This SOP governs spend optimization for Finance. The department owns the workflow until the stated handoff is accepted by the next owner. Normal cases should progress without founder intervention; exceptions are escalated with evidence and a proposed resolution, not merely a problem statement.

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
### Finance rule 01 — Missing mandatory evidence
If a required document, field or provider event is absent, do not infer completion. Set the case to needs_information, request the exact missing evidence and suspend irreversible execution. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 02 — Confidence below floor
If routing or interpretation confidence is below the configured floor, ask one targeted clarification or route to the responsible specialist. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 03 — Live data conflicts with static knowledge
Treat the authoritative live record as operational truth, prevent execution if the conflict affects safety or rights, and create a knowledge-correction task. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 04 — Duplicate task or event
Use the idempotency key and current entity state to suppress duplicate execution while preserving the duplicate event in the audit trail. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 05 — Authority exceeded
Block execution and request approval from the role specified in the authority matrix, including amount, impact, evidence and rollback plan. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 06 — Customer or supplier impact
Before executing a material change, identify affected users, required notice, contractual or privacy implications and a remediation path. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 07 — Provider or integration unavailable
Queue recoverable work, switch only to approved fallback services, apply backoff, communicate service impact and reconcile after recovery. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 08 — Irreversible action
Require two-step confirmation, evidence snapshot, explicit scope and legal or data-owner review where applicable. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 09 — Policy ambiguity
Do not create an ad-hoc policy through a model answer. Escalate the policy question and continue only with reversible advisory work. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

### Finance rule 10 — Material anomaly
Compare against prior baselines, rule out data-quality errors, create an incident if genuine and stop automated amplification. The Finance agent must record which rule fired, the relevant entity state and the downstream action.

## Exception playbooks
### Finance exception 01 — External AI provider unavailable
Route to deterministic logic or the approved small/local model; queue tasks requiring stronger reasoning; never weaken privacy, legal or financial controls to maintain throughput. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 02 — Database or vector retrieval failure
Stop decisions that depend on missing evidence, retry with backoff, use a verified read replica or last-known snapshot only where policy allows, and reconcile once restored. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 03 — Email delivery failure
Record provider response, retry through the outbox, respect suppression and idempotency, use an approved alternative channel only when consent and urgency permit. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 04 — WhatsApp or SMS outage
Queue messages, avoid duplicate sends, fall back to email or in-app notification only according to channel policy, and notify operations when SLA is at risk. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 05 — Corrupted or unsupported document
Quarantine the file, preserve the original, ask for a supported replacement or conversion and do not treat partial extraction as complete evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 06 — Two agents disagree
Compare source quality and authority, run the independent review chain and escalate only the unresolved decision with both recommendations and evidence. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 07 — Locked or conflicting record
Do not overwrite. Retry safely, surface the competing update, merge only through the entity's concurrency policy and maintain version history. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 08 — User changes material requirements mid-workflow
Version the scope, freeze prior quotations from direct comparison, notify affected parties and restart qualification for changed fields. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 09 — Security or privacy suspicion
Contain first, preserve evidence, restrict access, notify the security/privacy owner and follow the incident and breach-assessment runbook. The department remains accountable for state, communication and reconciliation until the exception is formally handed off or closed.

### Finance exception 10 — Repeated workflow failure
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

### North-star — Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure.
Primary department outcome. Claude must define an exact numerator, denominator, data owner, source table, refresh frequency and alert thresholds for: Accurate books, controlled cash burn, timely collections and no unmanaged tax or payment exposure.. The metric must have a single owner, authoritative query, refresh schedule, target, warning threshold and documented limitations.

## Target roles
### Finance Director
Owns the charter, authority, outcomes, risk and cross-department commitments. This is a target role definition, not proof that a separate production agent currently exists. The role uses the finance knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Finance Operations Specialist
Executes daily workflows, maintains case state, evidence and handoffs. This is a target role definition, not proof that a separate production agent currently exists. The role uses the finance knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Finance Analyst / Controller
Monitors quality, metrics, anomalies, forecasts and control effectiveness. This is a target role definition, not proof that a separate production agent currently exists. The role uses the finance knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

### Finance Reviewer / Auditor
Independently samples decisions, checks policy compliance and proposes corrective action. This is a target role definition, not proof that a separate production agent currently exists. The role uses the finance knowledge scope, may access only approved live bindings and must follow the department authority ceiling.

## Production implementation evidence
The following is evidence from the supplied export, not a guarantee that the current GitHub repository or frontend is identical. Claude must inspect the repository and live staging environment.
- **backend_function** `finance_ingest` — found_in_production_export — functions/finance_ingest.md
- **backend_function** `finance_doc` — found_in_production_export — functions/finance_doc.md
- **backend_function** `cost_snapshot` — found_in_production_export — functions/cost_snapshot.md
- **backend_function** `money_tests` — found_in_production_export — functions/money_tests.md
- **backend_function** `stripe_webhook` — found_in_production_export — functions/stripe_webhook.md
- **backend_function** `refund_flow` — found_in_production_export — functions/refund_flow.md
- **backend_function** `report_body` — found_in_production_export — functions/report_body.md
- **database_object** `expenses` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `expense_entries` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `gl_accounts` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `gl_journal` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `gl_journal_lines` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `ap_bills` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `budgets` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `budget_lines` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `finance_reports` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `finance_snapshots` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `finance_kpi_snapshots` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `transactions` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `reveal_invoices` — found_in_schema — database/schema-tables-and-views.md
- **database_object** `stripe_events` — found_in_schema — database/schema-tables-and-views.md
- **migration** `20260708110544_erp_ws_finance_cfo` — found_in_production_export — migrations/20260708110544_erp_ws_finance_cfo.md
- **migration** `20260709083034_finance_forecast_and_kpis` — found_in_production_export — migrations/20260709083034_finance_forecast_and_kpis.md
- **migration** `20260709083220_fn_finance_ai_agent` — found_in_production_export — migrations/20260709083220_fn_finance_ai_agent.md
- **migration** `20260709083600_ws_finance_add_ai_block` — found_in_production_export — migrations/20260709083600_ws_finance_add_ai_block.md
- **migration** `20260713112611_finance_subscription_reminders` — found_in_production_export — migrations/20260713112611_finance_subscription_reminders.md

## Review status
This is a production operating draft. Regulated, legal, tax, security and professional content must preserve its review status and must not be promoted to autonomous authority without the designated reviewer.