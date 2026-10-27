---
name: revenue-loop-entry-was-a-vocabulary-mismatch
description: "the marketplace's entry workflow (rfq_handling) could never start because it waited on inquiry.created while inquiries emit rfq.created — fixed 3 Sep 2026; the full dead-workflow map is here"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T00:37:01.380Z
---

Fixed 3 Sep 2026 ([[fix_rfq_handling_trigger_event.sql]]). The RFQ Handling workflow (`workflow_key
= 'rfq_handling'`) — the 18-step money loop (qualify → route → BOQ/drawing → privacy review →
**match** → notify → receive quotes → **compare** → recommend winner → close → feedback → improve)
— was defined with `trigger_event = 'inquiry.created'`, but the AFTER-INSERT trigger on
`public.inquiries` (`trg_event_inquiry`) fires `fn_emit_event('inquiry','rfq.created')`.
`fn_workflow_start_due` (cron 195) joins `workflow.trigger_event = company_event.event_type` EXACTLY,
so the inquiry emitted `rfq.created`, the workflow waited for `inquiry.created`, and the loop's entry
was dead. `rfq.created` is canonical — on 2026-08-10 the agent `event_subscription` rows were moved
`inquiry.created`→`rfq.created`; the workflow spine was the consumer that correction missed.
Proven end-to-end in an aborted tx: inquiry INSERT → rfq.created → rfq_handling run created
(0→1, key `rfq_handling:<evid>`, running, step 1). This is the [[a-sibling-path-that-never-got-the-lexicon]]
shape again. Related: [[two-gates-one-vocabulary-nothing-keeps-them-in-step]].

rfq_handling steps bind to REAL edge executors (org_action_executor): match_inquiry→**match**,
compare_quotes→**quote_compare**, route_category→**route_inquiry**, qualify_inquiry→**inquiry_ai**,
coordinate→**cos_execute** (now deterministic-first), recommend→analytics_recommend,
compliance_check→compliance_archive, knowledge_acquire→kb_deepen. So the workflow drives the actual
marketplace, not just org process.

THE DEAD-WORKFLOW MAP (7 workflows whose trigger events showed ever_emitted=false):
- `rfq_handling`/inquiry.created → **FIXED** to rfq.created.
- `refund`/refund.requested → correctly wired (trg_emit_refund_requested); 0 rows, fires on a real refund.
- `complaint`/customer.complaint → emitted by a live `fn_emit('customer.complaint',...)`; awaits an occurrence.
- `supplier_suspension`/supplier.suspension_proposed → emitted by a live fn_emit; awaits an occurrence.
- `lead_to_customer`/lead.qualified → NO emitter (customer-lead funnel not built; `leads` is SUPPLIER leads). Aspirational.
- `invoice_approval`/invoice.received → NO emitter yet; the real path is finance ingesting expense invoices from expenses@quotesdone.com. Buildable.
- `contract_review`/contract.submitted → NO emitter yet. Check supplier-contract path.

Latent (not yet a defect): `fn_workflow_start_due` does `order by e.id limit 200` over the lookback
window — fine at 96 events/24h, would silently defer the newest if a window ever exceeds 200.
