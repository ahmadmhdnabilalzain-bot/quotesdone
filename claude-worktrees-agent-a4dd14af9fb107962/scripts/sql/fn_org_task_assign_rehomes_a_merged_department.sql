-- fn_org_task_assign: OPEN WORK IN A MERGED DEPARTMENT FOLLOWS THE MERGE.
--
-- Full definition, fetched from production on 5 Sep 2026 and patched in one place: before any picking, an
-- open task whose dept_key is an inactive department with merged_into set is moved to the live department
-- it merged into (the chain is followed one step further for a department merged twice), with the reason
-- under result.rehomed. Measured before this: fn_org_task_assign left tasks 561939 (evolution) and 561968
-- (knowledge_eng) unowned with the note "every eligible colleague is at max_open_tasks" — the true reason
-- was that both departments had been merged away on 3 Sep and had no colleagues at all.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_org_task_assign_rehomes_a_merged_department.sql --apply
CREATE OR REPLACE FUNCTION public.fn_org_task_assign(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_pick text;
  v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
  v_released int := 0; v_gone int := 0; v_rehomed int := 0;
  v_promote jsonb;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
                                          'compliance_check','legal_review','supplier_verify',
                                          'capability_review','self_review'];
begin
  -- A MERGED DEPARTMENT HAS NO COLLEAGUES (5 Sep 2026). Two open tasks were addressed to 'evolution' and
  -- 'knowledge_eng', both merged away on 3 Sep; the picker found nobody, and the row said "every eligible
  -- colleague is at max_open_tasks", which was not the reason. Open work follows the merge to the live
  -- department, and the row says so. The chain is followed so a department merged twice still lands.
  update public.org_tasks t
     set dept_key = m.live_dept, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'rehomed', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.dept_key, 'to', m.live_dept,
             'reason', 'the department was merged into ' || m.live_dept || ' and has no colleagues; open work follows the merge'))
    from (select d0.dept_key, coalesce(d2.dept_key, d1.dept_key) as live_dept
            from public.org_departments d0
            join public.org_departments d1 on d1.dept_key = d0.merged_into
            left join public.org_departments d2 on d2.dept_key = d1.merged_into and not d1.active
           where not d0.active and d0.merged_into is not null) m
   where m.dept_key = t.dept_key
     and t.status in ('proposed','assigned','in_progress','blocked')
     and exists (select 1 from public.org_departments x where x.dept_key = m.live_dept and x.active);
  get diagnostics v_rehomed = row_count;

  -- a re-homed task (or any open task) with no objective serves the live department's primary active
  -- objective — the same default a05_org_task_fill_ownership applies at insert, which does not fire on
  -- an update of dept_key. org_connectivity_scenarios counts open tasks without one and expects 0.
  update public.org_tasks t
     set objective_id = (select o.id from public.department_objective o
                          where o.active and o.status = 'active' and o.dept_key = t.dept_key
                          order by (coalesce(o.measure_sql, '') <> '') desc, o.sort, o.id
                          limit 1),
         updated_at = now()
   where t.objective_id is null
     and t.status in ('proposed','assigned','in_progress','blocked')
     and exists (select 1 from public.department_objective o
                  where o.active and o.status = 'active' and o.dept_key = t.dept_key);

  -- release unworked work from a head nobody can review, where a colleague exists
  update public.org_tasks t
     set assigned_agent = null, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'released', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.assigned_agent,
             'reason', 'the department head has no manager, so work it authors cannot be reviewed; '
                    || 'released to a colleague the head can review'))
    from public.org_departments d
   where d.dept_key = t.dept_key
     and t.status in ('assigned','in_progress')
     and t.assigned_agent = d.lead_agent
     and coalesce(t.attempts, 0) = 0
     and not exists (select 1 from public.org_agents h
                      join public.org_agents m on m.agent_key = h.manager_key and m.active
                     where h.agent_key = d.lead_agent)
     and exists (select 1 from public.org_agents b
                  left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                 where b.active and coalesce(b.available, true) and b.department = d.dept_key
                   and b.agent_key <> d.lead_agent
                   and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer')
     and not exists (select 1 from public.workflow_step_run sr
                      join public.workflow_run wr on wr.id = sr.workflow_run_id
                     where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                       and sr.status = 'running');
  get diagnostics v_released = row_count;

  -- release work held by a colleague who is no longer active or available: fn_workflow_actor_resolve
  -- resolves such an owner to no employee and the promotion is refused (10 open tasks, 5 Sep 2026,
  -- surfaced the moment the promoter stopped swallowing the refusal)
  update public.org_tasks t
     set assigned_agent = null, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'released', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.assigned_agent,
             'reason', 'the assignee is no longer an active, available colleague; released to be re-homed'))
   where t.status in ('assigned','in_progress')
     and t.assigned_agent is not null
     and not exists (select 1 from public.org_agents a
                      where a.agent_key = t.assigned_agent and a.active and coalesce(a.available, true)
                        and (a.unavailable_until is null or a.unavailable_until < now()));
  get diagnostics v_gone = row_count;
  v_released := v_released + v_gone;

  for r in
    select t.id, t.dept_key, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.priority desc, t.created_at, t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    v_considered := v_considered + 1;
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status = 'active'
      join public.org_departments d on d.dept_key = a.department
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = r.dept_key
       and (coalesce(rr.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(r.action_class, '') = any (REVIEW_CLASSES))
       -- the picker knows who it must not select: a head nobody can review, while a colleague exists
       and not (a.agent_key = d.lead_agent
                and not exists (select 1 from public.org_agents h
                                 join public.org_agents m on m.agent_key = h.manager_key and m.active
                                where h.agent_key = d.lead_agent)
                and exists (select 1 from public.org_agents b
                             left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                            where b.active and coalesce(b.available, true) and b.department = d.dept_key
                              and b.agent_key <> d.lead_agent
                              and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'))
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks, 6)
     order by case when p.tier = 'probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key
                  and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;

    if v_pick is not null then
      update public.org_tasks set assigned_agent = v_pick, updated_at = now() where id = r.id;
      v_assigned := v_assigned + 1;
    else
      v_no_capacity := v_no_capacity + 1;
    end if;
  end loop;

  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  -- an unowned task carries its reason on the row: every eligible colleague is at max_open_tasks
  update public.org_tasks t
     set result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'waiting', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign',
             'reason', 'unowned: every eligible colleague in ' || t.dept_key || ' is at max_open_tasks; '
                    || 'it is assigned and promoted onto the spine as capacity frees (hourly)'))
   where t.assigned_agent is null and t.status in ('assigned','in_progress')
     and not (coalesce(t.result,'{}'::jsonb) ? 'waiting');

  begin
    v_promote := public.fn_org_task_promote();
  exception when others then
    v_promote := jsonb_build_object('error', sqlerrm);
  end;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'released_from_unreviewable_head', v_released,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                             'promoted_to_spine', v_promote),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to the currently '
          ||'least-loaded named colleague in the owning department, spreading within the department, '
          ||'skipping independent reviewers for non-review work and never a head nobody can review ('
          ||v_released||' released from one). '||v_no_capacity||' left unowned '
          ||'only where every eligible colleague was already at max_open_tasks - deliberate: an '
          ||'unowned task is visible, an overloaded one is not. Departments still carrying more open '
          ||'work than they staff (unowned/capacity): '||coalesce(v_saturated,'none')||'. Promoted onto '
          ||'the workflow spine: '||coalesce(v_promote::text,'{}')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'rehomed_from_merged_department', v_rehomed,
                            'released_from_unreviewable_head', v_released,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                            'promoted_to_spine', v_promote);
end
$function$

