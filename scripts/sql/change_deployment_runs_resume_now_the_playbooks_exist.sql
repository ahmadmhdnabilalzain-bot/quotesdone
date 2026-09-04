-- THE PARKED change_deployment RUNS RESUME, BECAUSE THE REASON THEY PARKED IS GONE (4 Sep 2026).
--
-- fn_workflow_step_release parks a step as disposition='awaiting_model' after three deterministic
-- attempts that found no company playbook, and fn_workflow_step_claim then refuses to claim it again
-- "until the hold lifts". That is the correct behaviour for a step nothing covers — never an endless
-- retry, never the same value as success.
--
-- It is the WRONG state for a step something now covers. All 26 change_deployment runs parked on step
-- 1 with this recorded reason:
--
--   "no company playbook or rule confidently covers this step (no corroborated actionable match:
--    nearest is exception_playbook 'Marketing exception 08 — User changes material requirements
--    mid-workflow' at 0.843 (floor 0.85, noise median 0.837) sharing 1 of 7 step terms)"
--
-- change_deployment_has_a_playbook_for_every_step.sql wrote the nine records that sentence says are
-- missing, and cron 315 embedded them with the free in-region gte-small. Measured through
-- fn_apply_playbook itself, at its real floor of 0.85 and k=20, for the seat that works each step
-- (scripts/kb/probe_change_deployment_playbooks.mjs):
--
--   step 1 optimisation_eng 0.9137  7/7 terms      step 6 cto         0.9087  4/4 terms
--   step 2 cto              0.9226  8/8 terms      step 7 qa_manager  0.9457 11/11 terms
--   step 3 eng_manager      0.9009  3/3 terms      step 8 cto         0.9212  3/3 terms
--   step 4 qa_manager       0.9473 12/12 terms     step 9 cpo         0.9343  8/8 terms
--   step 5 qa_manager       0.9136 13/13 terms
--
-- So the park is now stale evidence, and this file clears it — for change_deployment only, and only
-- while every one of the nine records is actually embedded. Nothing about the floor, the corroboration
-- rule, the release logic or any other workflow is touched: if the applier still refuses, the step
-- parks again on its own after three fresh attempts, with its own new reason.
--
-- The attempt counter is reset to 0 because the three attempts it counts were spent against a
-- substrate that did not contain the answer. The previous error is kept under previous_error rather
-- than overwritten, so what the step said while it was parked stays readable.
--
-- Idempotent: a step that is no longer parked no longer matches the predicate.
--
--   node scripts/apply_sql.mjs scripts/sql/change_deployment_runs_resume_now_the_playbooks_exist.sql --apply --ddl

begin;

do $$
declare v_embedded int; v_unparked int;
begin
  -- REFUSE TO UNPARK INTO AN EMPTY SUBSTRATE. Without this, a half-embedded knowledge write would
  -- release 26 runs to burn three fresh attempts each and re-park with the same reason.
  select count(*) into v_embedded
    from public.ops_knowledge
   where record_id like 'ops-change-deployment-step-%'
     and embedding_gte is not null and runtime_eligible and supersession_state = 'current'
     and record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook');
  if v_embedded <> 9 then
    raise exception 'refusing to unpark: % of 9 change_deployment playbooks are embedded and actionable', v_embedded;
  end if;

  update public.workflow_step_run sr
     set attempts = 0,
         error = jsonb_build_object(
           'unparked_at',  now(),
           'unparked_by',  'change_deployment_runs_resume_now_the_playbooks_exist.sql',
           'disposition',  'retry',
           'reason',       'parked as awaiting_model because no company playbook covered this step; '
                        || 'the nine change_deployment playbooks now exist in ops_knowledge and are '
                        || 'embedded, and fn_apply_playbook returns a corroborated actionable match '
                        || 'for every step at 0.90-0.95 against its 0.85 floor',
           'previous_error', sr.error)
    from public.workflow_run r
   where r.id = sr.workflow_run_id
     and r.workflow_key = 'change_deployment'
     and r.status = 'running'
     and sr.status = 'ready'
     and sr.finished_at is null
     and sr.error->>'disposition' = 'awaiting_model';
  get diagnostics v_unparked = row_count;

  raise notice 'unparked % change_deployment step(s) against 9 embedded playbooks', v_unparked;
end $$;

-- Proof, in the same transaction: no change_deployment step is left parked awaiting the model.
do $$
declare v_left int;
begin
  select count(*) into v_left
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where r.workflow_key = 'change_deployment'
     and sr.finished_at is null
     and sr.error->>'disposition' = 'awaiting_model';
  if v_left > 0 then
    raise exception '% change_deployment step(s) are still parked awaiting_model', v_left;
  end if;
  raise notice 'proof: 0 change_deployment steps parked awaiting_model';
end $$;

commit;
