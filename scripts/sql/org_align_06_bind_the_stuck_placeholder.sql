-- ORG ALIGNMENT 06 — one queued step, addressed to nobody since 10 August.
--
-- MEASURED. workflow_step_run 1469: step 10 of employee_task, "Department head review", status
-- QUEUED, actor 'Director'. Its run (0b0d697d) is still `running`, entity company_event 1186,
-- context {"dept_key":"exec","title":"OS review [amber]: Leadership OS","task_id":1221,
-- "action_class":"exec_review","assigned_by":"approval_path"}.
--
-- 'Director' is employee_task's registry placeholder for "the department head", and it binds per
-- run. This one never bound, so a review has been sitting in a queue addressed to an identity
-- nobody models — the root cause this company keeps meeting, in its purest form: nothing failed,
-- nothing errored, and no watcher fired, because a queued row is a perfectly normal thing to be.
--
-- THIS IS A REPAIR, NOT A REWRITE. The row is bound to the employee the registry ALREADY
-- designates for it — org_departments.lead_agent for the run's own recorded dept_key — so the
-- placeholder resolves to exactly who it always meant. Nothing is back-dated, no status is
-- changed, and no row is closed. The 21 'skipped' step runs keep their placeholders untouched: a
-- step that never executed keeps what it had, and rewriting them to make a check green is the one
-- thing that must not happen.
--
-- trg_step_run_actor_is_a_real_employee (org_align_05) makes this unrepeatable: a step run cannot
-- be queued, running or ok with an actor that resolves to nobody.

begin;

update workflow_step_run sr
   set actor = d.lead_agent
  from workflow_run r
  join org_departments d on d.dept_key = r.context->>'dept_key' and d.active
 where sr.workflow_run_id = r.id
   and sr.status in ('queued', 'running')
   and coalesce(public.fn_org_agent_resolve(sr.actor), public.fn_org_role_resolve(sr.actor)) is null
   and d.lead_agent is not null;

commit;
