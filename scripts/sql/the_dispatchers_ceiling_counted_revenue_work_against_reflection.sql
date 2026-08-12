-- THE DISPATCHER'S CEILING COUNTED REVENUE WORK AGAINST REFLECTION.
--
-- The founder, 12 Aug 2026: "split the 24/day cap so demand work is uncapped and reflection near zero."
--
-- fn_workflow_step_claim already HAS a daily ceiling — v_cap constant int := 24, added by
-- scripts/sql/the_dispatcher_needed_a_daily_ceiling_before_it_needed_speed.sql — and it already
-- refuses any step whose action_class has a safe edge executor, sending that work down the
-- deterministic path instead. Both of those are right and neither is touched here.
--
-- What it does NOT have is a distinction between the two kinds of work it ceilings. One counter
-- covers everything, so a day spent on twenty-four self-analysis steps leaves nothing for the
-- twenty-fifth step, and the twenty-fifth step might be a supplier registration. The ceiling was
-- protecting the bill by rationing the revenue path along with everything else.
--
-- THE SAME SPLIT AS cos_execute, FROM THE SAME SOURCE OF TRUTH. fn_task_is_demand() decides, and it
-- decides here exactly as it decides there — see
-- scripts/sql/sixty_percent_of_the_bill_was_the_company_thinking_about_itself.sql for the
-- measurements that produced it. Revenue-path steps are not counted and not capped. Self-analysis
-- gets decision_policy.workflow_reflection_steps_per_day.
--
-- SIZING, AND IT IS DELIBERATELY NOT 24. Measured over 30 days: workflow_dispatch is 48 calls and
-- 7.19 AED, 4.2% of all spend, at an average 3,529 OUTPUT tokens a step — the most expensive
-- per-call output in the company. 6 reflection steps a day is roughly 0.9 AED/day against the 24
-- the old ceiling allowed. The revenue path lost nothing: it is now uncapped where before it shared
-- a ration.
--
-- THE OVERSHOOT IS BOUNDED AND STATED. v_today is read once, before the pick, so a single call can
-- claim up to p_limit reflection steps against the last remaining slot — an overshoot of at most
-- p_limit-1 (4 at the cron's p_limit=5), self-correcting on the next call. Making it exact needs a
-- running total inside the pick, which cannot carry `for update ... skip locked` without either
-- nesting the CTE and losing the row lock or holding it longer. A ceiling that can overshoot by four
-- and keeps its concurrency guarantee is the better trade; a claim function that can hand the same
-- step to two dispatchers is a much more expensive defect than four extra steps in a day.
insert into public.decision_policy(key, value, description, updated_at)
values (
  'workflow_reflection_steps_per_day',
  to_jsonb(6),
  'Maximum workflow steps NOT on the revenue path that fn_workflow_step_claim may hand to a model in '
  'one UTC day. Revenue-path steps (fn_task_is_demand) are neither counted nor capped. Replaces the '
  'hardcoded 24 that rationed both kinds of work together.',
  now())
on conflict (key) do update
  set value = excluded.value, description = excluded.description, updated_at = now();

-- Transformed from the LIVE production definition, not retyped. Changes, and there are only four:
--   1. v_cap is read from decision_policy instead of being a constant 24
--   2. v_today counts NON-demand steps only
--   3. the early return fires only when there is also no revenue-path step waiting
--   4. the pick's row predicate and limit let demand through the ceiling
CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb; v_today int; v_cap int; v_demand_ready int;
begin
  update public.workflow_step_run sr
     set status = 'ready'
   where sr.status = 'running'
     and sr.finished_at is null
     and sr.started_at < now() - interval '15 minutes'
     and not exists (select 1 from public.action_execution x
                      where x.workflow_step_run_id = sr.id
                        and x.status in ('queued','running','succeeded'));

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  -- NON-DEMAND ONLY. A supplier registration step worked this morning must not make the company
  -- refuse an inquiry step this afternoon.
  select count(*) into v_today
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(sr.action_class);

  -- Is there revenue-path work waiting that the ceiling must not block? Same predicates as the pick,
  -- so this cannot claim the ceiling is irrelevant for a step the pick would reject anyway.
  select count(*) into v_demand_ready
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready'
     and sr.finished_at is null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and public.fn_task_is_demand(sr.action_class)
     and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
     and not exists (
           select 1 from public.org_action_executor e
            where e.action_class = sr.action_class and e.active and e.kind = 'edge'
              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
              and not e.notifies_human
              and coalesce(e.required_authority,'') <> 'founder');

  if v_today >= v_cap and v_demand_ready = 0 then
    return jsonb_build_object('capped', true, 'worked_today', v_today, 'cap', v_cap,
             'demand_ready', 0,
             'note', 'the daily reflection ceiling is spent and no revenue-path step is waiting; see '
                     || 'scripts/sql/the_dispatchers_ceiling_counted_revenue_work_against_reflection.sql');
  end if;

  with pick as (
    select sr.id
      from public.workflow_step_run sr
      join public.workflow_run r on r.id = sr.workflow_run_id
     where sr.status = 'ready'
       and sr.finished_at is null
       and r.status = 'running'
       and r.workflow_key <> 'employee_task'
       and coalesce(sr.input->>'gate','') <> 'founder'
       -- THE SPLIT. A revenue-path step is always claimable; a reflection step only while the
       -- day's ceiling holds.
       and (public.fn_task_is_demand(sr.action_class) or v_today < v_cap)
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       and not exists (
             select 1 from public.org_action_executor e
              where e.action_class = sr.action_class and e.active and e.kind = 'edge'
                and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                and not e.notifies_human
                and coalesce(e.required_authority,'') <> 'founder')
     order by sr.id
     -- the reflection remainder PLUS whatever revenue-path work is waiting, so demand is not
     -- rationed by a counter that no longer counts it. See the overshoot note in the header.
     limit greatest(least(coalesce(p_limit, 5), greatest(v_cap - v_today, 0) + v_demand_ready), 1)
     for update of sr skip locked
  ), claimed as (
    update public.workflow_step_run sr
       set status = 'running', started_at = now()
      from pick
     where sr.id = pick.id
    returning sr.id, sr.workflow_run_id, sr.step_no, sr.actor, sr.action_class, sr.input
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'step_run_id',  c.id,
           'run_id',       c.workflow_run_id,
           'step_no',      c.step_no,
           'employee',     public.fn_workflow_actor_resolve(c.workflow_run_id, c.actor),
           'addressed_as', coalesce(c.input->>'addressed_as', c.actor),
           'action_class', c.action_class,
           'step',         c.input->>'step',
           'gate',         c.input->>'gate',
           'workflow_key', r.workflow_key,
           'workflow',     w.name,
           'context',      r.context,
           -- WHAT THIS RUN HAS ALREADY CONCLUDED. See the header: without this the process does not
           -- accumulate. Skipped steps are excluded on purpose - their note says the work was never
           -- separately observed, and passing that on as a finding would be a fabrication.
           'prior_steps', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'step_no', p.step_no,
                                    'step',    p.input->>'step',
                                    'by',      coalesce(p.output->>'employee', p.actor),
                                    'outcome', left(coalesce(p.output->>'outcome',
                                                             p.output->>'note', ''), 600))
                                  order by p.step_no), '[]'::jsonb)
                             from (select p2.* from public.workflow_step_run p2
                                    where p2.workflow_run_id = c.workflow_run_id
                                      and p2.step_no < c.step_no
                                      and p2.status = 'done'
                                      and coalesce(p2.output->>'outcome', p2.output->>'note','') <> ''
                                    order by p2.step_no desc
                                    limit 3) p)
         ) order by c.id), '[]'::jsonb)
    into v_out
    from claimed c
    join public.workflow_run r on r.id = c.workflow_run_id
    left join public.workflow w on w.workflow_key = r.workflow_key;

  return v_out;
end
$function$;

-- CREATE OR REPLACE preserves the ACL, so there is deliberately no REVOKE here: this function
-- already existed and already carries the grants it was created with.
