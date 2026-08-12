-- The workflow that can ban a supplier automates only the reading
-- ===============================================================
--
-- Fourth slice of org_task #1394. supplier_suspension has zero workflow_step_run rows, so this
-- fires nothing today - but it is the most consequential workflow classified so far: its steps end
-- in matching_blocked or banned on a real company's account, and one of them closes a whole
-- category if the supplier was the only one in it.
--
-- There is no blocking executor in org_action_executor at all, which is the right state: nothing in
-- this estate should be able to ban a supplier without an agent reasoning about it first. So every
-- consequential step here is classified to something with NO safe executor and routes to the
-- dispatcher. Only three steps automate, and all three are read-only:
--
--    1 Suspension proposed        coordinate            medium -> agent
--    2 Gather the evidence        recommend             low/safe -> EXECUTOR (read-only)
--    3 Verify licence/documents   supplier_verify       medium -> agent
--    5 Risk and governance sign-off coordinate          medium -> agent      (gate authority)
--    6 Decide block or ban        resolve_within_policy medium -> agent      (gate dept_head)
--    7 APPLY THE BLOCK            coordinate            medium -> agent
--    8 Tell the supplier          coordinate            medium -> agent
--    9 Handle the appeal          resolve_within_policy medium -> agent      (gate dept_head)
--   10 Check category coverage    recommend             low/safe -> EXECUTOR (read-only)
--   11 Learn                      knowledge_acquire     low/safe -> EXECUTOR
--
-- Step 7 is the destructive one and it deliberately gets `coordinate` rather than a
-- suspension-shaped class: coordinate is medium and not advisory_safe, so fn_workflow_step_sweep
-- cannot queue it to an executor, and naming it something that sounds like an automation would
-- invite someone to build one later. Step 8 speaks to the supplier, so it routes to an agent for
-- the same reason as complaint's steps 3 and 8. Step 10 is the one that catches the real damage -
-- suspending the only supplier in a category closes the category - and it is safe to automate
-- because it only measures.
--
-- payment, refund and invoice_approval remain unclassified. They move money.

update public.workflow_step s set action_class = v.cls
  from (values
    (1,'coordinate'), (2,'recommend'), (3,'supplier_verify'), (5,'coordinate'),
    (6,'resolve_within_policy'), (7,'coordinate'), (8,'coordinate'),
    (9,'resolve_within_policy'), (10,'recommend'), (11,'knowledge_acquire')
  ) as v(step_no, cls)
 where s.workflow_key = 'supplier_suspension' and s.step_no = v.step_no and s.action_class is null;
