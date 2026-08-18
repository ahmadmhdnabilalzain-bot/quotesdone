CREATE OR REPLACE FUNCTION public.fn_ws_agents()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_out jsonb;
begin
  create temp table if not exists _minds (k text primary key) on commit drop;
  insert into _minds
    select agent_key from public.org_agents where active
    union select 'cat:'||slug from public.category_agents where active
    union select slug from public.category_agents where active
    union select distinct agent_key from public.agent_knowledge where agent_key <> '_global'
  on conflict do nothing;

  with keys as (
    select distinct k from (
      select agent k from public.agent_runs where agent is not null and agent <> ''
      union select agent from public.agent_actions where agent is not null
      union select key from public.prompts where key is not null
      union select slug from public.category_agents where slug is not null
      union select agent_key from public.org_agents where active
    ) u
  ),
  -- ONE PASS PER SOURCE. Previously each of these was a subquery re-evaluated for all 356 keys.
  runs as (
    select agent k, count(*) runs_total,
           count(*) filter (where started_at > now() - interval '24 hours') runs_24h,
           max(started_at) last_run
      from public.agent_runs where agent is not null and agent <> '' group by agent
  ),
  -- The newest run's status, taken with a window rather than a per-key ORDER BY ... LIMIT 1.
  last_status as (
    select k, status from (
      select agent k, status, row_number() over (partition by agent order by started_at desc) rn
        from public.agent_runs where agent is not null and agent <> ''
    ) z where rn = 1
  ),
  acts as (
    select agent k, count(*) filter (where status in ('pending','held_for_review','proposed','open')) actions_pending
      from public.agent_actions where agent is not null group by agent
  ),
  mem as (select agent_key k, count(*) n from public.agent_memory group by agent_key),
  kn  as (select agent_key k, count(*) n from public.agent_knowledge group by agent_key)
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents', (select count(distinct case when m.k like 'cat:%' then m.k
                                            when exists (select 1 from _minds m2 where m2.k='cat:'||m.k) then 'cat:'||m.k
                                            else m.k end) from _minds m),
      'automations', (select count(distinct ar.agent) from public.agent_runs ar
                      where ar.agent is not null and ar.agent <> ''
                        and not exists (select 1 from _minds m where m.k=ar.agent)),
      'runs_24h', (select count(*) from public.agent_runs where started_at > now()-interval '24 hours'),
      'actions_total', (select count(*) from public.agent_actions),
      'actions_pending', (select count(*) from public.agent_actions where status in ('pending','held_for_review','proposed','open')),
      'memory_items', (select count(*) from public.agent_memory),
      'knowledge_items', (select count(*) from public.agent_knowledge)
    ),
    'rows', coalesce((
      select jsonb_agg(r order by (r->>'runs_total')::int desc nulls last, r->>'name')
      from (
        select jsonb_build_object(
          'key', k.k,
          'name', coalesce(ca.name, pr.description, k.k),
          'emoji', ca.emoji,
          'kind', case when exists (select 1 from _minds m where m.k=k.k) then 'agent' else 'automation' end,
          'active', coalesce(ca.active, true),
          'prompt_version', pr.active_version,
          'runs_total', coalesce(ru.runs_total, 0),
          'runs_24h', coalesce(ru.runs_24h, 0),
          'last_run', ru.last_run,
          'last_status', ls.status,
          'actions_pending', coalesce(ac.actions_pending, 0),
          'memory', coalesce(me.n, 0),
          -- Both the bare key and its 'cat:' twin, exactly as the IN (k, 'cat:'||k) did.
          'knowledge', coalesce(kb.n, 0) + coalesce(kc.n, 0)
        ) r
        from keys k
        left join public.category_agents ca on ca.slug = k.k
        left join public.prompts pr on pr.key = k.k
        left join runs ru on ru.k = k.k
        left join last_status ls on ls.k = k.k
        left join acts ac on ac.k = k.k
        left join mem me on me.k = k.k
        left join kn kb on kb.k = k.k
        left join kn kc on kc.k = 'cat:' || k.k
      ) s), '[]'::jsonb)
  ) into v_out;

  return v_out;
end $function$
