-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260713141850   name: exclude_canary_from_suppliers_view
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

CREATE OR REPLACE FUNCTION public.fn_ws_suppliers(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_q text := nullif(trim(coalesce(p->>'q','')),'');
  v_emirate text := nullif(p->>'emirate','');
  v_sector text := nullif(p->>'sector','');
  v_approval text := nullif(p->>'approval','');
  v_limit int := least(coalesce((p->>'limit')::int,50),100);
  v_offset int := greatest(coalesce((p->>'offset')::int,0),0);
  v_rows jsonb; v_total bigint;
begin
  select count(*) into v_total from leads
   where coalesce(source,'') <> 'canary'
     and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
     and (v_emirate is null or emirate=v_emirate)
     and (v_sector is null or sector=v_sector)
     and (v_approval is null or approval_status=v_approval);

  select coalesce(jsonb_agg(r),'[]'::jsonb) into v_rows from (
    select jsonb_build_object('id',id,'company_name',company_name,'sector',sector,'sub_type',sub_type,
      'emirate',emirate,'city',city,'rating',rating,'reviews',reviews,'categories',categories,
      'approval_status',approval_status,'lifecycle_stage',lifecycle_stage,'verified',verified,
      'verification_status',verification_status,'capability_score',capability_score,'invite_status',invite_status,
      'registration_status',registration_status,'license_expiry',license_expiry,'banned',banned,
      'matching_blocked',matching_blocked,'phone',phone,'website',website,'created_at',created_at) as r
    from leads
    where coalesce(source,'') <> 'canary'
      and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
      and (v_emirate is null or emirate=v_emirate)
      and (v_sector is null or sector=v_sector)
      and (v_approval is null or approval_status=v_approval)
    order by capability_score desc nulls last, reviews desc nulls last
    limit v_limit offset v_offset
  ) x;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from leads where coalesce(source,'') <> 'canary'),
      'approved',(select count(*) from leads where approval_status='approved'),
      'pending_review',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'verified',(select count(*) from leads where verified is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'licenses_expiring',(select count(*) from leads where license_expiry is not null and license_expiry < (now()+interval '30 days')::date and license_expiry >= now()::date),
      'banned',(select count(*) from leads where banned is true),
      'matching_blocked',(select count(*) from leads where matching_blocked is true)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from supplier_kpis k), '{}'::jsonb),
      'open_risk', (select count(*) from agent_actions where kind='supplier_risk' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',supplier_id,'company_name',company_name,'health',health,
            'quality',quality,'compliance',compliance,'response',response,'retention',retention,
            'risk_tier',risk_tier,'dormant',dormant) a
          from supplier_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from supplier_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(lifecycle_stage,''),'directory') stg, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 8) k),'[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) s),'[]'::jsonb),
    'emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) e),'[]'::jsonb),
    'total', v_total, 'limit', v_limit, 'offset', v_offset, 'rows', v_rows
  );
end;
$function$;
SELECT (fn_ws_suppliers('{}'::jsonb)->'kpis'->>'total') AS shown_total;
