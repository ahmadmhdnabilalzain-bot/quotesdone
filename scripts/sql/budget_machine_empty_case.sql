-- THE BUDGET MACHINE MISHANDLES THE EMPTY CASE, IN TWO ROUTINES.
-- Measured on production 2026-08-10. department_budget is ENFORCED — fn_check_spend,
-- fn_ai_spend_guard, fn_budget_available and fn_ai_route all read it — so both of these change what
-- the company is allowed to spend, not just what a report says.
--
-- 1. fn_reallocate: A RELEASE WITH NO RECIPIENT IS A BUDGET CUT, NOT A REALLOCATION.
--    On 1 Aug 08:00 the release loop ran unconditionally and took 20% off ALL TWELVE departments
--    (every one was under 30% utilisation). The grant loop then looked for departments over 85% and
--    found NONE, so the money left the departments and reached nobody:
--        allocation_change  = 12 release rows, 0 grant rows
--        department_budget  = 9,500 -> 7,640 AED
--        agent_runs note    = "1860 AED moved from idle to saturated departments"   <- false
--    Scheduled to repeat 1 Sept 08:00 and every month after: a compounding 20%-per-month cut to
--    every department's enforced ceiling, with no recipient and a run note claiming otherwise.
--    FIX: count recipients BEFORE releasing. With none, release nothing and say so.
--
-- 2. fn_reallocate: THE GRANT LOOP DIVIDED BY A HARD-CODED 3.
--    `round(v_free/3,0)` regardless of how many recipients were found, so with one or two recipients
--    most of the pool vanished even when a recipient existed. Latent today only because the loop has
--    never had a recipient at all.
--    FIX: split across the recipients actually found; the last one takes the rounding remainder.
--
-- 3. fn_budget_rollup: A DEPARTMENT THAT SPENDS NOTHING IS NEVER ROLLED.
--    `update ... from (select ... from ai_cost_log group by dept_key) s where b.dept_key = s.dept_key`
--    is an INNER join, so a department with zero rows in ai_cost_log this month keeps last month's
--    spent_aed and period_label forever. Ten of thirteen rows still read period_label '2026-07'.
--    Harmless today because all ten are 0, but a department at 90% in month N that goes quiet in
--    month N+1 keeps reading 90% — and fn_check_spend would keep halting it for spend it is not
--    making.
--    FIX: roll every department, coalescing a missing sum to 0. Only write when something changed,
--    so updated_at still means "this budget moved".

create or replace function public.fn_reallocate()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  n int := 0;
  v_pool numeric := 0;
  v_recipients int := 0;
  v_idle numeric := 0;
  v_slots int := 0;
  v_i int := 0;
  v_take numeric;
  v_left numeric;
begin
  -- policy: never move more than 20% of a department's budget in one cycle, never below 200 AED,
  -- only FROM departments under 30% utilisation, only TO departments over 85%.

  -- Recipients first. A release that cannot be granted is a cut.
  select count(*) into v_recipients
    from department_budget
   where round(100.0 * spent_aed / nullif(monthly_aed, 0), 1) > 85;

  if v_recipients = 0 then
    select coalesce(sum(round(monthly_aed * 0.2, 0)), 0) into v_idle
      from department_budget
     where monthly_aed > 200
       and coalesce(round(100.0 * spent_aed / nullif(monthly_aed, 0), 1), 0) < 30
       and monthly_aed * 0.2 >= 50;

    insert into agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('reallocate', now(), now(), 'ok',
            jsonb_build_object('changes', 0, 'released_aed', 0, 'idle_aed_available', v_idle,
                               'recipients', 0),
            'Resource reallocation: no change. ' || v_idle || ' AED could be released from idle '
            || 'departments, but no department is over 85% utilisation, so there is nowhere to '
            || 'move it. Budgets left intact rather than cut.');
    return jsonb_build_object('changes', 0, 'released_aed', 0, 'idle_aed_available', v_idle,
                              'recipients', 0);
  end if;

  for r in
    select b.dept_key, b.monthly_aed, b.spent_aed,
           round(100.0 * b.spent_aed / nullif(b.monthly_aed, 0), 1) as util
      from department_budget b
     where b.monthly_aed > 200
  loop
    if r.util < 30 and r.monthly_aed * 0.2 >= 50 then
      v_pool := v_pool + round(r.monthly_aed * 0.2, 0);
      insert into allocation_change (resource, subject, from_value, to_value, reason, policy)
      values ('ai_budget_aed', r.dept_key, r.monthly_aed,
              r.monthly_aed - round(r.monthly_aed * 0.2, 0),
              r.dept_key || ' used only ' || coalesce(r.util, 0)
              || '% of its budget. Releasing 20% to the pool.',
              'release: utilisation under 30%, cap 20% per cycle, floor 200 AED');
      update department_budget
         set monthly_aed = monthly_aed - round(monthly_aed * 0.2, 0), updated_at = now()
       where dept_key = r.dept_key;
      n := n + 1;
    end if;
  end loop;

  -- A released department was under 30% and can rise by at most a quarter of that, so it can never
  -- re-enter the grant loop's >85% set. The two loops cannot overlap.
  v_left := v_pool;
  v_slots := least(v_recipients, 3);
  if v_pool > 0 then
    for r in
      select b.dept_key, b.monthly_aed,
             round(100.0 * b.spent_aed / nullif(b.monthly_aed, 0), 1) util
        from department_budget b
       where round(100.0 * b.spent_aed / nullif(b.monthly_aed, 0), 1) > 85
       order by util desc
       limit 3
    loop
      v_i := v_i + 1;
      -- the last recipient takes the remainder, so the pool is never left part-granted
      v_take := case when v_i = v_slots then v_left else round(v_pool / v_slots, 0) end;
      exit when v_take <= 0;
      insert into allocation_change (resource, subject, from_value, to_value, reason, policy)
      values ('ai_budget_aed', r.dept_key, r.monthly_aed, r.monthly_aed + v_take,
              r.dept_key || ' is at ' || r.util || '% utilisation. Receiving ' || v_take
              || ' AED of released budget.',
              'grant: utilisation over 85%, released pool split across at most 3 departments');
      update department_budget set monthly_aed = monthly_aed + v_take, updated_at = now()
       where dept_key = r.dept_key;
      v_left := v_left - v_take;
      n := n + 1;
    end loop;
  end if;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('reallocate', now(), now(), 'ok',
          jsonb_build_object('changes', n, 'released_aed', v_pool, 'granted_aed', v_pool - v_left,
                             'recipients', v_recipients),
          'Resource reallocation: ' || n || ' change(s), ' || (v_pool - v_left) || ' of ' || v_pool
          || ' AED released from idle departments and granted to ' || v_slots
          || ' saturated one(s). Every change is logged and reversible.');
  return jsonb_build_object('changes', n, 'released_aed', v_pool, 'granted_aed', v_pool - v_left,
                            'recipients', v_recipients);
end $function$;

create or replace function public.fn_budget_rollup()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_period text := to_char(current_date,'YYYY-MM'); n int := 0; v_degraded int := 0; v_halted int := 0; r record;
begin
  -- Every department is rolled, including the ones that spent nothing. The previous inner join
  -- skipped zero-spend departments entirely, leaving last month's spent_aed and period_label in
  -- place indefinitely. Only rows whose value actually changes are written, so updated_at still
  -- means "this budget moved".
  update department_budget b
     set spent_aed = v.total, period_label = v_period, updated_at = now()
  from (
    select b2.dept_key,
           coalesce((select sum(l.cost_aed) from ai_cost_log l
                      where l.dept_key = b2.dept_key
                        and l.occurred_at >= date_trunc('month', now())), 0) as total
      from department_budget b2
  ) v
  where b.dept_key = v.dept_key
    and (b.spent_aed is distinct from v.total or b.period_label is distinct from v_period);
  get diagnostics n = row_count;

  for r in
    select dept_key, monthly_aed, spent_aed, degrade_at_pct, halt_at_pct,
           round(100.0*spent_aed/nullif(monthly_aed,0),1) as pct
    from department_budget
    where monthly_aed > 0 and spent_aed is not null
  loop
    if r.pct >= r.halt_at_pct then
      v_halted := v_halted + 1;
      insert into founder_alerts (level, event, detail, channel)
      select 'high','ai_budget_halt', r.dept_key||' has spent '||r.pct||'% of its monthly AI budget ('||r.spent_aed||' of '||r.monthly_aed||' AED). Halt threshold '||r.halt_at_pct||'% reached.','email'
      where not exists (select 1 from founder_alerts where event='ai_budget_halt' and detail like r.dept_key||'%' and created_at > now()-interval '24 hours');
      -- The same fact, on the bus, so the Finance OS hears it as well as the founder.
      if not exists (select 1 from company_event where event_type='budget.exceeded'
                       and entity_id = r.dept_key and occurred_at > now()-interval '24 hours') then
        perform public.fn_emit('budget.exceeded','department', r.dept_key, 'cfo',
                  jsonb_build_object('pct', r.pct, 'spent_aed', r.spent_aed,
                                     'monthly_aed', r.monthly_aed, 'halt_at_pct', r.halt_at_pct));
      end if;
    elsif r.pct >= r.degrade_at_pct then
      v_degraded := v_degraded + 1;
      insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select r.dept_key, 'AI budget degrade threshold: '||r.dept_key,
             r.dept_key||' has spent '||r.pct||'% of its monthly AI budget. Move non-critical work to the cheaper model tier and enable response caching before the halt threshold at '||r.halt_at_pct||'%.',
             'proposed','gated', false, 'recommend'
      where not exists (select 1 from org_tasks where title='AI budget degrade threshold: '||r.dept_key and status<>'done');
    end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('budget_rollup', now(), now(), 'ok',
          jsonb_build_object('depts_changed',n,'degraded',v_degraded,'halted',v_halted),
          'AI spend rolled into department budgets: '||n||' department(s) changed, '||v_degraded||' past degrade threshold, '||v_halted||' past halt.');
  return jsonb_build_object('updated',n,'degraded',v_degraded,'halted',v_halted);
end $function$;
