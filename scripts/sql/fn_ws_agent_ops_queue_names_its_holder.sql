-- THE AGENT DRAWER'S QUEUE NAMES ITS HOLDER (6 Sep 2026).
--
-- OsxShell's per-agent drawer rendered "Decisions held for review" with Approve/Reject for the
-- founder on every open agent_action of that agent. Those rows are held with the role
-- fn_action_holder names, not with him; the only decision that is his is a refund
-- (agent_action_kind_policy.policy = 'founder'). Each queue row now carries 'holder' and 'yours'
-- so the drawer can show "Held with <holder> — not yours to approve" and keep buttons only where
-- yours = true — the same two keys fn_ws_operations gives the Operations page.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ws_agent_ops_queue_names_its_holder.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_ws_agent_ops(p_agent text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare ca public.category_agents%rowtype; pr public.prompts%rowtype;
  runs_total int; runs_24h int; runs_7d int; ok_runs int; last_run timestamptz; last_status text;
  avg_ms numeric; kn_updated timestamptz; kn_count int; mem_count int; health text;
  v_dept text; v_cap int; v_open int; v_queue int; v_goal jsonb; v_rep public.agent_reputation%rowtype;
begin
  select * into ca from public.category_agents where slug=p_agent;
  select * into pr from public.prompts where key=p_agent;

  -- RESOLVE HERE, NOT AT THE TOP. PLACEMENT IS LOAD-BEARING (15 Aug 2026).
  --
  -- Everything below this line reads org_agents, agent_runs, agent_knowledge, agent_memory,
  -- agent_actions, decision_log, employee_kpi_history, knowledge_exam_results and skills_matrix by
  -- agent_key, and every one of those missed for an employee addressed by an alias - so the whole
  -- workspace drawer came back empty for them: no runs, no knowledge, no KPIs, no learning curve.
  --
  -- But the TWO lookups above are keyed differently. category_agents.slug and prompts.key are
  -- alias-shaped: 14 alias values are also category_agents slugs, and none of the 132 slugs equals
  -- any org_agents.agent_key. Resolving before them would blank the name, emoji and persona for
  -- exactly the employees this repairs - trading an empty drawer for an anonymous one.
  p_agent := coalesce(public.fn_org_agent_resolve(p_agent), p_agent);
  select count(*), count(*) filter (where started_at>now()-interval '24 hours'),
         count(*) filter (where started_at>now()-interval '7 days'),
         count(*) filter (where status='ok'),
         max(started_at),
         coalesce(round(avg(extract(epoch from (finished_at-started_at))*1000) filter (where finished_at is not null),0),0)
    into runs_total, runs_24h, runs_7d, ok_runs, last_run, avg_ms
    from public.agent_runs where agent=p_agent;
  select status into last_status from public.agent_runs where agent=p_agent order by started_at desc limit 1;
  select count(*), max(updated_at) into kn_count, kn_updated from public.agent_knowledge where agent_key=p_agent;
  select count(*) into mem_count from public.agent_memory where agent_key=p_agent;
  health := case
    when last_status is null then 'idle'
    when last_status in ('error','failed') then 'degraded'
    when last_run < now()-interval '3 days' then 'stale'
    else 'healthy' end;

  select a.department, a.max_open_tasks into v_dept, v_cap
    from public.org_agents a where a.agent_key = p_agent;
  select * into v_rep from public.agent_reputation where agent_key = p_agent;

  -- The employee's own open items, and the open work sitting in their department.
  select count(*) into v_queue from public.agent_actions
   where agent = p_agent and status in ('pending','held_for_review','proposed','open');
  select count(*) into v_open from public.org_tasks
   where dept_key = v_dept and coalesce(status,'') <> 'done';

  -- CURRENT GOAL, resolved down the chain until something real answers.
  select case
    when o.objective is not null then jsonb_build_object(
      'objective', o.objective, 'horizon', o.horizon, 'status', o.status,
      'goal_source', 'department_objective', 'dept', v_dept)
    when cg.goal is not null then jsonb_build_object(
      'objective', cg.goal, 'horizon', cg.horizon, 'metric', cg.metric,
      'target_value', cg.target_value, 'unit', cg.unit,
      'goal_source', 'company_goals', 'dept', v_dept)
    when d.north_star is not null then jsonb_build_object(
      'objective', d.north_star, 'horizon', 'standing',
      'goal_source', 'department_north_star', 'dept', v_dept)
    else jsonb_build_object('objective', null, 'goal_source', 'none', 'dept', v_dept)
  end into v_goal
  from (select 1) _
  left join lateral (select * from public.department_objective x
                      where x.dept_key = v_dept and x.active
                      order by x.sort nulls last, x.updated_at desc limit 1) o on true
  left join lateral (select * from public.company_goals c
                      where c.owner_dept = v_dept and c.active
                      order by c.sort nulls last limit 1) cg on true
  left join public.org_departments d on d.dept_key = v_dept;

  return jsonb_build_object(
    'identity', jsonb_build_object('key',p_agent,'name',coalesce(ca.name,pr.description,p_agent),
       'emoji',ca.emoji,'active',coalesce(ca.active,true),'persona',ca.persona,
       'department', v_dept,
       'prompt_version',pr.active_version,'prompt_desc',pr.description,'prompt_owner',pr.owner,'prompt_updated',pr.updated_at,
       'knowledge_updated',kn_updated),
    'health', jsonb_build_object('status',health,'last_run',last_run,'last_status',last_status),
    'performance', jsonb_build_object('runs_total',runs_total,'runs_24h',runs_24h,'runs_7d',runs_7d,
       'ok_rate', case when runs_total>0 then round(100.0*ok_runs/runs_total,1) else null end,
       'avg_duration_ms',avg_ms),

    -- PERFORMANCE AS A TREND, NOT A POINT (11 Aug 2026). Every number above is a single current
    -- value, so the drawer could show how this employee is doing and never whether it is getting
    -- better or worse. employee_kpi_history writes one row per KPI per UTC day with a unique index
    -- that makes a fabricated trend impossible; this is its first reader. Attainment is averaged
    -- across the employee's KPIs for the day, so the series is "how this person performed", not
    -- one arbitrary KPI of theirs. Oldest-first because that is the order a line is drawn in.
    'kpi_trend', (select coalesce(jsonb_agg(jsonb_build_object(
                        'label', to_char(t.measured_on, 'DD Mon'),
                        'v', t.attainment,
                        'kpis', t.n) order by t.measured_on), '[]'::jsonb)
                    from (select h.measured_on,
                                 round(avg(h.attainment)::numeric, 1) attainment,
                                 count(*) n
                            from public.employee_kpi_history h
                           where h.agent_key = p_agent
                             and h.measured_on > (now() at time zone 'utc')::date - 90
                           group by h.measured_on
                           order by h.measured_on desc
                           limit 30) t),

    -- ── THE SIX THAT WERE COMPUTED AND NEVER DELIVERED ─────────────────────────────────────────
    'goal', v_goal,

    'tasks', jsonb_build_object(
      'mine_open', v_queue,
      'department', v_dept,
      'department_open', v_open,
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                 'id',t.id,'title',t.title,'status',t.status,'tier',t.tier,
                 'needs_founder',t.needs_founder,'created_at',t.created_at,'last_run_at',t.last_run_at)
               order by (coalesce(t.status,'')='done'), t.created_at desc)
             from (select * from public.org_tasks where dept_key = v_dept
                    and coalesce(status,'') <> 'done' order by created_at desc limit 12) t), '[]'::jsonb)),

    'decisions', coalesce((select jsonb_agg(jsonb_build_object(
                 'id',l.id,'kind',l.kind,'decision',l.decision,'confidence',l.confidence,
                 'route_to',l.route_to,'reasons',l.reasons,'sources',l.sources,'at',l.created_at)
               order by l.created_at desc)
             from (select * from public.decision_log where actor = p_agent
                    order by created_at desc limit 10) l), '[]'::jsonb),

    'confidence', jsonb_build_object(
      'reputation_score', v_rep.score, 'tier', v_rep.tier,
      'correctness', v_rep.correctness, 'reliability', v_rep.reliability,
      'learning_speed', v_rep.learning_speed, 'computed_at', v_rep.computed_at,
      'avg_decided', (select round(avg(confidence)::numeric, 2) from public.decision_log
                       where actor = p_agent and confidence is not null),
      'decided_with_confidence', (select count(*) from public.decision_log
                                   where actor = p_agent and confidence is not null)),

    'workload', jsonb_build_object(
      'open_tasks', v_open, 'queue_depth', v_queue, 'capacity', v_cap,
      'workload_pct', case when coalesce(v_cap,0) > 0
                           then round(100.0 * (v_open + v_queue) / v_cap, 1) else null end,
      'state', case when coalesce(v_cap,0) = 0 then 'unset'
                    when (v_open + v_queue) > v_cap then 'over'
                    when (v_open + v_queue) > v_cap * 0.8 then 'tight' else 'ok' end),

    'plans', coalesce((select jsonb_agg(jsonb_build_object(
                 'objective',p.objective,'horizon',p.horizon,'status',p.status,'scope','department')
               order by p.sort nulls last)
             from public.department_objective p where p.dept_key = v_dept and p.active), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_build_object(
                 'objective',o.objective,'horizon',o.horizon,'measure',o.measure,'scope','operating_system')
               order by o.id)
             from public.os_objective o
             where o.active and o.os_key = (select r.os_key from public.os_responsibility r
                                             where r.responsibility = v_dept limit 1)), '[]'::jsonb),

    -- WHAT THIS EMPLOYEE IS SUPPOSED TO KNOW (13 Aug 2026). employee_knowledge holds 900 rows over
    -- 66 employees - the domains each one is expected to cover and at what depth - and had NO
    -- browser-reachable reader at all. The `knowledge` block below is a different table:
    -- agent_knowledge is what has been WRITTEN for them, this is the curriculum they are measured
    -- against. Showing only the first without the second means a drawer can look full while the
    -- employee covers one of twelve domains they are meant to hold.
    'curriculum', jsonb_build_object(
       'domains', (select count(*) from public.employee_knowledge ek where ek.agent_key = p_agent),
       'rows', coalesce((select jsonb_agg(jsonb_build_object('domain',ek.domain_key,'depth',ek.depth,'layer',ek.layer_no)
                                order by ek.layer_no nulls last, ek.domain_key)
                           from public.employee_knowledge ek where ek.agent_key = p_agent),'[]'::jsonb),
       'by_depth', coalesce((select jsonb_object_agg(d.depth, d.n)
                               from (select coalesce(ek.depth,'unspecified') depth, count(*) n
                                       from public.employee_knowledge ek where ek.agent_key = p_agent
                                      group by 1) d),'{}'::jsonb)),
    'knowledge', jsonb_build_object('count',kn_count,'updated',kn_updated,

       'topics', coalesce((select jsonb_agg(distinct topic) from public.agent_knowledge where agent_key=p_agent and topic is not null),'[]'::jsonb),
       'recent', coalesce((select jsonb_agg(jsonb_build_object('topic',topic,'priority',priority,'updated',updated_at) order by updated_at desc)
                    from (select * from public.agent_knowledge where agent_key=p_agent order by updated_at desc limit 6) x),'[]'::jsonb)),
    'memory', jsonb_build_object('count',mem_count,
       'recent', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'content',left(content,140),'importance',importance,'at',created_at) order by created_at desc)
                    from (select * from public.agent_memory where agent_key=p_agent order by created_at desc limit 6) x),'[]'::jsonb)),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'risk',risk,'status',status,'recommendation',recommendation,'created_at',created_at,
                   -- NOT HIS unless the kind's policy is 'founder' (a refund). The holder is the role that decides it.
                   'holder', public.fn_action_holder(x.kind, x.agent),
                   'yours', exists (select 1 from public.agent_action_kind_policy kp where kp.kind = x.kind and kp.policy = 'founder')) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and status in ('pending','held_for_review','proposed','open') order by created_at desc limit 12) x),'[]'::jsonb),
    'conversations', coalesce((select jsonb_agg(jsonb_build_object('role',role,'content',left(content,160),'at',created_at) order by created_at desc)
                 from (select * from public.agent_chats where agent_key=p_agent order by created_at desc limit 8) x),'[]'::jsonb),
    -- LEARNING PROGRESS. The employee workspace showed goal, tasks, decisions, confidence,
    -- workload, plans, knowledge, health, performance, queue, runs, memory, conversations and
    -- recommendations - everything except whether this employee is getting BETTER. The founder's
    -- operating model asks each employee to "learn from performance, failures, outcomes and new
    -- information" and to "improve its decisions and methods over time", and the drawer had no key
    -- for it, so knowledge_exam_results (576 rows over 98 employees) and skills_matrix (695 rows)
    -- were written and never read by any browser-reachable surface.
    --
    -- exam_trend is one point PER DAY, oldest first, because a curve is the only form in which
    -- "improving" is visible. A single aggregate score cannot say whether it went up.
    'learning', jsonb_build_object(
      'exam_results_total', (select count(*) from public.knowledge_exam_results where agent_key = p_agent),
      'exam_days',          (select count(distinct created_at::date) from public.knowledge_exam_results where agent_key = p_agent),
      'exam_score_pct',     (select round(100.0 * count(*) filter (where verdict = 'correct') / nullif(count(*),0), 1)
                               from public.knowledge_exam_results where agent_key = p_agent),
      'last_exam_at',       (select max(created_at) from public.knowledge_exam_results where agent_key = p_agent),
      'exam_trend', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'asked', n, 'score_pct', pct) order by d)
                     from (select created_at::date d, count(*) n,
                                  round(100.0 * count(*) filter (where verdict = 'correct') / nullif(count(*),0), 1) pct
                             from public.knowledge_exam_results where agent_key = p_agent
                            group by 1 order by 1 desc limit 14) t), '[]'::jsonb),
      'knowledge_gaps_found', (select count(*) from public.knowledge_exam_results
                                where agent_key = p_agent and gap_fact is not null),
      'knowledge_gaps_filled', (select count(*) from public.knowledge_exam_results
                                 where agent_key = p_agent and filled),
      'skills', coalesce((select jsonb_agg(jsonb_build_object('skill', skill, 'rating', rating) order by skill)
                 from public.skills_matrix where agent_key = p_agent), '[]'::jsonb)),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'recommendation',left(recommendation,180),'risk',risk,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and recommendation is not null order by created_at desc limit 6) x),'[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',kind,'status',status,'decided_by',decided_by,'decided_at',decided_at,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent order by created_at desc limit 12) x),'[]'::jsonb),
    'recent_runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'note',note,'started_at',started_at,'finished_at',finished_at) order by started_at desc)
                 from (select * from public.agent_runs where agent=p_agent order by started_at desc limit 8) x),'[]'::jsonb)
  );
end $function$;
