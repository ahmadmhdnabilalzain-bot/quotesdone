-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706165528   name: os_command_center_rollup
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Single rollup the OS Command Center reads. Composes existing live functions
-- (fn_health_index, fn_ops_dashboard) + core counts. SECURITY DEFINER, locked down.
create or replace function public.fn_os_command()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_health jsonb;
  v_ops jsonb;
  v_counts jsonb;
  v_attention jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  -- recent governed decisions routed to a human (the "attention" stream)
  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           jsonb_build_object(
             'id', id, 'actor', actor, 'kind', kind, 'decision', decision,
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at
           ) as x
    from decision_log
    where route_to is not null and route_to <> 'auto'
    order by created_at desc
    limit 8
  ) t;

  return jsonb_build_object(
    'ok', true,
    'generated_at', now(),
    'health', v_health,
    'ops', v_ops,
    'counts', v_counts,
    'attention', v_attention
  );
end;
$$;

revoke all on function public.fn_os_command() from public, anon, authenticated;
grant execute on function public.fn_os_command() to service_role;
