-- FIVE PROCESSES THE COMPANY PERFORMS AND HAD NEVER WRITTEN DOWN.
--
-- 14 workflows existed; Customer Registration, Payment, Complaint, Refund and Supplier Suspension
-- did not. Every one of the five has real machinery behind it - transactions, fn_refund_state,
-- leads.banned, notifications - so this is not inventing process. It is recording the process the
-- code already performs, in the place management looks for it, with the gate on each step.
--
-- WHY THAT MATTERS RATHER THAN BEING PAPERWORK: workflow_step.gate is where authority lives. A step
-- with gate='founder' is a step no agent may take alone. Refund carries it, because the founder's
-- one standing approval rule in this company is that a Stripe refund needs him - and until now that
-- rule existed only in a session document and in his head, not anywhere the company could read.
--
-- Actor roles are the TITLES of employees that actually exist; every one was checked against
-- org_agents where active before being written here. A workflow naming a role nobody holds is a
-- workflow nobody runs.
--
-- HONEST LIMIT: writing a workflow does not execute it. 9 of the existing 14 have 0 runs, and these
-- five will start at 0 too. workflow_run is the evidence of execution and none of these can produce
-- one until the company has a customer. What this closes is that management could not SEE the
-- process, not that the process now runs itself.

insert into public.workflow (workflow_key, name, trigger_event, description, active, os_key) values
 ('customer_registration','Customer Registration','customer.registered',
  'A customer creates an account and reaches the point of being able to post a request. Backed by customers (phone_verified, email_verified, tos_accepted_at, tos_version, wa_optin) and the OTP path.', true, 'marketplace'),
 ('payment','Reveal Payment','reveal.paid',
  'A customer pays the reveal fee and supplier contact details are released. Backed by transactions (reveal_fee, app_fee, fee_status, payment_ref, revealed_at) and Stripe.', true, 'finance'),
 ('complaint','Customer Complaint','complaint.received',
  'A customer raises a problem with a supplier, a quote or the platform. Backed by the escalation path in wa_inbound and customer_api, notifications and agent_actions.', true, 'operations'),
 ('refund','Reveal Refund','refund.requested',
  'A customer asks for the reveal fee back, normally because the supplier never responded. Backed by fn_refund_state, fn_notify_supplier, the working-day ladder and transactions.refund_*.', true, 'finance'),
 ('supplier_suspension','Supplier Suspension','supplier.suspension_proposed',
  'A supplier is removed from matching for fraud, repeated non-response, an expired licence or a trust-and-safety finding. Backed by leads.banned, banned_reason, matching_blocked, matching_block_reason.', true, 'marketplace')
on conflict (workflow_key) do nothing;

insert into public.workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 -- CUSTOMER REGISTRATION -----------------------------------------------------------------------
 ('customer_registration',1,'Registration submitted','Customer Support Specialist',null,'none'),
 ('customer_registration',2,'Verify the mobile number by OTP (customers.phone_verified)','Customer Support Specialist',null,'none'),
 ('customer_registration',3,'Record terms acceptance with version and IP (tos_accepted_at, tos_version, tos_ip)','Compliance Manager',null,'none'),
 ('customer_registration',4,'Screen for duplicate or previously banned identity before activating','Fraud & Risk Analyst',null,'review'),
 ('customer_registration',5,'Activate the account and capture channel consent (wa_optin)','Customer Support Specialist',null,'none'),
 ('customer_registration',6,'Guide the customer to their first request','Customer Success Director',null,'none'),
 ('customer_registration',7,'Measure activation and feed the customer KPIs','Supplier & Customer Analyst',null,'none'),

 -- REVEAL PAYMENT ------------------------------------------------------------------------------
 ('payment',1,'Customer chooses a quote and requests the reveal','Account Manager',null,'none'),
 ('payment',2,'Compute the reveal fee from the quote and the live fee policy','Billing & Reconciliation Specialist',null,'none'),
 ('payment',3,'Take payment through Stripe','Billing & Reconciliation Specialist',null,'none'),
 ('payment',4,'Write the transaction and release supplier contact details ONLY on a confirmed charge','Billing & Reconciliation Specialist',null,'none'),
 ('payment',5,'Reconcile the charge against the transactions row and flag any charge without a reveal','Accountant','money_verify','review'),
 ('payment',6,'Post to the ledger and issue the receipt','Accountant',null,'none'),
 ('payment',7,'Start the supplier response clock (nudge at 24h and 48h)','Customer Success Director',null,'none'),
 ('payment',8,'Measure conversion and feed revenue_annual','Finance Director',null,'none'),

 -- COMPLAINT -----------------------------------------------------------------------------------
 ('complaint',1,'Complaint received on any channel','Customer Support Specialist',null,'none'),
 ('complaint',2,'Classify severity and whether money, safety or compliance is involved','Customer Support Specialist',null,'none'),
 ('complaint',3,'Acknowledge to the customer within the SLA, before any investigation','Customer Support Specialist',null,'none'),
 ('complaint',4,'Investigate against the record - inquiry, quotes, transaction, messages','Quality Assurance Manager',null,'none'),
 ('complaint',5,'Legal and compliance review where a contract, licence or regulation is in scope','Legal Counsel','legal_review','review'),
 ('complaint',6,'Decide the remedy','Customer Success Director',null,'dept_head'),
 ('complaint',7,'Escalate to the founder if the remedy is a refund or a supplier suspension','Customer Success Director','escalate_founder','founder'),
 ('complaint',8,'Execute the remedy and tell the customer what was done','Customer Support Specialist',null,'none'),
 ('complaint',9,'Trace the cause to the employee, prompt, knowledge source or rule and correct it','Quality Assurance Manager',null,'none'),
 ('complaint',10,'Re-check the KPI the failure moved','Supplier & Customer Analyst',null,'none'),

 -- REFUND --------------------------------------------------------------------------------------
 ('refund',1,'Customer requests the reveal fee back','Customer Support Specialist',null,'none'),
 ('refund',2,'Read fn_refund_state - it decides what is permitted and when','Billing & Reconciliation Specialist',null,'none'),
 ('refund',3,'Formally notify the supplier, copying the customer (fn_notify_supplier)','Customer Success Director',null,'none'),
 ('refund',4,'Wait out the working-day ladder - call window, then claim window','Customer Success Director',null,'none'),
 ('refund',5,'Verify the supplier genuinely did not respond before accepting the claim','Quality Assurance Manager',null,'review'),
 ('refund',6,'Recommend approve or decline with the evidence attached','Finance Director','recommend','dept_head'),
 -- THE ONE STANDING APPROVAL RULE IN THIS COMPANY, NOW WRITTEN WHERE THE COMPANY CAN READ IT.
 ('refund',7,'FOUNDER APPROVAL. No agent may execute a Stripe refund. This gate is absolute and is not delegable to any department head.','Finance Director','escalate_founder','founder'),
 ('refund',8,'Execute the refund in Stripe and record refund_stripe_id, refund_amount_aed, refund_confirmed_at','Billing & Reconciliation Specialist',null,'none'),
 ('refund',9,'Recover the fee from the supplier under the supplier terms where non-response caused it','Accounts Receivable Specialist',null,'none'),
 ('refund',10,'Record against the supplier (rv_nonresponse_refunds) and re-check their standing','Supplier Retention Specialist',null,'none'),

 -- SUPPLIER SUSPENSION -------------------------------------------------------------------------
 ('supplier_suspension',1,'Suspension proposed - fraud signal, repeated non-response, expired licence or trust finding','Trust & Safety Manager',null,'none'),
 ('supplier_suspension',2,'Gather the evidence onto the record before anything is blocked','Fraud & Risk Analyst',null,'none'),
 ('supplier_suspension',3,'Verify the licence and document position independently','Supplier Verification Specialist',null,'none'),
 ('supplier_suspension',4,'Legal review - suspension affects a commercial relationship and a paid subscription','Legal Counsel','legal_review','review'),
 ('supplier_suspension',5,'Risk and governance sign-off','Risk & Governance Manager',null,'authority'),
 ('supplier_suspension',6,'Decide: block matching only (matching_blocked) or suspend the account (banned)','Trust & Safety Manager',null,'dept_head'),
 ('supplier_suspension',7,'Apply the block with a stated reason - never an unexplained flag','Trust & Safety Manager',null,'none'),
 ('supplier_suspension',8,'Tell the supplier what happened and how to answer it','Supplier Success Manager',null,'none'),
 ('supplier_suspension',9,'Handle the appeal and reinstate if the evidence does not hold','Supplier Success Manager',null,'dept_head'),
 ('supplier_suspension',10,'Check the effect on category coverage - suspending the only supplier in a category closes it','Supplier Coverage Specialist',null,'none'),
 ('supplier_suspension',11,'Learn: was the signal that triggered this correct?','Quality Assurance Manager',null,'none')
on conflict do nothing;
