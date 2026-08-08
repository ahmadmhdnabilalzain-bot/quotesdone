-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724143508   name: ws_agents_honest_count
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Dashboard fix (founder-requested): 'agents' now counts REGISTERED MINDS
-- (department executives + named staff + category experts + intel officers),
-- not every distinct name that ever wrote to the agent_runs log. Infrastructure
-- jobs (uptime, smoke, email_cron, webhooks...) are reported separately as
-- 'automations'. Rows gain kind: agent | automation. Also fixes the cat: prefix
-- mismatch so category rows show their knowledge counts.
create or replace function public.fn_ws_agents()
 returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog'
as $function$
declare v_minds jsonb;
begin
  -- The registry of real minds: org executives, category experts, intel officers,
  -- and any key that holds its own knowledge (covers secretary/designer).
  create temp table if not exists _minds (k text primary key) on commit drop;
  insert into _minds
    select agent_key from public.org_agents where active
    union select 'cat:'||slug from public.category_agents where active
    union select slug from public.category_agents where active
    union select distinct agent_key from public.agent_knowledge where agent_key <> '_global'
  on conflict do nothing;

  return jsonb_build_object(
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
    'rows', (
      with keys as (
        select distinct k from (
          select agent k from public.agent_runs where agent is not null and agent <> ''
          union select agent from public.agent_actions where agent is not null
          union select key from public.prompts where key is not null
          union select slug from public.category_agents where slug is not null
          union select agent_key from public.org_agents where active
        ) u
      )
      select coalesce(jsonb_agg(r order by (r->>'runs_total')::int desc nulls last, r->>'name'),'[]'::jsonb)
      from (
        select jsonb_build_object(
          'key', k.k,
          'name', coalesce(ca.name, pr.description, k.k),
          'emoji', ca.emoji,
          'kind', case when exists (select 1 from _minds m where m.k=k.k) then 'agent' else 'automation' end,
          'active', coalesce(ca.active, true),
          'prompt_version', pr.active_version,
          'runs_total', (select count(*) from public.agent_runs ar where ar.agent=k.k),
          'runs_24h', (select count(*) from public.agent_runs ar where ar.agent=k.k and ar.started_at>now()-interval '24 hours'),
          'last_run', (select max(started_at) from public.agent_runs ar where ar.agent=k.k),
          'last_status', (select status from public.agent_runs ar where ar.agent=k.k order by started_at desc limit 1),
          'actions_pending', (select count(*) from public.agent_actions aa where aa.agent=k.k and aa.status in ('pending','held_for_review','proposed','open')),
          'memory', (select count(*) from public.agent_memory am where am.agent_key=k.k),
          'knowledge', (select count(*) from public.agent_knowledge ak where ak.agent_key in (k.k, 'cat:'||k.k))
        ) r
        from keys k
        left join public.category_agents ca on ca.slug=k.k
        left join public.prompts pr on pr.key=k.k
      ) s
    )
  );
end $function$;
revoke execute on function public.fn_ws_agents() from public, anon, authenticated;
