-- Two more workflows, and nothing that talks to a customer fires itself
-- ====================================================================
--
-- Third slice of org_task #1394, after supplier_onboarding and rfq_handling. complaint and
-- campaign_publishing both have ZERO workflow_step_run rows, so classifying them fires nothing
-- today; it makes the paths executable the first time either is instantiated.
--
-- Every class below was checked against the ACTIVE executor registry first, because the class is
-- what decides whether fn_workflow_step_sweep automates the step or fn_workflow_step_claim hands
-- it to an agent. The rule applied throughout: ANYTHING THAT PUTS WORDS IN FRONT OF A CUSTOMER
-- ROUTES TO AN AGENT, never to an executor.
--
-- campaign_publishing
--    1 Create campaign brief   content_calendar  low/safe   -> EXECUTOR
--    2 Research audience       recommend         low/safe   -> EXECUTOR
--    3 Generate ideas          content_draft     low/safe   -> EXECUTOR
--    4 Create content          content_draft     low/safe   -> EXECUTOR
--    5 Create creative         content_draft     low/safe   -> EXECUTOR
--    6 Brand review            brand_scan        low/safe   -> EXECUTOR
--    7 Quality review          qa_gate           low/safe   -> EXECUTOR   (gate dept_head)
--    8 Chief of Staff approval coordinate        medium     -> agent      (gate chief_of_staff)
--    9 Publish                 outreach_send     HIGH, not advisory_safe, NOT REVERSIBLE,
--                                                notifies_human -> agent  (gate founder)
--   10 Collect analytics       metric_alerts     low/safe   -> EXECUTOR
--   11 Analyse and improve     recommend         low/safe   -> EXECUTOR
--   12 Store learning          knowledge_acquire low/safe   -> EXECUTOR
--
-- Step 9 is the irreversible one and it is doubly held: outreach_send fails the safe-executor test
-- on three attributes at once, and fn_workflow_step_claim excludes founder-gated steps outright, so
-- neither consumer can take it. Publishing stays the founder's act. Drafting, reviewing and
-- measuring around it are all automated, which is the right split - the machine writes and checks,
-- the human sends.
--
-- complaint
--    1 Complaint received      coordinate           medium -> agent
--    2 Classify severity       compliance_check     low/safe -> EXECUTOR
--    3 Acknowledge to customer coordinate           medium -> agent
--    4 Investigate the record  recommend            low/safe -> EXECUTOR
--    6 Decide the remedy       resolve_within_policy medium -> agent      (gate dept_head)
--    8 Execute remedy + tell   coordinate           medium -> agent
--    9 Trace the cause         incident_fix         medium -> agent
--   10 Re-check the KPI        metric_alerts        low/safe -> EXECUTOR
--
-- Steps 3 and 8 both speak to a complaining customer, so both route to an agent even though
-- outreach_draft would have passed the safe test - drafting is safe, but the step as written says
-- acknowledge and tell, not draft, and classifying it as a drafting action would quietly change
-- what the step means. Deciding the remedy (6) is resolve_within_policy, which is medium and not
-- advisory-safe, so a remedy is reasoned about and never issued automatically.
--
-- payment, refund and invoice_approval remain unclassified. They move money.

update public.workflow_step s set action_class = v.cls
  from (values
    ('campaign_publishing',1,'content_calendar'), ('campaign_publishing',2,'recommend'),
    ('campaign_publishing',3,'content_draft'),    ('campaign_publishing',4,'content_draft'),
    ('campaign_publishing',5,'content_draft'),    ('campaign_publishing',6,'brand_scan'),
    ('campaign_publishing',7,'qa_gate'),          ('campaign_publishing',8,'coordinate'),
    ('campaign_publishing',9,'outreach_send'),    ('campaign_publishing',10,'metric_alerts'),
    ('campaign_publishing',11,'recommend'),       ('campaign_publishing',12,'knowledge_acquire'),
    ('complaint',1,'coordinate'),                 ('complaint',2,'compliance_check'),
    ('complaint',3,'coordinate'),                 ('complaint',4,'recommend'),
    ('complaint',6,'resolve_within_policy'),      ('complaint',8,'coordinate'),
    ('complaint',9,'incident_fix'),               ('complaint',10,'metric_alerts')
  ) as v(wf, step_no, cls)
 where s.workflow_key = v.wf and s.step_no = v.step_no and s.action_class is null;
