-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726142450   name: knowledge_gap_loop
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Per-agent knowledge freshness measurement. Maps both key conventions (bare slug for
-- functional agents, cat:<slug> for trade agents). Read-only.
create or replace function public.fn_knowledge_gaps(p_stale_days int default 14, p_thin_min int default 4)
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  with base as (
    select ca.slug, ca.name, ca.emoji,
      (select count(*) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as items,
      (select max(updated_at) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as last_updated
    from category_agents ca where coalesce(ca.active,true)
  ),
  scored as (
    select slug, name, emoji, items, last_updated,
      case when last_updated is null then null else floor(extract(epoch from (now()-last_updated))/86400)::int end as days_stale,
      case when items = 0 then 'missing'
           when last_updated < now() - (p_stale_days||' days')::interval then 'stale'
           when items < p_thin_min then 'thin'
           else 'ok' end as status
    from base
  )
  select jsonb_build_object(
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status='ok'),
      'stale', (select count(*) from scored where status='stale'),
      'thin', (select count(*) from scored where status='thin'),
      'missing', (select count(*) from scored where status='missing'),
      'coverage_pct', round(100.0 * (select count(*) from scored where status='ok') / nullif((select count(*) from scored),0), 1)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', emoji, 'items', items,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status
      ) order by case status when 'stale' then 0 when 'thin' then 1 when 'missing' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb)
  );
$$;

-- Detect + dispatch + auto-close loop. Uses kn_task (idempotent create when the gap exists,
-- auto-resolve when it clears) so a task closes only once the agent's knowledge is actually fresh
-- again — the "verify" step is built in. Only stale/thin agents are tasked; genuinely-empty
-- orchestrators (status=missing, e.g. chief_of_staff) are surfaced but not tasked to avoid noise.
create or replace function public.fn_dispatch_agent_knowledge_gaps(p_stale_days int default 14, p_thin_min int default 4)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare a jsonb; g jsonb; opened int := 0; resolved_before int; resolved_after int; total_gap int := 0;
begin
  g := fn_knowledge_gaps(p_stale_days, p_thin_min);
  select count(*) into resolved_before from agent_actions where kind='knowledge_task' and detail->>'signal' like 'agent_knowledge:%' and status in ('pending','needs_review');
  for a in select * from jsonb_array_elements(g->'agents') loop
    declare v_gap boolean := (a->>'status') in ('stale','thin'); v_slug text := a->>'slug';
    begin
      if v_gap then total_gap := total_gap + 1; end if;
      perform kn_task('agent_knowledge:'||v_slug, v_gap, case when (a->>'status')='thin' then 'low' else 'medium' end,
        'Refresh knowledge: '||coalesce(a->>'name',v_slug),
        coalesce(a->>'name',v_slug)||' has '||coalesce(a->>'items','0')||' knowledge item(s), last refreshed '||
        coalesce((a->>'days_stale')||' days ago','never')||' (status: '||(a->>'status')||'). Regenerate its field brief so it advises with current expertise. Auto-closes once refreshed.');
    end;
  end loop;
  select count(*) into resolved_after from agent_actions where kind='knowledge_task' and detail->>'signal' like 'agent_knowledge:%' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at', now(), 'gaps_found', total_gap, 'open_tasks', resolved_after,
    'summary', g->'summary');
end $$;

revoke execute on function public.fn_knowledge_gaps(int,int) from anon, authenticated, public;
revoke execute on function public.fn_dispatch_agent_knowledge_gaps(int,int) from anon, authenticated, public;
