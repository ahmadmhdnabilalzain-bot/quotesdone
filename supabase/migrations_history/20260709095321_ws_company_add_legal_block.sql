-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709095321   name: ws_company_add_legal_block
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_company()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'legal', jsonb_build_object(
      'health', (select (kpis->>'legal_health')::numeric from legal_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from legal_kpis k),
      'missing_docs', coalesce((select jsonb_agg(jsonb_build_object('requirement',requirement,'priority',priority,'applies_to',applies_to) order by priority) from legal_checklist where not present),'[]'::jsonb),
      'flags', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='legal_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'reviews', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',doc_kind,'risk',risk_level,'at',reviewed_at) order by reviewed_at desc) from (select * from legal_reviews order by reviewed_at desc limit 10) r),'[]'::jsonb)
    ),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'actions',c,'pending',pend,'last_active',la) order by c desc) from (
        select coalesce(agent,'—') agent, count(*) c,
               count(*) filter (where status='pending') pend, max(created_at) la
        from agent_actions group by 1 order by 2 desc limit 20) d),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'status',status,'started_at',started_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb),
    'evals', coalesce((select jsonb_agg(jsonb_build_object('snapshot_at',snapshot_at,'window_days',window_days,'kpis',kpis)) from (select * from agent_evals order by snapshot_at desc limit 4) e),'[]'::jsonb)
  );
$function$;
revoke all on function public.fn_ws_company() from anon, authenticated, public;
