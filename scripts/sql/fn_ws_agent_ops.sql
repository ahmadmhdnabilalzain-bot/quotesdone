-- fn_ws_agent_ops — the EMPLOYEE WORKSPACE, extended.
--
-- Screen 5 of the executive-UI spec asks what an employee is doing: their current goal, their
-- tasks, their recent decisions, their confidence, their workload and their upcoming plans. The
-- drawer showed identity, health, performance, knowledge, memory and an approval queue, and none of
-- the other six — every one of them computed elsewhere in the estate and handed to nobody:
--
--   goal        department_objective -> company_goals -> org_departments.north_star
--   tasks       org_tasks (739 rows, 473 open) + this employee's own agent_actions
--   decisions   decision_log (1,276 rows across 49 actors)
--   confidence  agent_reputation (one scored row per employee) + decided confidence
--   workload    open tasks against org_agents.max_open_tasks, the capacity the org model sets
--   plans       department_objective + os_objective, forward horizons only
--
-- THE GOAL CHAIN IS A CHAIN BECAUSE THE DATA IS UNEVEN. 56 of 66 employees sit in a department that
-- keeps an active objective; evolution, intelligence and knowledge_eng do not. Rather than hand
-- those ten employees a null, the goal falls back to the company goal their department owns, and
-- then to the department's own north star — which every department has. `goal_source` travels with
-- it so the founder can always see which rung answered.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ws_agent_ops.sql --promote
create or replace function public.fn_ws_agent_ops(p_agent text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare ca public.category_agents%rowtype; pr public.prompts%rowtype;
  runs_total int; runs_24h int; runs_7d int; ok_runs int; last_run timestamptz; last_status text;
  avg_ms numeric; kn_updated timestamptz; kn_count int; mem_count int; health text;
  v_dept text; v_cap int; v_open int; v_queue int; v_goal jsonb; v_rep public.agent_reputation%rowtype;
begin
  select * into ca from public.category_agents where slug=p_agent;
  select * into pr from public.prompts where key=p_agent;
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

    'knowledge', jsonb_build_object('count',kn_count,'updated',kn_updated,
       'topics', coalesce((select jsonb_agg(distinct topic) from public.agent_knowledge where agent_key=p_agent and topic is not null),'[]'::jsonb),
       'recent', coalesce((select jsonb_agg(jsonb_build_object('topic',topic,'priority',priority,'updated',updated_at) order by updated_at desc)
                    from (select * from public.agent_knowledge where agent_key=p_agent order by updated_at desc limit 6) x),'[]'::jsonb)),
    'memory', jsonb_build_object('count',mem_count,
       'recent', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'content',left(content,140),'importance',importance,'at',created_at) order by created_at desc)
                    from (select * from public.agent_memory where agent_key=p_agent order by created_at desc limit 6) x),'[]'::jsonb)),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'risk',risk,'status',status,'recommendation',recommendation,'created_at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and status in ('pending','held_for_review','proposed','open') order by created_at desc limit 12) x),'[]'::jsonb),
    'conversations', coalesce((select jsonb_agg(jsonb_build_object('role',role,'content',left(content,160),'at',created_at) order by created_at desc)
                 from (select * from public.agent_chats where agent_key=p_agent order by created_at desc limit 8) x),'[]'::jsonb),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'recommendation',left(recommendation,180),'risk',risk,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and recommendation is not null order by created_at desc limit 6) x),'[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',kind,'status',status,'decided_by',decided_by,'decided_at',decided_at,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent order by created_at desc limit 12) x),'[]'::jsonb),
    'recent_runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'note',note,'started_at',started_at,'finished_at',finished_at) order by started_at desc)
                 from (select * from public.agent_runs where agent=p_agent order by started_at desc limit 8) x),'[]'::jsonb)
  );
end $function$;
