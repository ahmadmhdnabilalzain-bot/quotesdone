-- DRAIN THE WORKFLOW BACKLOG HONESTLY (4 Sep 2026) — every close below carries its reason on the row.
--
-- What was MEASURED before this file (production, 05:13 UTC):
--   employee_task runs 'running' = 149, of which the owning org_task was
--     cancelled 80 (Aug 10-15: stand-down cancellations; fn_workflow_run_follow_task only knew
--                   done/failed/escalated, so a cancelled task left its run running forever),
--     done      31 (the task finished before the follow trigger existed, or the run was raised after),
--     assigned/in_progress 37 (live: waiting for the org_task lane — NOT touched here),
--   failed runs 40 with 155 step runs still 'queued' behind the failed step (never finished, counted
--   by never_finished, and picked at nothing).
--
-- Nothing here marks a step DONE: a run whose task was cancelled closes as cancelled; a run whose task
-- was done closes exactly as the follow trigger would have (steps skipped, 'closed_by owning_org_task');
-- a failed run's queued tail is skipped with the failed step named. Idempotent: every predicate names
-- the stale state, so a second apply finds nothing.
--
--   node scripts/apply_sql.mjs scripts/sql/workflow_backlog_drain_2026_09_04.sql --apply --ddl

begin;

do $$
declare v_cancel int := 0; v_done int := 0; v_tail int := 0; v_steps int := 0;
begin
  -- 1. employee_task runs whose owning org_task is CANCELLED -> run cancelled, open steps skipped.
  with r as (
    select r.id, (r.context->>'task_id')::bigint task_id
      from public.workflow_run r
      join public.org_tasks t on t.id::text = r.context->>'task_id'
     where r.workflow_key = 'employee_task' and r.status = 'running' and t.status = 'cancelled'
  ), s as (
    update public.workflow_step_run sr
       set status = 'skipped', finished_at = now(),
           output = coalesce(sr.output,'{}'::jsonb) || jsonb_build_object(
             'closed_by', 'workflow_backlog_drain_2026_09_04', 'org_task_id', r.task_id,
             'org_task_status', 'cancelled',
             'note', 'the owning task was cancelled (company stand-down, Aug 2026); this step was never separately observed, so it is skipped rather than claimed as done')
      from r where sr.workflow_run_id = r.id and sr.finished_at is null
    returning sr.id
  ), u as (
    update public.workflow_run wr
       set status = 'cancelled', finished_at = now(), updated_at = now(),
           context = coalesce(wr.context,'{}'::jsonb) || jsonb_build_object('closed_by','workflow_backlog_drain_2026_09_04','org_task_status','cancelled'),
           error = jsonb_build_object('owning_org_task', r.task_id, 'org_task_status', 'cancelled',
                                      'reason', 'the owning org_task was cancelled; drained 4 Sep 2026')
      from r where wr.id = r.id
    returning wr.id
  )
  select (select count(*) from u), (select count(*) from s) into v_cancel, v_steps;
  raise notice 'employee_task runs closed as cancelled: % (% steps skipped)', v_cancel, v_steps;

  -- 2. employee_task runs whose owning org_task is DONE -> exactly the follow trigger's close.
  with r as (
    select r.id, t.id task_id, t.result
      from public.workflow_run r
      join public.org_tasks t on t.id::text = r.context->>'task_id'
     where r.workflow_key = 'employee_task' and r.status = 'running' and t.status = 'done'
  ), s as (
    update public.workflow_step_run sr
       set status = 'skipped', finished_at = now(),
           output = coalesce(sr.output,'{}'::jsonb) || jsonb_build_object(
             'closed_by', 'owning_org_task', 'org_task_id', r.task_id, 'org_task_status', 'done',
             'used_llm', case when (r.result->>'used_llm') in ('true','false') then (r.result->>'used_llm')::boolean else null end,
             'note', 'the owning task was performed and reviewed as one act; this step was never separately observed, so it is skipped rather than claimed as done (drained 4 Sep 2026: the task closed before the follow trigger could see it)')
      from r where sr.workflow_run_id = r.id and sr.finished_at is null
    returning sr.id
  ), u as (
    update public.workflow_run wr
       set status = 'done', finished_at = now(), updated_at = now(), error = null,
           context = coalesce(wr.context,'{}'::jsonb) || jsonb_build_object('closed_by','owning_org_task','org_task_status','done','drained_by','workflow_backlog_drain_2026_09_04')
      from r where wr.id = r.id
    returning wr.id
  )
  select (select count(*) from u), (select count(*) from s) into v_done, v_steps;
  raise notice 'employee_task runs closed as done behind a done task: % (% steps skipped)', v_done, v_steps;

  -- 3. failed runs: the queued tail behind the failed step can never be picked; skip it, naming the step.
  update public.workflow_step_run sr
     set status = 'skipped', finished_at = now(),
         output = coalesce(sr.output,'{}'::jsonb) || jsonb_build_object(
           'closed_by', 'workflow_backlog_drain_2026_09_04',
           'note', 'the run failed at step ' || coalesce(r.error->>'failed_step', r.current_step::text)
                   || ' (' || coalesce(r.error->>'reason', r.error->>'status', 'failed') || '); this queued tail step was never reached')
    from public.workflow_run r
   where r.id = sr.workflow_run_id and r.status = 'failed'
     and sr.finished_at is null and sr.status = 'queued';
  get diagnostics v_tail = row_count;
  raise notice 'queued tail steps of failed runs skipped: %', v_tail;
end $$;

commit;
