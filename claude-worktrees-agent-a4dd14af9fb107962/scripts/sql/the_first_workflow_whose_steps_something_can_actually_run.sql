-- The first workflow whose steps something can actually run
-- =========================================================
--
-- org_task #1394 records the finding: ten workflow definitions - employee_task, rfq_handling,
-- payment, refund, complaint, supplier_onboarding, customer_registration, invoice_approval,
-- campaign_publishing, supplier_suspension - carry NO action_class on any step, so nothing can ever
-- pick them up and 67 ready step-runs sit permanently unclaimable. The company's operating model is
-- written down as workflows that cannot execute.
--
-- Classifying all ten at once would make ~1,049 queued steps become executable simultaneously, and
-- `refund` reaches Stripe. So this does ONE workflow, chosen because it is the smallest and the
-- least dangerous: supplier_onboarding has 7 step-runs in total (6 queued, 1 ready) across a single
-- workflow run, and touches no money.
--
-- WHAT A CLASS ACTUALLY DECIDES. There are two consumers and the class picks between them:
--   * fn_workflow_step_sweep queues a step to a REAL EXECUTOR when one exists that is kind='edge',
--     risk_tier='low', advisory_safe, reversible and NOT notifies_human;
--   * fn_workflow_step_claim hands the step to the LLM dispatcher when no such executor exists.
-- A class with no safe executor is therefore not a gap - it routes the step to an agent to reason
-- about instead of to an automation. Both are better than NULL, which routes it nowhere.
--
-- Each step checked against org_action_executor before assigning:
--
--   1 Application received                 coordinate           medium, not advisory_safe -> agent
--   2 Verify trade licence                 supplier_verify      medium, not advisory_safe -> agent
--   3 Verify certifications and capability capability_review    notifies_human            -> agent
--   4 Compliance screen                    compliance_check     low/safe/reversible       -> EXECUTOR
--   5 Approve or reject                    supplier_approve_clean  medium, gate dept_head -> agent
--   6 Activate and coach                   coordinate           medium                    -> agent
--   7 Measure and learn                    knowledge_acquire    low/safe/reversible       -> EXECUTOR
--
-- Only steps 4 and 7 become automated, and both are low-risk, advisory-safe, reversible and
-- non-notifying. Step 5 keeps its dept_head gate and is not founder-gated, so it reaches the
-- dispatcher rather than an executor - approval stays a reasoned act, not an automatic one.
--
-- The existing 7 step-runs are backfilled from the definition, because action_class is copied at
-- creation and rows made before today carry NULL. Without that the fix would only apply to
-- workflow runs started in future, and the 7 already parked would stay parked - the exact shape of
-- defect this session has been finding all day.

update public.workflow_step s set action_class = v.cls
  from (values
    (1, 'coordinate'),
    (2, 'supplier_verify'),
    (3, 'capability_review'),
    (4, 'compliance_check'),
    (5, 'supplier_approve_clean'),
    (6, 'coordinate'),
    (7, 'knowledge_acquire')
  ) as v(step_no, cls)
 where s.workflow_key = 'supplier_onboarding'
   and s.step_no = v.step_no
   and s.action_class is null;

-- Backfill the runs already parked against those steps.
update public.workflow_step_run sr set action_class = s.action_class
  from public.workflow_run r, public.workflow_step s
 where sr.workflow_run_id = r.id
   and r.workflow_key = 'supplier_onboarding'
   and s.workflow_key = r.workflow_key
   and s.step_no = sr.step_no
   and sr.action_class is null
   and s.action_class is not null
   and sr.status in ('queued','ready');
