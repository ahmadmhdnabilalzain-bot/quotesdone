-- ABORTED-TRANSACTION PROBE: a verdict is a resting state, three misses park with a reason, and the
-- parked task is not claimed again (5 Sep 2026). Commits nothing.
--   node scripts/phase_c/q_tmp.mjs scripts/phase_c/probe_park_and_retry.sql
do $$
declare
  v_step bigint; v_task bigint; v_r1 text; v_r2 text; v_r3 text; t record; v_claimed jsonb; v_seen boolean;
  v_lane_max_attempts int; v_over3 int;
begin
  select sr.id, (r.context->>'task_id')::bigint into v_step, v_task
    from public.workflow_step_run sr join public.workflow_run r on r.id = sr.workflow_run_id
   where r.workflow_key = 'employee_task' and r.status = 'running' and sr.status = 'ready'
   order by sr.id limit 1;
  if v_step is null then raise exception 'PROBE {"skipped":"no ready employee_task step to probe"}'; end if;

  update public.workflow_step_run set status = 'running', started_at = now() where id = v_step;
  v_r1 := public.fn_workflow_step_release(v_step, 'no company playbook corroborated this task (probe)');
  update public.workflow_step_run set status = 'running', started_at = now() where id = v_step;
  v_r2 := public.fn_workflow_step_release(v_step, 'no company playbook corroborated this task (probe)');
  update public.workflow_step_run set status = 'running', started_at = now() where id = v_step;
  v_r3 := public.fn_workflow_step_release(v_step, 'no company playbook corroborated this task (probe)');

  select status, result->'parked'->>'reason' reason, result->'parked'->>'attempts' att,
         result->'parked'->>'knowledge_at_park' known into t
    from public.org_tasks where id = v_task;

  -- the parked task is not claimed again: claim a wide batch and look for it
  v_claimed := public.fn_workflow_step_claim(60);
  v_seen := exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_claimed) = 'array' then v_claimed else '[]'::jsonb end) e
                     where (e->>'step_run_id')::bigint = v_step);

  -- the retry budget across the lane: no lane-closed task carries more than 3 attempts
  select max(coalesce(attempts,0)), count(*) filter (where coalesce(attempts,0) > 3)
    into v_lane_max_attempts, v_over3
    from public.org_tasks where result->>'lane' = 'org_task';

  raise exception 'PROBE %', jsonb_pretty(jsonb_build_object(
    'step', v_step, 'task', v_task,
    'release_1', v_r1, 'release_2', v_r2, 'release_3', v_r3,
    'task_after', jsonb_build_object('status', t.status, 'reason', t.reason, 'attempts', t.att, 'knowledge_at_park', t.known),
    'claimed_again', v_seen,
    'lane_tasks_max_attempts', v_lane_max_attempts, 'lane_tasks_over_3_attempts', v_over3));
end $$;
