-- The demand path can now be walked by something
-- ==============================================
--
-- Second slice of org_task #1394, after supplier_onboarding. rfq_handling is the workflow the whole
-- company exists to run - inquiry in, matched suppliers, quotes compared, winner recommended - and
-- not one of its twelve steps carried an action_class, so if an RFQ arrived tomorrow the workflow
-- would park on step 1 and never move.
--
-- ZERO BLAST RADIUS. rfq_handling has no workflow_step_run rows at all (0 queued, 0 ready): with no
-- customers and no inquiries it has never been instantiated. Classifying it fires nothing today and
-- makes the path executable for the first inquiry that arrives.
--
-- Each step checked against the ACTIVE executor registry before assigning. A class whose executor
-- is low-risk, advisory-safe, reversible and non-notifying gets automated by
-- fn_workflow_step_sweep; anything else routes to the LLM dispatcher instead.
--
--    1 Receive inquiry       qualify_inquiry   low/safe      -> EXECUTOR
--    2 Detect category       route_category    low/safe      -> EXECUTOR
--    3 Collect missing data  coordinate        medium        -> agent
--    4 Review completeness   coordinate        medium        -> agent   (gate dept_head)
--    5 Select suppliers      match_inquiry     low/safe      -> EXECUTOR
--    6 Send RFQ              coordinate        medium        -> agent
--    7 Receive quotes        coordinate        medium        -> agent
--    8 Compare quotes        compare_quotes    low/safe      -> EXECUTOR
--    9 Recommend winner      recommend         low/safe      -> EXECUTOR (gate dept_head)
--   10 Close inquiry         coordinate        medium        -> agent
--   11 Collect feedback      coordinate        medium        -> agent
--   12 Improve               knowledge_acquire low/safe      -> EXECUTOR
--
-- STEP 6 IS DELIBERATELY NOT AUTOMATED. "Send RFQ" puts a message in front of real suppliers, and
-- the only classes that could carry it (nudge, dispatch_inquiry) either notify humans or have no
-- active executor. It routes to an agent, so the first RFQ this company ever sends is composed by
-- something that reasoned about it rather than fired automatically. Steps 3, 7, 10 and 11 are
-- judgement or waiting, not automation. Step 9 recommends and does not award - `recommend` is
-- advisory-safe and reversible, and the dept_head gate is untouched.
--
-- Nothing here moves money. payment, refund and invoice_approval remain unclassified on purpose.

update public.workflow_step s set action_class = v.cls
  from (values
    (1,'qualify_inquiry'), (2,'route_category'), (3,'coordinate'), (4,'coordinate'),
    (5,'match_inquiry'),   (6,'coordinate'),     (7,'coordinate'), (8,'compare_quotes'),
    (9,'recommend'),       (10,'coordinate'),    (11,'coordinate'),(12,'knowledge_acquire')
  ) as v(step_no, cls)
 where s.workflow_key = 'rfq_handling' and s.step_no = v.step_no and s.action_class is null;
