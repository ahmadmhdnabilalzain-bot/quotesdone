-- 957 PLANNED STEPS THAT NO EXECUTOR COULD EVER MATCH.
--
-- fn_workflow_step_sweep raises an org_task called "Classify the workflow steps no executor can
-- run" and has been raising it for days. This is what it is about, measured on production:
--
--   workflow_step_run, action_class IS NULL, status in ('ready','queued'):   957 rows
--   of which the row's OWN workflow_step definition carries an action_class: 957 rows
--
-- Every single one is recoverable from its own definition. Not one needs classifying by a human or
-- a model — the answer was already in workflow_step the whole time:
--
--   employee_task        step 1 "Understand request"      -> coordinate
--   customer_registration step 1 "Registration submitted" -> coordinate
--
-- WHY THEY ARE NULL, AND WHY THE WRITER IS NOT THE BUG. fn_workflow_start plans every step up front
-- and DOES copy `s.action_class` from workflow_step. It is correct today. These rows are older than
-- the definitions: the workflow_step rows were given their action_class after these runs had
-- already been planned, so the copies are stale rather than wrong. Nothing in the code needs
-- changing — workflow_step now has 0 rows with a null action_class, so newly planned steps inherit
-- it correctly and this cannot recur from the same cause.
--
-- WHAT IT WAS COSTING. 89 employee_task runs, 13 customer_registration and 7 strategic_review sit
-- at status 'running', step 1, attempts 0 — never attempted, no error, no retry. The dispatcher
-- selects on action_class, so a NULL step is not refused with a reason, it is never selected. This
-- is the shape this codebase has named before: a condition that can never fire, invisible because
-- nothing failed.
--
-- SPEND IMPACT: NONE, AND THAT IS MEASURED, NOT ASSUMED. Every one of these steps is throttled by
-- decision_policy.workflow_reflection_steps_per_day, which was ALREADY fully consumed every day
-- before this change — workflow_dispatch ran 24.3 calls/day against a ceiling of 24. The ceiling
-- binds, not the queue depth, so making more steps eligible changes WHICH step is picked, not how
-- many. Demand-linked steps are exempt from the ceiling by design and run regardless; with 0
-- inquiries and 0 quotes there are effectively none today, and when there are, revenue work
-- reaching its executor is the point.
--
-- SAFETY CHECKED BEFORE UNBLOCKING, per the standing rule that an executor can be low-risk,
-- advisory-safe and reversible and STILL email the founder. All six executors involved:
--
--   coordinate        edge cos_execute            active  notifies_human = false
--   recommend         edge analytics_recommend    active  notifies_human = false
--   knowledge_acquire edge kb_deepen              active  notifies_human = false
--   self_review       rpc  fn_self_review         active  notifies_human = false
--   compliance_check  edge compliance_archive     active  notifies_human = false
--   metric_alerts     rpc  fn_emit_metric_alerts  active  notifies_human = false
--
-- Not one notifies a human. Nothing here can reach the founder's inbox.
--
-- ONLY UNSTARTED ROWS. status in ('ready','queued') and action_class is null. A 'done', 'failed' or
-- 'skipped' row is history and is left exactly as it is — 387 done and 16 failed rows already carry
-- a non-null action_class anyway, so there is nothing to repair there and rewriting a finished
-- row's class would be falsifying the record of what ran.
--
-- NOTHING IS INVENTED. The value comes from the workflow's own step definition, joined on
-- (workflow_key, step_no). A step whose definition is also null is left null and stays visible to
-- the sweep — there are none today, and if one appears it should be classified, not guessed.

update workflow_step_run sr
   set action_class = ws.action_class
  from workflow_run r
  join workflow_step ws on ws.workflow_key = r.workflow_key
 where r.id = sr.workflow_run_id
   and ws.step_no = sr.step_no
   and sr.action_class is null
   and ws.action_class is not null
   and sr.status in ('ready','queued');
