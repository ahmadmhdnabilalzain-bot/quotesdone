CREATE OR REPLACE FUNCTION public.fn_evolution_scan()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'repeated_failure', r.agent,
         format('%s failed %s times in the last 7 days.', r.agent, r.fails),
         jsonb_build_object('failures_7d', r.fails),
         format('Root-cause %s rather than retry it. If the failure is external, add a documented fallback to continuity_plan; if it is a parsing or contract failure, fix the contract and add a regression test.', r.agent),
         'code'
  from (select agent, count(*) fails from agent_runs
        where status = 'error' and started_at > now() - interval '7 days'
        group by agent having count(*) >= 3) r
  on conflict do nothing;

  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'metric_off_target', s.metric_key,
         format('%s is %s against a target of %s.', s.label, coalesce(s.value::text,'unmeasured'), s.target),
         jsonb_build_object('value', s.value, 'target', s.target, 'owner', s.owner_dept),
         format('%s owns this. Either the target is wrong and should be restated, or the operating approach behind it is wrong and should change. Do not carry it as-is for another period.', coalesce(s.owner_dept,'exec')),
         'process'
  from v_bi_scorecard s where s.state = 'OFF_TARGET'
  on conflict do nothing;

  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'cost_anomaly', c.fn,
         format('%s made %s model calls in 30 days that the cost governor flagged as avoidable.', c.fn, c.n),
         jsonb_build_object('avoidable_calls', c.n, 'cost_aed', c.cost),
         format('Replace the flagged path in %s with a rule, a lookup or SQL, or drop it to the small tier.', c.fn),
         'model_routing'
  from (select fn, count(*) n, round(sum(cost_aed),2) cost from ai_cost_log
        where could_be_cheaper and occurred_at > now() - interval '30 days'
        group by fn having count(*) >= 5) c
  on conflict do nothing;

  -- ── THE FOUR STRUCTURAL QUESTIONS ─────────────────────────────────────────────────────────────
  -- The three triggers above ask about routines, metrics and bills. These ask about the company.

  -- IS ANOTHER ROLE IDLE? One proposal, not one per employee: 57 dormant employees is a single
  -- organisational decision and a founder handed 57 rows would read none of them.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', 'workforce',
         format('%s of %s active employees are dormant — no run, no recorded thought and no reasoning in 30 days. Longest-standing: %s.',
                d.idle, d.total, d.sample),
         jsonb_build_object('dormant', d.idle, 'active', d.total, 'sample', d.sample),
         'Decide, for each dormant role, which of two things is true: nothing routes to it, or the role is not needed. Where nothing routes to it the routing is the defect and the role is fine. Where the role is not needed it should be retired rather than carried as an employee that never works.',
         'org'
    from (select count(*) filter (where not (exists (select 1 from agent_runs r_a where r_a.agent = a.agent_key
                                    and r_a.started_at > now() - interval '30 days')
                       or exists (select 1 from agent_memory m_a where m_a.agent_key = a.agent_key
                                    and m_a.created_at > now() - interval '30 days')
                       or exists (select 1 from agent_chats c_a where c_a.agent_key = a.agent_key
                                    and c_a.created_at > now() - interval '30 days'))) idle,
                 count(*) total,
                 (select string_agg(x.agent_key, ', ') from (
                    select a2.agent_key from org_agents a2 where a2.active
                     and not (exists (select 1 from agent_runs r_a2 where r_a2.agent = a2.agent_key
                                    and r_a2.started_at > now() - interval '30 days')
                       or exists (select 1 from agent_memory m_a2 where m_a2.agent_key = a2.agent_key
                                    and m_a2.created_at > now() - interval '30 days')
                       or exists (select 1 from agent_chats c_a2 where c_a2.agent_key = a2.agent_key
                                    and c_a2.created_at > now() - interval '30 days'))
                     order by a2.agent_key limit 5) x) sample
            from org_agents a where a.active) d
   where d.idle > 0 and not exists (select 1 from evolution_proposal p
        where p.trigger_kind = 'audit_gap' and p.subject = 'workforce'
          and p.created_at > now() - interval '30 days')
  on conflict do nothing;

  -- IS ONE ROLE OVERLOADED? Per operating system, because each names a different number and they
  -- are acted on separately.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', h.name,
         format('%s carries a backlog of %s open tasks per head across %s employee(s) — the role is overloaded.',
                h.name, h.backlog_per_head, coalesce(h.employees, 0)),
         jsonb_build_object('backlog_per_head', h.backlog_per_head, 'employees', h.employees,
                            'open_tasks', h.open_tasks, 'os_key', h.os_key),
         format('Either split the work of %s across more employees, or accept that the backlog is not going to be cleared and close what is no longer worth doing. Carrying it at this level is a decision by default.', h.name),
         'org'
    from v_os_health h
   where h.backlog_per_head > 5 and not exists (select 1 from evolution_proposal p
        where p.trigger_kind = 'audit_gap' and p.subject = h.name
          and p.created_at > now() - interval '30 days')
  on conflict do nothing;

  -- IS A NEW SPECIALIST NEEDED? Work exists in the department and no employee in it has run at all.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', z.dept_key,
         format('%s holds %s open task(s) and not one active employee in it has run in 30 days — the work has no one doing it.',
                z.dept_key, z.n),
         jsonb_build_object('open_tasks', z.n, 'department', z.dept_key),
         format('A new specialist is needed for %s, or the work belongs to a department that already has someone running. Decide which before hiring: staffing a queue that should have been routed elsewhere adds an employee and keeps the defect.', z.dept_key),
         'org'
    from (select t.dept_key, count(*) n from org_tasks t
           where t.status <> 'done' and t.dept_key is not null
             and not exists (select 1 from org_agents a join agent_runs r on r.agent = a.agent_key
                              and r.started_at > now() - interval '30 days'
                             where a.active and a.department = t.dept_key)
           group by t.dept_key having count(*) >= 5) z
   where not exists (select 1 from evolution_proposal p
        where p.trigger_kind = 'audit_gap' and p.subject = z.dept_key
          and p.created_at > now() - interval '30 days')
  on conflict do nothing;

  -- SHOULD TWO ROLES MERGE? Aggregated for the same reason as role_idle.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'audit_gap', 'organisation structure',
         format('%s department(s) have two or more employees who are ALL dormant: %s.', m.depts, m.sample),
         jsonb_build_object('departments', m.depts, 'sample', m.sample),
         'Consider whether these roles should merge. Two dormant employees in one department is either duplicated scope that should be consolidated into a single role, or a department that receives no work at all — and those two answers lead to opposite actions, so establish which before combining anything.',
         'org'
    from (select count(*) depts,
                 (select string_agg(y.department||' ('||y.n||')', ', ' order by y.n desc) from (
                    select a3.department, count(*) n from org_agents a3 where a3.active
                     and not exists (select 1 from agent_runs r3 where r3.agent = a3.agent_key
                                      and r3.started_at > now() - interval '30 days')
                     group by a3.department having count(*) >= 2 order by count(*) desc limit 5) y) sample
            from (select a.department from org_agents a where a.active
                   and not exists (select 1 from agent_runs r where r.agent = a.agent_key
                                    and r.started_at > now() - interval '30 days')
                   group by a.department having count(*) >= 2) q) m
   where m.depts > 0 and not exists (select 1 from evolution_proposal p
        where p.trigger_kind = 'audit_gap' and p.subject = 'organisation structure'
          and p.created_at > now() - interval '30 days')
  on conflict do nothing;

  return (select count(*) from evolution_proposal where status='proposed');
end; $function$
