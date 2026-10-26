-- comp-09-workflows — five of fourteen active workflows carried an ENGLISH SENTENCE in
-- trigger_event. fn_workflow_start_due joins `workflow w on w.trigger_event = e.event_type`, so a
-- sentence can never match anything: those workflows were unreachable by construction, and the
-- population check passed them because it only asked `trigger_event <> ''`.
--
-- Each prose trigger is replaced with the token its own OS already declares in os_interface. No
-- new vocabulary is invented and no run is manufactured — four of these tokens have still never
-- fired, and os_interface already carries the dated, written reason why (planned_until 2026-11-04).
--
--   invoice_approval    'a supplier invoice arrives'   -> invoice.received   (finance input;
--                        step 1 is literally "Invoice arrives"; emitter fn_emit_invoice_received
--                        is live on a trigger, production simply has zero invoices)
--   rfq_handling        'a buyer submits an inquiry'   -> inquiry.created    (marketplace input;
--                        step 1 "Receive inquiry")
--   supplier_onboarding 'a supplier applies to join'   -> supplier.applied   (marketplace input;
--                        step 1 "Application received"; emitter fn_emit_supplier_applied is live
--                        on leads AFTER UPDATE, and 0 leads have registration_submitted_at set)
--   campaign_publishing 'a campaign or post is proposed'-> campaign.published (commercial input).
--                        NOT content.published: fn_review_submit emits that at the END of the
--                        review chain, which is this workflow's own step 9 "Publish". Triggering
--                        the workflow on its own output would have produced 20 runs whose first
--                        eight steps had already happened — a record of work that never moved.
--
-- employee_task keeps NO trigger. "Standard Employee Task Loop" is the canonical procedure every
-- employee follows per assigned task; org_tasks has 612 rows and FOURTEEN routines write it, but
-- nothing announces a task assignment on the bus and the vocabulary has no token for one. Prose
-- there was a claim of a trigger that does not exist, so the column is set NULL and the intent
-- stays in `description` where it already reads "The canonical loop every employee follows...".
-- This is an honest gap, and comp-09-workflows now reports it instead of accepting the sentence.

update public.workflow set trigger_event = 'invoice.received'    where workflow_key = 'invoice_approval';
update public.workflow set trigger_event = 'inquiry.created'     where workflow_key = 'rfq_handling';
update public.workflow set trigger_event = 'supplier.applied'    where workflow_key = 'supplier_onboarding';
update public.workflow set trigger_event = 'campaign.published'  where workflow_key = 'campaign_publishing';
update public.workflow set trigger_event = null                  where workflow_key = 'employee_task';
