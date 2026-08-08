-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708113638   name: erp_ws_ai_agents_ops
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Registry of agents with per-agent activity KPIs
create or replace function public.fn_ws_agents()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
begin
  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents', (select count(distinct agent) from public.agent_runs where agent is not null),
      'runs_24h', (select count(*) from public.agent_runs where started_at > now()-interval '24 hours'),
      'actions_total', (select count(*) from public.agent_actions),
      'actions_pending', (select count(*) from public.agent_actions where status in ('pending','held_for_review','proposed','open')),
      'memory_items', (select count(*) from public.agent_memory),
      'knowledge_items', (select count(*) from public.agent_knowledge)
    ),
    'rows', (
      with keys as (
        select distinct k from (
          select agent k from public.agent_runs where agent is not null
          union select agent from public.agent_actions where agent is not null
          union select key from public.prompts where key is not null
          union select slug from public.category_agents where slug is not null
        ) u
      )
      select coalesce(jsonb_agg(r order by (r->>'runs_total')::int desc nulls last, r->>'name'),'[]'::jsonb)
      from (
        select jsonb_build_object(
          'key', k.k,
          'name', coalesce(ca.name, pr.description, k.k),
          'emoji', ca.emoji,
          'active', coalesce(ca.active, true),
          'prompt_version', pr.active_version,
          'runs_total', (select count(*) from public.agent_runs ar where ar.agent=k.k),
          'runs_24h', (select count(*) from public.agent_runs ar where ar.agent=k.k and ar.started_at>now()-interval '24 hours'),
          'last_run', (select max(started_at) from public.agent_runs ar where ar.agent=k.k),
          'last_status', (select status from public.agent_runs ar where ar.agent=k.k order by started_at desc limit 1),
          'actions_pending', (select count(*) from public.agent_actions aa where aa.agent=k.k and aa.status in ('pending','held_for_review','proposed','open')),
          'memory', (select count(*) from public.agent_memory am where am.agent_key=k.k),
          'knowledge', (select count(*) from public.agent_knowledge ak where ak.agent_key=k.k)
        ) r
        from keys k
        left join public.category_agents ca on ca.slug=k.k
        left join public.prompts pr on pr.key=k.k
      ) s
    )
  );
end $$;

-- Per-agent operations detail
create or replace function public.fn_ws_agent_ops(p_agent text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare ca public.category_agents%rowtype; pr public.prompts%rowtype;
  runs_total int; runs_24h int; runs_7d int; ok_runs int; last_run timestamptz; last_status text;
  avg_ms numeric; kn_updated timestamptz; kn_count int; mem_count int; health text;
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

  return jsonb_build_object(
    'identity', jsonb_build_object('key',p_agent,'name',coalesce(ca.name,pr.description,p_agent),
       'emoji',ca.emoji,'active',coalesce(ca.active,true),'persona',ca.persona,
       'prompt_version',pr.active_version,'prompt_desc',pr.description,'prompt_owner',pr.owner,'prompt_updated',pr.updated_at,
       'knowledge_updated',kn_updated),
    'health', jsonb_build_object('status',health,'last_run',last_run,'last_status',last_status),
    'performance', jsonb_build_object('runs_total',runs_total,'runs_24h',runs_24h,'runs_7d',runs_7d,
       'ok_rate', case when runs_total>0 then round(100.0*ok_runs/runs_total,1) else null end,
       'avg_duration_ms',avg_ms),
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
end $$;

revoke execute on function public.fn_ws_agents() from anon, authenticated, public;
revoke execute on function public.fn_ws_agent_ops(text) from anon, authenticated, public;
