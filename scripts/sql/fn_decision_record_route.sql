-- A PROPOSED DECISION IS ROUTED TO THE DEPARTMENT THAT OWNS IT, NEVER LEFT FOR THE FOUNDER.
--
-- fn_decide writes every escalating decision as status='proposed' with approved_by null and its own
-- rollback text said "the decision sits at proposed until a human takes it". Nothing routed it. Measured
-- on production 5 Sep 2026: 7 such rows, the oldest from 27 July, and the OS showed them to the founder
-- as his decisions. His standing rule is that nothing reaches him except a Stripe refund.
--
-- This routine gives each proposed decision an owner through the existing org_task lane: one org_task
-- in the accountable department, assigned to that department's lead when the lead is an active employee
-- (else the assigner picks the least-loaded colleague), at tier 'advisory' — a written determination.
-- The department is resolved by a ladder that invents nobody: the record's dept_key, followed through
-- org_departments.merged_into to a live department; else the deciding actor's own department; else the
-- executive office. Identical open questions in one department share one task rather than three.
--
-- The link survives the lane: org_tasks.detail carries the literal marker [decision_record:<id>] (the
-- lane REPLACES result at close, so a jsonb key there would not). When the linked task is done the
-- decision is closed back as 'approved' by the employee who determined it; trg_decision_gate then rules
-- on that approval exactly as it rules on any other, and a refusal lands as 'blocked_by_gate' with the
-- gate's reason on the row — a working gate, not a bypass.
--
-- Called by fn_decide for the row it just escalated, and by fn_agent_action_work_sweep hourly for the
-- rows that predate this routine. p_decision_id null routes every unrouted proposed decision.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_decision_record_route.sql --apply
create or replace function public.fn_decision_record_route(p_decision_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  d record; t record;
  v_dept text; v_lead text; v_task bigint; v_title text; v_detail text; v_hops int;
  v_routed int := 0; v_shared int := 0; v_closed int := 0; v_status text;
begin
  for d in
    select r.id, r.decided_by, r.dept_key, r.problem, r.recommendation, r.options, r.created_at
      from public.decision_record r
     where r.status = 'proposed' and r.approved_by is null
       and (p_decision_id is null or r.id = p_decision_id)
       and not exists (select 1 from public.org_tasks o
                        where o.detail like '%[decision_record:' || r.id || ']%')
     order by r.id
  loop
    -- the owning department: the record's, followed through merges; else the actor's; else exec
    v_dept := d.dept_key; v_hops := 0;
    while v_dept is not null and v_hops < 6
          and not exists (select 1 from public.org_departments x where x.dept_key = v_dept and x.active) loop
      select x.merged_into into v_dept from public.org_departments x where x.dept_key = v_dept;
      v_hops := v_hops + 1;
    end loop;
    if v_dept is null then
      select a.department into v_dept from public.org_agents a where a.agent_key = d.decided_by and a.active;
    end if;
    if v_dept is null or not exists (select 1 from public.org_departments x where x.dept_key = v_dept and x.active) then
      v_dept := 'exec';
    end if;
    select x.lead_agent into v_lead from public.org_departments x where x.dept_key = v_dept;
    if not exists (select 1 from public.org_agents a where a.agent_key = v_lead and a.active and coalesce(a.available, true)) then
      v_lead := null;   -- a05_org_task_fill_ownership picks the least-loaded colleague
    end if;

    v_title := left('Decision requested: ' || regexp_replace(coalesce(d.problem, 'decision_record ' || d.id), '^Decision requested \([^)]*\) by [^:]+: ', ''), 200);

    -- the same open question in the same department is one task, not one per retry
    select o.id into v_task from public.org_tasks o
     where o.dept_key = v_dept and o.title = v_title
       and o.status not in ('done', 'cancelled')
       and o.detail like '[decision_record:%'
     order by o.id limit 1;

    if v_task is not null then
      update public.org_tasks
         set detail = detail || ' [decision_record:' || d.id || ']', updated_at = now()
       where id = v_task;
      v_shared := v_shared + 1;
    else
      v_detail := '[decision_record:' || d.id || '] ' || coalesce(d.problem, '')
        || E'\n\nEngine recommendation: ' || coalesce(d.recommendation, '(none)')
        || E'\nOptions scored: ' || left(coalesce(d.options::text, '[]'), 1500)
        || E'\nRaised by ' || coalesce(d.decided_by, '?') || ' at ' || d.created_at
        || '. fn_decide escalated it instead of taking it; the department determines it in the org_task lane '
        || 'and the decision_record closes on that determination. Only a Stripe refund reaches the founder.';
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                    action_class, assigned_agent, priority, result)
      values (v_dept, v_title, v_detail, 'assigned', 'advisory', false, 'fn_decision_record_route',
              'analysis', v_lead, 1,
              jsonb_build_object('source', jsonb_build_object('decision_record_id', d.id,
                                 'routed_at', now(), 'routed_by', 'fn_decision_record_route')))
      returning id into v_task;
      v_routed := v_routed + 1;
    end if;
  end loop;

  -- close-back: a decision whose task the department has determined is approved by that employee, and
  -- the gate rules on it
  for d in
    select r.id, o.id as task_id, coalesce(o.result->>'employee', o.assigned_agent, o.dept_key) as employee,
           left(coalesce(o.result->>'deliverable', o.result->>'summary', ''), 2000) as determination
      from public.decision_record r
      join public.org_tasks o on o.detail like '%[decision_record:' || r.id || ']%' and o.status = 'done'
     where r.status = 'proposed' and r.approved_by is null
       and (p_decision_id is null or r.id = p_decision_id)
     order by r.id
  loop
    update public.decision_record
       set status = 'approved', approved_by = d.employee, decided_at = now(),
           actual_outcome = 'Determined in the org_task lane by ' || d.employee || ' (org_task ' || d.task_id || '): '
                            || coalesce(nullif(d.determination, ''), '(no deliverable text on the task)')
     where id = d.id
     returning status into v_status;
    v_closed := v_closed + 1;
  end loop;

  return jsonb_build_object('routed', v_routed, 'shared_existing_task', v_shared,
                            'closed_on_determination', v_closed, 'ran_at', now());
end
$function$;

revoke execute on function public.fn_decision_record_route(bigint) from public, anon, authenticated;
