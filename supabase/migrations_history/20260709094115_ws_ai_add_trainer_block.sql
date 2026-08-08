-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709094115   name: ws_ai_add_trainer_block
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_ai()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents',(select count(*) from category_agents),
      'agents_active',(select count(*) from category_agents where active is true),
      'actions_total',(select count(*) from agent_actions),
      'actions_pending',(select count(*) from agent_actions where status='pending'),
      'runs_24h',(select count(*) from agent_runs where started_at > now()-interval '24 hours'),
      'avg_confidence',(select round(avg(confidence)::numeric,2) from decision_log where confidence is not null)
    ),
    'trainer', jsonb_build_object(
      'ai_health', (select (kpis->>'ai_health')::numeric from ai_trainer_snapshots order by snapshot_date desc limit 1),
      'metrics', (select kpis from ai_trainer_snapshots order by snapshot_date desc limit 1),
      'weak_agents', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'run_success_pct',run_success_pct,'rejection_rate_pct',rejection_rate_pct,'errors',errors) order by run_success_pct nulls last)
          from ai_agent_quality where runs_30d>=20 and (coalesce(run_success_pct,100)<95 or coalesce(rejection_rate_pct,0)>20)),'[]'::jsonb),
      'proposals', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='ai_trainer' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('slug',ca.slug,'name',ca.name,'emoji',ca.emoji,'active',ca.active,
        'actions',(select count(*) from agent_actions a where a.agent=ca.slug),
        'pending',(select count(*) from agent_actions a where a.agent=ca.slug and a.status='pending')) order by ca.name) from category_agents ca),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (
        select coalesce(nullif(kind,''),'other') k, count(*) c from agent_actions group by 1 order by 2 desc limit 12) kk),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'status',status,'started_at',started_at,'finished_at',finished_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb)
  );
$function$;
revoke all on function public.fn_ws_ai() from anon, authenticated, public;
