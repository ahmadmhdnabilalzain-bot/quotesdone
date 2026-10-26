-- The step that refunds a card had no gate at all
-- ===============================================
--
-- Sixth and final classification slice of org_task #1394, covering the three money workflows.
-- payment, refund and invoice_approval all have ZERO workflow_step_run rows, so this fires nothing
-- today - but classifying them means the first payment or refund this company processes finds a
-- workflow that can move instead of one that freezes on step 1.
--
-- AND IT FOUND A GATE THAT WAS MISSING. The founder's standing rule is that Stripe refunds need
-- him. refund step 8 is "Execute the refund in Stripe and record refund_stripe_id,
-- refund_amount_aed, refund_confirmed_at" and its gate reads `none`. invoice_approval step 8,
-- "Approve payment", correctly carries `founder`. The single most irreversible step in the estate -
-- money leaving the company's Stripe account - was the one with no gate on it.
--
-- That is fixed here. gate='founder' makes fn_workflow_step_claim exclude the step outright (its
-- pick CTE filters `coalesce(sr.input->>'gate','') <> 'founder'`), so no dispatcher and no executor
-- can take it, whatever it is classified as. Classification and gate are belt and braces.
--
-- payment step 3, "Take payment through Stripe", is deliberately NOT founder-gated. Gating revenue
-- capture on the founder would block every sale the company ever makes, and the actual charge
-- happens in the app's Stripe checkout, not in this workflow. It routes to an agent instead.
--
-- Every money-touching step across all three workflows is classified to something with no safe
-- executor, so it reaches an agent and never an automation. Only reads and measurements automate:
--
--   invoice_approval  validate, check PO, check budget, detect fraud   compliance_check -> EXECUTOR
--                     check supplier standing                          recommend        -> EXECUTOR
--                     dashboard/KPI, learn                    metric_alerts/knowledge_acquire -> EXEC
--                     approve payment (founder), record in ledger, authority   coordinate -> agent
--   payment           compute the fee                                  recommend        -> EXECUTOR
--                     measure conversion                               metric_alerts    -> EXECUTOR
--                     take payment, write transaction, ledger/receipt  coordinate       -> agent
--                     start the response clock                         nudge            -> agent
--   refund            read fn_refund_state, verify non-response, record against supplier
--                                                                      recommend        -> EXECUTOR
--                     request, notify, wait, EXECUTE IN STRIPE, recover fee  coordinate -> agent
--
-- Nothing in this file lets any automation move a single fils.

update public.workflow_step s set gate = 'founder'
 where s.workflow_key = 'refund' and s.step_no = 8 and coalesce(s.gate,'none') = 'none';

update public.workflow_step s set action_class = v.cls
  from (values
    ('invoice_approval',1,'coordinate'),      ('invoice_approval',2,'compliance_check'),
    ('invoice_approval',3,'compliance_check'),('invoice_approval',4,'compliance_check'),
    ('invoice_approval',5,'coordinate'),      ('invoice_approval',6,'recommend'),
    ('invoice_approval',7,'compliance_check'),('invoice_approval',8,'coordinate'),
    ('invoice_approval',9,'coordinate'),      ('invoice_approval',10,'metric_alerts'),
    ('invoice_approval',11,'knowledge_acquire'),
    ('payment',1,'coordinate'), ('payment',2,'recommend'), ('payment',3,'coordinate'),
    ('payment',4,'coordinate'), ('payment',6,'coordinate'), ('payment',7,'nudge'),
    ('payment',8,'metric_alerts'),
    ('refund',1,'coordinate'),  ('refund',2,'recommend'),   ('refund',3,'coordinate'),
    ('refund',4,'coordinate'),  ('refund',5,'recommend'),   ('refund',8,'coordinate'),
    ('refund',9,'coordinate'),  ('refund',10,'recommend')
  ) as v(wf, step_no, cls)
 where s.workflow_key = v.wf and s.step_no = v.step_no and s.action_class is null;
