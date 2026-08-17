// The cutover classification, one entry per source, in the founder's four classes.
//
//   A  NEW_WORK_REQUEST        starts a Phase B workflow through fn_kernel_trigger_submit
//   B  EXISTING_WORKFLOW_SIGNAL attaches to a run that already exists, via fn_kernel_signal_submit
//   C  READ_ONLY_MONITOR        observes; may update approved operational state; may NEVER create
//                               business work directly — when a threshold is crossed it raises a
//                               separate class-A request with its own dedupe key and evidence
//   D  RETIRE_OR_HISTORICAL     deliberately dead, kept only so history stays readable
//
// `why` is the reason the class is what it is, and it is written per source, not per class. A
// classification with no stated reason is a label.
//
// `signal` is the kernel_signal_type a class-B source submits; `trigger` is the
// kernel_trigger_type a class-A source submits. Exactly one of them is set, and the seed refuses
// to write a row where that is not true.
export const CLASSIFICATION = {
  // ---- cron: the eleven live ones observe and report; none of them writes business work -------
  'cron:103': ['C', null, 'fn_policy_consistency_check (weekly, 4 runs). Reads the policy set and reports inconsistencies; it calls no writer, measured live from the catalogue.'],
  'cron:110': ['C', null, 'fn_security_scan (hourly, 693 runs). Scans and reports; it calls no writer, measured live from the catalogue rather than assumed from the name.'],
  'cron:129': ['C', null, 'fn_autonomy_audit_run (weekly, 3 runs). Audits how much autonomy each role has actually exercised and reports it; it calls no writer.'],
  'cron:14':  ['C', null, 'fn_founder_brief (daily, 29 runs). Composes the founder brief from state that already exists; it starts nothing and calls no writer.'],
  'cron:142': ['C', null, 'fn_evolution_scan (weekly, 2 runs). Scans for structural improvement candidates and reports them; it calls no writer.'],
  'cron:172': ['C', null, 'fn_ai_spend_guard (hourly, 457 runs). Watches AI spend against its ceiling and reports; it calls no writer. A breach must raise a class-A request, not write work from here.'],
  'cron:195': ['C', null, 'fn_workflow_start_due(1440) (every 15 min, 954 runs, switched off). Reports what is DUE to start. Naming a workflow does not make it a starter: creates_work_now is false, measured from the catalogue.'],
  'cron:250': ['C', null, 'fn_employee_kpi_measure (daily, 5 runs, switched off). Measures employee KPIs and records the measurement; it creates no business work.'],
  'cron:26':  ['C', null, 'fn_smoke (every 30 min, 1390 runs). A smoke test. It asserts and reports; it calls no writer.'],
  'cron:53':  ['C', null, 'doc_process (every 5 min, 8137 runs, switched off). Posts to the document edge function in a loop; whatever work results is created THERE, and that function carries its own row in this register.'],
  'cron:57':  ['C', null, 'fn_board_report (weekly, 4 runs). Produces the board report from existing state; it calls no writer.'],
  'cron:60':  ['C', null, 'fn_period_report(monthly) (monthly, 1 run). Produces the monthly report from existing state; it calls no writer.'],
  'cron:64':  ['C', null, 'fn_autonomy_dispose (hourly, 374 runs). Disposes of expired autonomy grants — operational state, not business work; it calls no writer.'],
  'cron:7':   ['C', null, 'run_health_check (every 30 min, 1390 runs). Health probe. It records health and calls no writer.'],
  // ---- cron: the ones that do write, all currently switched off -------------------------------
  'cron:105': ['A', 'scheduled.financial_close', 'A billing run opens a new close cycle for a period that has no run yet. Switched off; the cutover gives it a door, not an activation.'],
  'cron:118': ['A', 'supplier.file_complete', 'A supplier file becoming complete is the declared start of W10 Supplier verification. Switched off; the cutover gives it a door, not an activation.'],
  'cron:155': ['A', 'kpi.supplier_coverage_gap', 'A supplier coverage gap is the declared start of W11 Coverage and liquidity correction. Switched off; the cutover gives it a door, not an activation.'],
  'cron:2':   ['A', 'supplier.registration_submitted', 'Opens W09 for a supplier registration that has no run yet. Switched off; the cutover gives it a door, not an activation.'],
  'cron:209': ['A', 'supplier.churn_signal', 'A churn signal opens W19 for a supplier with no live run. Switched off; the cutover gives it a door, not an activation.'],
  'cron:210': ['A', 'supplier.churn_signal', 'Second churn sweep. Same class, same dedupe key shape, so two sweeps seeing one supplier produce one run. Switched off.'],
  'cron:211': ['A', 'supplier.churn_signal', 'Third churn sweep. Same class and key shape as 209 and 210. Switched off.'],
  'cron:67':  ['A', 'customer.inquiry_submitted', 'Opens W05 for an inquiry that has no run yet. Switched off; the cutover gives it a door, not an activation.'],
  'cron:141': ['B', 'followup.due', 'A notification already approved inside a W13 run falling due to send. It is a follow-up on that run, not a new one. Switched off.'],
  'cron:264': ['B', 'followup.due', 'A safe package already approved inside a W12 run falling due. A follow-up on the existing run, never a second one. Switched off.'],
  // ---- database triggers: live, and every one of them writes ----------------------------------
  'dbtrigger:public.agent_actions:trg_page_high_agent_action': ['A', 'system.incident_opened', 'A high-severity agent action with no incident open for it yet is the declared start of W29 Incident and security response.'],
  'dbtrigger:public.company_goals:trg_goal_cascade':           ['A', 'kpi.company_target_miss', 'A company goal moving outside tolerance is the declared start of W02 Company target miss and corrective management, for that goal.'],
  'dbtrigger:public.inquiries:customer_abandon_ban':           ['A', 'customer.support_signal', 'An abandonment is a new support signal about a customer, not a step inside an inquiry run.'],
  'dbtrigger:public.inquiries:trg_inquiry_received_a':         ['A', 'customer.inquiry_submitted', 'The row that IS the new inquiry. Declared start of W05 Customer inquiry qualification; nothing exists to attach a signal to yet.'],
  'dbtrigger:public.inquiry_matches:notify_matched_supplier':  ['B', 'followup.due', 'A supplier being matched happens INSIDE the W12 run that approved the package. Starting a workflow per match would open one run per supplier for one inquiry.'],
  'dbtrigger:public.notifications:trg_invite_status_on_send':  ['B', 'provider.callback', 'A status change on an invitation already sent. The registration itself is the class-A event; this is its delivery status.'],
  'dbtrigger:public.quote_items:quote_items_rescore':          ['B', 'supplier.quote_revision', 'Item-level rescoring of a quote already inside a W14 run. W14-S03 Receive quotation revision exists for exactly this.'],
  'dbtrigger:public.quote_items:quote_items_roll':             ['B', 'supplier.quote_revision', 'Roll-up of item totals on a quotation that is already inside a W14 run. It fires on revision, not on first submission, so it is a signal on that run.'],
  'dbtrigger:public.quote_items:trg_items_submittable':        ['B', 'supplier.quote_revision', 'Submittability recomputed on a quotation already inside a W14 run. It fires on revision, not on first submission.'],
  'dbtrigger:public.quotes:trg_new_quote_sms':                 ['A', 'supplier.quotation_submitted', 'The row that IS the new quotation. Declared start of W14. Its three sibling triggers on quote_items are class B because they fire on REVISIONS to that same quote — the distinction that stops one quotation opening four runs.'],
  'dbtrigger:public.supplier_dues:trg_due_paid':               ['B', 'provider.callback', 'Payment against a due that already exists. The reveal payment that OPENS W16 is trg_reveal_receipt_a; this is settlement of an existing obligation.'],
  'dbtrigger:public.transactions:trg_notify_refund':           ['A', 'customer.refund_requested', 'A refund being requested is the declared start of W17 Refund and dispute handling; the resolution of that same refund is trg_refund_resolved and is class B.'],
  'dbtrigger:public.transactions:trg_refund_resolved':         ['B', 'provider.callback', 'Resolution of a refund already inside a W17 run. Routing it as new work would open a second W17 for the same transaction.'],
  'dbtrigger:public.transactions:trg_reveal_receipt_a':        ['A', 'provider.payment_event', 'A reveal payment is the declared start of W16 Reveal and payment; settlement of an existing obligation is trg_due_paid and is class B.'],
  // ---- edge functions --------------------------------------------------------------------------
  'edge:attach_photos':      ['B', 'document.arrived_for_run', 'Photos attached to an inquiry that already has a run. W07 owns a NEW document arriving cold; an attachment to live work is evidence on that run, not a second workflow.'],
  'edge:claim_lookup':       ['C', null, 'Public \"is this your company?\" check, v4. It reads a lead by unguessable claim_token and returns; it starts nothing and changes no business state. Public by design — an invited supplier has no account yet, and v2 replaced the sequential id after v1 exposed the 20,470-row lead table.'],
  'edge:contact_submit':     ['A', 'customer.support_signal', 'First contact from the public website with no prior run. Declared start of W18 Customer issue and retention; a reply inside an existing conversation arrives through edge:messages_api instead.'],
  'edge:customer_api':       ['A', 'customer.inquiry_submitted', 'The customer portal submitting a new inquiry. Declared start of W05; documents and messages against an inquiry that already has a run are class B and go through the signal door.'],
  'edge:customer_documents': ['B', 'document.arrived_for_run', 'Documents uploaded against an inquiry that already has a run. Attaching them is evidence on that run; opening a second W07 for a file added to live work is the duplicate this class exists to prevent.'],
  'edge:inbound_email':      ['A', 'customer.inquiry_submitted', 'An inbound email that matches no existing inquiry opens W05. One that carries a document for live work is edge:resend_inbound and is class B.'],
  'edge:inquiry_intake':     ['A', 'customer.inquiry_submitted', 'The intake surface itself: the first thing a new inquiry touches. Declared start of W05 Customer inquiry qualification.'],
  'edge:messages_api':       ['B', 'clarification.response', 'Portal messaging. A message from a customer or supplier lands inside the run the conversation belongs to; the great majority are clarification answers, and none of them is a new inquiry.'],
  'edge:pdpl_request':       ['A', 'customer.privacy_request', 'A privacy or data-subject request is the declared start of W28 Privacy, legal and compliance response. Consent withdrawal is edge:unsubscribe and is a different thing entirely.'],
  'edge:refund_flow':        ['A', 'customer.refund_requested', 'A customer opening a refund with no dispute run yet. Declared start of W17 Refund and dispute handling.'],
  'edge:resend_inbound':     ['B', 'document.arrived_for_run', 'An inbound email carrying a document for an inquiry that is already being worked. Evidence on the existing run, not a new intake.'],
  'edge:resend_webhook':     ['C', null, 'Resend delivery events. A hard bounce writes email_suppressions — approved operational state, not business work. K10 recorded NO_WORKFLOW_IN_REGISTRY and it is right: W13 starts from an APPROVED QUEUED NOTIFICATION, not from its failure to deliver. When suppression crosses a threshold it must raise a separate class-A request, which is why this row is C and not simply exempt.'],
  'edge:site_assistant':     ['A', 'customer.support_signal', 'The site assistant taking a first support signal from a visitor with no run. Declared start of W18 Customer issue and retention.'],
  'edge:stripe_confirm':     ['B', 'provider.callback', 'Confirmation of a checkout already in flight, so a run already exists. The webhook that OPENS W16 is edge:stripe_webhook; treating both as new work would open two runs for one payment.'],
  'edge:stripe_webhook':     ['A', 'provider.payment_event', 'A payment event arriving from Stripe for an object with no run yet. Declared start of W16; the confirmation of a checkout already in flight is edge:stripe_confirm and is class B.'],
  'edge:sup_dob':            ['B', 'document.arrived_for_run', 'A supplier completing a file that already exists. The registration that opened the file is the class-A event; completion of it is a signal on that run.'],
  'edge:supplier_ack':       ['B', 'supplier.acknowledgement', 'One-click "I have contacted the customer" from the nudge email; sets supplier_ack_at and stops the nudges. K10 recorded it exactly: "a STEP EVENT inside an open W14 run (SLA-SUPPLIER-ACK, 4 hours), not the start of a workflow".'],
  'edge:supplier_api':       ['A', 'supplier.quotation_submitted', 'A supplier submitting a quotation for the first time. Declared start of W14 Quotation submission and evaluation; revisions to that quotation arrive through edge:supplier_portal and are class B.'],
  'edge:supplier_onboard':   ['A', 'supplier.registration_submitted', 'A supplier registering for the first time. Declared start of W09 Supplier onboarding; a status change on an invitation already sent is class B.'],
  'edge:supplier_portal':    ['B', 'supplier.quote_revision', 'The supplier portal surface. A supplier working inside an RFQ they were invited to is acting on a live run; the first submission arrives through edge:supplier_api.'],
  'edge:unsubscribe':        ['C', null, 'Consent withdrawal by HMAC link. K10 recorded NO_WORKFLOW_IN_REGISTRY: W13 ENFORCES consent, it does not begin when consent is withdrawn. Class C is used for its binding constraint — it may not create business work directly — and the reason is stated plainly rather than dressed up: a consent record is a legal record, not telemetry, and the handler owed to lifecycle_channel_operations is still owed.'],
  'edge:voice_otp':          ['D', null, 'DISABLED 18 Jul 2026 on a security finding; the deployed body is a 410 responder. Kept in the register so the history of what it did stays readable rather than vanishing.'],
  'edge:voice_otp_capture':  ['D', null, 'Retired alongside edge:voice_otp on 18 Jul 2026, same security finding, same 410 responder. Kept so the pair stays legible as one decision.'],
  'edge:wa_inbound':         ['A', 'customer.support_signal', 'An inbound WhatsApp message from a customer with no open run. Declared start of W18 Customer issue and retention.'],
  // ---- frontend paths: entry points, cut over through the edge function each one calls ---------
  'ui:/[locale]/contact':   ['A', 'customer.support_signal', 'The public contact route. It calls edge:contact_submit and is cut over BY that function: a browser cannot hold a service-role key and must never call the kernel directly.'],
  'ui:/[locale]/me':        ['B', 'clarification.response', 'The customer surface for inquiries that already exist. It calls edge:messages_api and edge:customer_documents, both class B, and is cut over by them.'],
  'ui:/[locale]/portal':    ['A', 'customer.inquiry_submitted', 'The customer portal route for submitting a new inquiry. It calls edge:customer_api and is cut over by it; the browser never calls the kernel directly.'],
  'ui:/[locale]/supplier':  ['A', 'supplier.registration_submitted', 'The supplier route. It calls edge:supplier_onboard for registration and edge:supplier_api for a first quotation, and is cut over by them.'],
  'ui:ChatWidget':          ['A', 'customer.support_signal', 'The site-wide chat widget. It calls edge:site_assistant and is cut over by it; a browser cannot hold a service-role key and must never reach the kernel directly.'],
};

export const CLASS_NAME = {
  A: 'NEW_WORK_REQUEST', B: 'EXISTING_WORKFLOW_SIGNAL',
  C: 'READ_ONLY_MONITOR', D: 'RETIRE_OR_HISTORICAL',
};
