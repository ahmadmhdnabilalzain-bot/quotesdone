-- The last workflow, and its generic "Execute" step stays manual
-- ==============================================================
--
-- Final classification slice of org_task #1394. employee_task is the generic employee work loop -
-- understand, analyse, plan, review, execute, verify, learn - and it is the reason the task exists:
-- 17 steps, none classified, 986 parked step-runs.
--
-- DEFINITION ONLY, NO RUN BACKFILL, for the same reason as customer_registration and more so. The
-- 986 parked runs carry NULL action_class; fn_workflow_step_sweep reads the RUN's class, not the
-- definition's, so leaving them alone means this change wakes nothing. Backfilling them would hand
-- ~986 steps to executors in a single sweep. Verified on customer_registration that a
-- definition-only update wakes exactly 0 runs.
--
-- Those 986 are also not work waiting to be done. Their sibling rows carry the note "the owning
-- task was performed and reviewed as one act; this step was never separately observed, so it is
-- skipped rather than claimed as done" - employee_task is a shadow of org_tasks, and the real work
-- unit is the task. Waking its shadow would re-run work that already happened.
--
--    1 Understand request       coordinate        medium -> agent
--    2 Check existing knowledge knowledge_acquire low/safe -> EXECUTOR
--    3 Collect missing info     coordinate        medium -> agent
--    4 Analyse                  recommend         low/safe -> EXECUTOR
--    5 Create plan              recommend         low/safe -> EXECUTOR
--    6 Assess risk              compliance_check  low/safe -> EXECUTOR
--    7 Consult other departments coordinate       medium -> agent
--    8 Generate recommendation  recommend         low/safe -> EXECUTOR
--    9 Self review              self_review       low/safe -> EXECUTOR
--   10 Department head review   coordinate        medium -> agent   (gate dept_head)
--   11 Chief of Staff review    coordinate        medium -> agent   (gate chief_of_staff)
--   12 EXECUTE                  coordinate        medium -> agent
--   13 Verify result            self_review       low/safe -> EXECUTOR
--   14 Measure KPI              metric_alerts     low/safe -> EXECUTOR
--   15 Learn                    knowledge_acquire low/safe -> EXECUTOR
--   16 Store memory             knowledge_acquire low/safe -> EXECUTOR
--   17 Improve future decisions recommend         low/safe -> EXECUTOR
--
-- Step 12 is the whole reason this needed care. "Execute" is a generic instruction to do whatever
-- the task said - it could be anything the company does - so it is the one step that must never
-- resolve to an automation. coordinate is medium and not advisory_safe, so the sweep cannot queue
-- it and an agent has to decide what executing actually means for that task. The three review
-- steps keep their gates and route to agents for the same reason.
--
-- Ten of ten workflows now carry a class on every step.

update public.workflow_step s set action_class = v.cls
  from (values
    (1,'coordinate'), (2,'knowledge_acquire'), (3,'coordinate'), (4,'recommend'),
    (5,'recommend'), (6,'compliance_check'), (7,'coordinate'), (8,'recommend'),
    (9,'self_review'), (10,'coordinate'), (11,'coordinate'), (12,'coordinate'),
    (13,'self_review'), (14,'metric_alerts'), (15,'knowledge_acquire'),
    (16,'knowledge_acquire'), (17,'recommend')
  ) as v(step_no, cls)
 where s.workflow_key = 'employee_task' and s.step_no = v.step_no and s.action_class is null;

-- NO workflow_step_run backfill. See the header.
