-- THE PROMOTER RAISED ON EVERY CALL AND ITS CALLERS SWALLOWED IT (4 Sep 2026).
--
-- fn_org_task_promote is the leg of MASTER_PLAN 4.3 that lifts an org_task onto the workflow spine.
-- It has never once run: its plpgsql `declare r record` shadows the table alias in
-- `select count(*) ... from public.workflow_run r where r.workflow_key = ...`, so PostgreSQL resolves
-- r.workflow_key against the RECORD and raises 42703 "record r has no field workflow_key" on every
-- call, before any row is read. Measured by aborted-transaction probe, and confirmed by the absence
-- it predicts: 0 of the 301 employee_task runs ever created carry context->>'promoted_by' =
-- 'fn_org_task_promote'.
--
-- It is called by fn_org_task_assign, fn_org_task_deterministic_done and fn_workflow_step_release --
-- all three in the live loop, all three still working, which means all three swallow the exception.
-- A caught error that returns a success-looking value is the shape MASTER_PLAN 5.2 #12 names as the
-- most common defect in this estate, and this is it: the lane reported itself healthy while its
-- promotion leg had never executed a single statement.
--
-- The fix is the alias, nothing else: workflow_run is aliased wr where the RECORD is named r.
--
--   node scripts/apply_sql.mjs scripts/sql/the_promoter_raised_on_every_call.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_org_task_promote(p_limit integer DEFAULT 12, p_in_flight_ceiling integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_run uuid;
  v_unparked int := 0; v_promoted int := 0; v_in_flight int; v_room int; v_backlog int;
begin
  -- (1) un-park what the company has since learned how to do
  for r in
    select t.id, t.dept_key, coalesce((t.result->'parked'->>'knowledge_at_park')::int, 0) was
      from public.org_tasks t
     where t.status = 'blocked' and (t.result ? 'parked')
     order by t.id
     limit 200
  loop
    if public.fn_org_task_lane_knowledge(r.dept_key) > r.was then
      update public.org_tasks
         set status = 'assigned', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'unparked', jsonb_build_object('at', now(),
                 'knowledge_at_park', r.was,
                 'knowledge_now', public.fn_org_task_lane_knowledge(r.dept_key),
                 'reason', 'the department now holds more actionable in-scope knowledge than when this parked'))
       where id = r.id;
      update public.workflow_step_run sr
         set status = 'ready', attempts = 0, error = null
        from public.workflow_run wr
       where wr.id = sr.workflow_run_id and wr.workflow_key = 'employee_task'
         and wr.context->>'task_id' = r.id::text
         and sr.finished_at is null
         and coalesce(sr.error->>'disposition','') = 'awaiting_model';
      v_unparked := v_unparked + 1;
    end if;
  end loop;

  -- (2) promote, within the in-flight ceiling
  select count(*) into v_in_flight
    from public.workflow_run wr where wr.workflow_key = 'employee_task' and wr.status = 'running';
  v_room := greatest(least(coalesce(p_limit, 12), coalesce(p_in_flight_ceiling, 60) - v_in_flight), 0);

  select count(*) into v_backlog
    from public.org_tasks t
   where t.status in ('assigned','in_progress')
     and not exists (select 1 from public.workflow_run wr
                      where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text);

  if v_room > 0 then
    for r in
      select t.id, t.dept_key
        from public.org_tasks t
       where t.status in ('assigned','in_progress')
         and coalesce(t.needs_founder, false) = false
         and not exists (select 1 from public.workflow_run wr
                          where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text)
       order by t.priority desc nulls last, t.created_at, t.id
       limit v_room
    loop
      begin
        v_run := public.fn_workflow_start('employee_task', null, 'org_task', r.id::text,
                   jsonb_build_object('task_id', r.id::text, 'dept_key', r.dept_key,
                                      'promoted_by', 'fn_org_task_promote',
                                      'promoted_at', now()));
        if v_run is not null then v_promoted := v_promoted + 1; end if;
      exception when others then
        -- one task that cannot be promoted (no resolvable actor, say) must not stop the sweep
        null;
      end;
    end loop;
  end if;

  return jsonb_build_object('unparked', v_unparked, 'promoted', v_promoted,
                            'in_flight_before', v_in_flight, 'room', v_room,
                            'backlog_without_a_run', v_backlog, 'ran_at', now());
end
$function$
