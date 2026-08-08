-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709082330   name: ws_customers_add_success_block
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_customers()
 returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from customers),
      'verified',(select count(*) from customers where phone_verified is true or email_verified is true),
      'banned',(select count(*) from customers where banned is true),
      'with_rfqs',(select count(distinct customer_id) from inquiries where customer_id is not null)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from customer_kpis k),'{}'::jsonb),
      'open_escalations', (select count(*) from agent_actions where kind='customer_escalation' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',customer_id,'name',coalesce(full_name,email),'health',health,
            'engagement',engagement,'satisfaction',satisfaction,'progress',progress,'service',service,
            'risk_tier',risk_tier,'stalled',stalled_inq,'disputes',disputes,'dormant',dormant) a
          from customer_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from customer_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
        'phone_verified',c.phone_verified,'email_verified',c.email_verified,'banned',c.banned,'created_at',c.created_at,
        'rfqs',(select count(*) from inquiries i where i.customer_id=c.id),
        'projects',(select count(*) from projects p where p.customer_id=c.id))) from (select * from customers order by created_at desc limit 100) c),'[]'::jsonb)
  );
$function$;
