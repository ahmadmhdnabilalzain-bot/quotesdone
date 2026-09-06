-- ONLY A REFUND WAITS ON THE FOUNDER (6 Sep 2026, OS walk after PR #524).
--
-- Founder, verbatim: "nothing routes to my approval except refunds". Measured on production in his own
-- browser: Operating System & map listed four "Invoice Approval · step 8: Approve payment — waiting on
-- Cfo · gate: founder" rows, 10 hours old. workflow_step carried gate = 'founder' on FIVE steps:
--
--     refund/7               FOUNDER APPROVAL of a Stripe refund         his, stays
--     refund/8               execute the refund in Stripe                his, stays
--     invoice_approval/8     approve a supplier invoice for payment      NOT a refund
--     campaign_publishing/9  publish the approved campaign               NOT a refund
--     complaint/7            "escalate to the founder if the remedy is a refund or a suspension"
--
-- A founder-gated step is one fn_workflow_step_claim and fn_workflow_step_sweep exclude outright
-- (`coalesce(sr.input->>'gate','') <> 'founder'`), and fn_founder_queue lists only refund decisions —
-- so the four invoice runs (company_event 495263–495266, the receipts that book themselves, PR #522)
-- were waiting for an approval nobody could give and nobody could see. A dead end by definition.
--
-- The three non-refund gates become dept_head: the department head the step already names takes it
-- (Finance Director for the invoice, the marketing head for the campaign, the Customer Success
-- Director for the complaint). A complaint whose remedy IS a refund hands off to the refund workflow,
-- whose founder gate is the only one the company keeps. fn_workflow_start copies workflow_step.gate
-- into every new step run, so the change reaches future runs; the four open step runs are repaired in
-- place so the dispatcher can pick them up on its next tick.
--
-- Apply:  node scripts/apply_sql.mjs scripts/sql/only_a_refund_waits_on_the_founder.sql --apply
-- Prove:  select count(*) from workflow_step where gate='founder' and workflow_key<>'refund'  -> 0
--         select count(*) from workflow_step_run where input->>'gate'='founder' and finished_at is null -> 0
--         Operating System & map in the OS shows no "gate: founder" row.

update public.workflow_step s
   set gate = 'dept_head',
       action_class = case when s.action_class = 'escalate_founder' then 'coordinate' else s.action_class end,
       step = case when s.workflow_key = 'complaint' and s.step_no = 7
                   then 'Hand a refund remedy to the refund workflow (the only founder gate); decide a supplier suspension as department head'
                   else s.step end
 where (s.workflow_key, s.step_no) in (('invoice_approval', 8), ('campaign_publishing', 9), ('complaint', 7))
   and s.gate = 'founder';

update public.workflow_step_run sr
   set input = jsonb_set(coalesce(sr.input, '{}'::jsonb), '{gate}', '"dept_head"'::jsonb)
  from public.workflow_run r
 where r.id = sr.workflow_run_id
   and (r.workflow_key, sr.step_no) in (('invoice_approval', 8), ('campaign_publishing', 9), ('complaint', 7))
   and sr.input->>'gate' = 'founder'
   and sr.finished_at is null;
