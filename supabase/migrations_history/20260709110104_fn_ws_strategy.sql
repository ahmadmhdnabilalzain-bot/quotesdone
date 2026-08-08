-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709110104   name: fn_ws_strategy
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_strategy()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.strategy_kpis k),
    'risks', (select coalesce(jsonb_agg(r),'[]'::jsonb) from (
        select title, category, score, likelihood, impact, status
        from public.strategy_risks where status<>'closed' order by score desc limit 20) r),
    'recommendations', (select coalesce(jsonb_agg(x),'[]'::jsonb) from (
        select title, risk, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where agent='strategy_ai' and kind='strategy_rec'
          and status in ('pending','needs_review') order by array_position(array['high','medium','low']::text[],risk)) x),
    'under_supplied', coalesce(fn_strategy_metrics()->'under_supplied','[]'::jsonb),
    'market_intel', (select coalesce(jsonb_agg(m),'[]'::jsonb) from (
        select kind, title, impact, status, coalesce(source,'—') as source
        from public.market_intel where status<>'dismissed' order by created_at desc limit 20) m),
    'recent_simulations', (select coalesce(jsonb_agg(s),'[]'::jsonb) from (
        select coalesce(scenario->>'type','scenario') as title,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.simulations order by created_at desc limit 8) s)
  );
$$;
revoke all on function public.fn_ws_strategy() from anon, authenticated, public;
