-- Three hundred and thirty-nine tasks were "assigned" to nobody
-- =============================================================
--
-- Followed the employee-performance thread down to its floor. org_tasks.assigned_agent has NO
-- WRITER ANYWHERE: not one of the 41 SQL routines that touch org_tasks sets it, and the string
-- does not appear in supabase/functions or src at all. The 143 non-null values on file came from
-- a one-off backfill.
--
-- Meanwhile:
--
--     status='assigned'      339 tasks    339 with assigned_agent NULL   100%
--     status='in_progress'    46 tasks     20 with assigned_agent NULL
--     status='done'          485 tasks    386 with assigned_agent NULL
--     org_tasks total        922 tasks    779 with assigned_agent NULL    85%
--
-- Three hundred and thirty-nine tasks carry a status that says "assigned" and not one of them
-- names an employee. The company generates work, marks it assigned, and assigns it to nobody.
--
-- THE SCHEMA WAS BUILT FOR THIS. org_agents carries department, manager_key, seniority,
-- max_open_tasks, available, unavailable_until and routing_tier - a complete assignment and
-- capacity model - and nothing has ever written the one column that would use it. Another finished
-- capability with no entry point, and the largest one yet: it is why 75 employees have no
-- agent_runs row, why 57 came out 'unmeasured' when reputation stopped inventing a 50 for them,
-- and why employee-performance and employee-current-thoughts fail on Row #3. An employee with no
-- work has no performance to show, and the reason it has no work is this column.
--
-- Feasibility measured before building: all 359 open unowned tasks have an active, available agent
-- in their own department. 93 agents across 25 departments at an average max_open_tasks of 6 is
-- 558 slots against 359 tasks.
--
-- WHAT IT DOES NOT DO. Assigning names an owner; it does not execute anything, does not touch
-- status, and does not grant authority. A probation employee is still assigned work - probation
-- gates what an employee may do UNAUTONOMOUSLY, and starving it of work is how it would stay on
-- probation for ever - but it is ranked last so a healthy colleague takes the task first.
-- max_open_tasks is respected as a hard ceiling: an employee at capacity is skipped rather than
-- overloaded, and a task with no free colleague in its department stays unowned and visible rather
-- than being pushed onto someone who cannot take it.

create or replace function public.fn_org_task_assign(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
begin
  with open_tasks as (
    select t.id, t.dept_key, t.created_at
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.created_at
     limit greatest(coalesce(p_limit, 200), 1)
  ),
  -- Load is counted ONCE, before any assignment in this run, and the running total is added back
  -- by the row_number below. Counting it per-task inside the loop would let one employee be handed
  -- every task in the batch: each lookup would see the load as it was before the batch started.
  load as (
    select a.agent_key, a.department, coalesce(a.max_open_tasks, 6) as cap,
           (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key and o.status in ('assigned','in_progress')) as open_now,
           case when p.tier = 'probation' then 1 else 0 end as probation_rank
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
  ),
  ranked as (
    select ot.id as task_id, l.agent_key, l.cap, l.open_now,
           row_number() over (partition by ot.id
                              order by l.probation_rank, l.open_now, l.agent_key) as pick,
           row_number() over (partition by l.agent_key
                              order by ot.created_at, ot.id) as nth_for_agent
      from open_tasks ot
      join load l on l.department = ot.dept_key
  ),
  chosen as (
    -- pick = 1 is the least-loaded non-probation colleague in the department; nth_for_agent keeps
    -- this run inside that colleague's remaining capacity.
    select task_id, agent_key from ranked
     where pick = 1 and (open_now + nth_for_agent) <= cap
  ),
  done as (
    update public.org_tasks t
       set assigned_agent = c.agent_key, updated_at = now()
      from chosen c
     where t.id = c.task_id and t.assigned_agent is null
    returning t.id
  )
  select (select count(*) from done), (select count(*) from open_tasks)
    into v_assigned, v_considered;

  v_no_capacity := v_considered - v_assigned;

  -- WHICH DEPARTMENTS ARE OVERSUBSCRIBED, named rather than swallowed. A task left unowned is not
  -- a failure of this function; it is the company telling us a department generates more work than
  -- it employs people to do. Measured on the first run: exec 87 open against 4 staff and 28 slots,
  -- knowledge 34 against 21, sales 27 against 15. That is a hiring signal and it belongs in the
  -- note, not in a silent counter.
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
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to a named employee '
          ||'in the owning department. '||v_no_capacity||' left unowned because no colleague in that '
          ||'department had capacity under max_open_tasks - deliberate: an unowned task is visible, '
          ||'an overloaded one is not. Departments carrying more open work than they staff '
          ||'(unowned/capacity): '||coalesce(v_saturated,'none')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'));
end
$function$;

revoke all on function public.fn_org_task_assign(integer) from public;
