-- LAUNCH STEP 1 — A SWEEP FILLS THE DEPARTMENT, AND "NO CAPACITY" MEANS IT.
--
-- Measured 2026-08-31 on htdblwldjkcgjvmqkbeh: the target cascade produces open work (org_tasks in
-- status 'assigned'), and fn_org_task_assign is what stamps each with an accountable owner. It did
-- not fill a department. It ranked agents PER TASK and kept only pick=1, so when a department's
-- agents were all idle every task resolved to the single alphabetically-first agent; only that one
-- agent's cap-worth stuck and the remainder were dropped — while the run note called the idle
-- department "oversubscribed". customer_experience carried 26 unowned tasks across 7 agents holding
-- 0 of 39 slots, and a sweep assigned 6 of them, leaving 20 unowned against a false capacity story.
--
-- The fix assigns one task at a time to the currently-least-loaded ELIGIBLE colleague in the owning
-- department, recomputing load each pick. Because the assignments made earlier in the same sweep are
-- visible to the later picks (same transaction), the load spreads breadth-first and one sweep fills
-- the department. Proven by aborted-tx probe on the live 37 unowned tasks: 37 assigned, 0 left,
-- customer_experience spread 5/5/4/4/4/4 across six agents, none over max_open_tasks. The
-- independent-reviewer exception and the per-agent cap are preserved exactly.
--
-- Now that a sweep genuinely fills a department, the "oversubscribed / left_unowned" figure is a TRUE
-- saturation signal (every eligible colleague at max_open_tasks) rather than the single-agent
-- artefact it used to report.
--
-- Not a frozen subject. The assign cron (jobid 262) remains INACTIVE — re-activating stood-down
-- automation is the founder's call; this only repairs the mechanism it drives.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_task_assign_fills_the_department.sql --apply

CREATE OR REPLACE FUNCTION public.fn_org_task_assign(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_pick text;
  v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
                                          'compliance_check','legal_review','supplier_verify',
                                          'capability_review','self_review'];
begin
  -- ONE TASK AT A TIME, TO THE CURRENTLY-LEAST-LOADED ELIGIBLE COLLEAGUE. Assigning inside the
  -- transaction makes each pick see the assignments already made in this sweep, so the load spreads
  -- breadth-first across the department and a single sweep fills it.
  for r in
    select t.id, t.dept_key, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.created_at, t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    v_considered := v_considered + 1;
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status = 'active'
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = r.dept_key
       -- AN INDEPENDENT REVIEWER CARRYING THE DEPARTMENT'S ROUTINE QUEUE IS NOT INDEPENDENT OF IT.
       -- Review work still reaches them: the review action classes are the exception, and
       -- fn_pick_reviewer routes review directly rather than through this queue.
       and (coalesce(rr.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(r.action_class, '') = any (REVIEW_CLASSES))
       -- REMAINING CAPACITY, RECOMPUTED EACH PICK so it counts what this sweep already assigned.
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

  -- Departments that genuinely could not take all their open work: every eligible colleague was at
  -- max_open_tasks. Now that a sweep fills a department, this is a TRUE saturation signal.
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

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none')),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to the currently '
          ||'least-loaded named colleague in the owning department, spreading within the department '
          ||'and skipping independent reviewers for non-review work. '||v_no_capacity||' left unowned '
          ||'only where every eligible colleague was already at max_open_tasks - deliberate: an '
          ||'unowned task is visible, an overloaded one is not. Departments still carrying more open '
          ||'work than they staff (unowned/capacity): '||coalesce(v_saturated,'none')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'));
end
$function$;
