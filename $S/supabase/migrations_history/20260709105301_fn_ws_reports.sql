-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709105301   name: fn_ws_reports
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_reports()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select source, report_type, title, period, to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry order by created_at desc limit 20) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, title, to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, title, created_at
          from public.report_registry order by report_type, created_at desc
        ) x order by report_type) t),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$$;
revoke all on function public.fn_ws_reports() from anon, authenticated, public;
