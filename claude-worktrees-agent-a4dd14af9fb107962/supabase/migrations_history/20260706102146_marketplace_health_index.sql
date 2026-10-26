-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706102146   name: marketplace_health_index
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ MARKETPLACE HEALTH INDEX ============
-- One composite 0-100 score from available signals. Components that lack a basis
-- return null and are excluded from the average, so a pre-traction marketplace
-- isn't scored to a misleading 0.
create or replace function public.fn_health_index()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  s_acq numeric; s_supp numeric; s_rfq numeric; s_qual numeric;
  s_resp numeric; s_disp numeric; s_up numeric;
  signups_7d int; quotes_7d int; approved_suppliers int;
  inq_total int; inq_done int; avg_qual numeric; avg_resp numeric;
  blocked_30d int; msgs_30d int; up_ok int; up_tot int;
  parts numeric[]; overall numeric; band text; present int;
begin
  select count(*) into signups_7d from customers where created_at > now()-interval '7 days';
  select count(*) into quotes_7d  from quotes    where created_at > now()-interval '7 days';
  select count(*) into approved_suppliers from leads
     where coalesce(approval_status,'')='approved' or claimed=true;
  select count(*) filter (where created_at > now()-interval '90 days'),
         count(*) filter (where created_at > now()-interval '90 days'
                          and (status in ('completed','won') or completed_at is not null))
    into inq_total, inq_done from inquiries;
  select avg(nullif(quality->>'score','')::numeric) into avg_qual
    from quotes where quality is not null and created_at > now()-interval '90 days';
  select avg(nullif(rv_response_rate,0)) into avg_resp
    from leads where coalesce(rv_reveals,0) > 0;
  select count(*) filter (where coalesce(blocked,false)),
         count(*) into blocked_30d, msgs_30d
    from messages where created_at > now()-interval '30 days';
  select count(*) filter (where ok), count(*) into up_ok, up_tot
    from health_checks where created_at > now()-interval '24 hours';

  -- sub-scores (0-100), null when no basis
  s_acq  := least(100, signups_7d * 10.0);                 -- 10 signups/wk = 100
  s_supp := case when approved_suppliers=0 and quotes_7d=0 then null
                 else least(100, quotes_7d * 5.0) end;      -- 20 quotes/wk = 100
  s_rfq  := case when inq_total=0 then null else round(inq_done::numeric/inq_total*100,1) end;
  s_qual := avg_qual;                                       -- already 0-100
  s_resp := case when avg_resp is null then null
                 when avg_resp <= 1 then round(avg_resp*100,1) else round(avg_resp,1) end;
  s_disp := case when msgs_30d=0 then null
                 else greatest(0, 100 - least(100, blocked_30d*5.0)) end;
  s_up   := case when up_tot=0 then null else round(up_ok::numeric/up_tot*100,1) end;

  parts := array_remove(array[s_acq,s_supp,s_rfq,s_qual,s_resp,s_disp,s_up], null);
  present := coalesce(array_length(parts,1),0);
  overall := case when present=0 then null else round((select avg(x) from unnest(parts) x),1) end;
  band := case when overall is null then 'no data'
               when overall >= 75 then 'healthy'
               when overall >= 50 then 'watch'
               else 'attention' end;

  return jsonb_build_object(
    'index', overall,
    'band', band,
    'components_present', present,
    'note', case when present < 3 then 'insufficient data — pre-traction; index will firm up with volume' else null end,
    'components', jsonb_build_object(
       'customer_acquisition', s_acq,
       'supplier_activity', s_supp,
       'rfq_completion', s_rfq,
       'quote_quality', s_qual,
       'response_time', s_resp,
       'dispute_health', s_disp,
       'uptime', s_up,
       'revenue', null),
    'raw', jsonb_build_object(
       'signups_7d', signups_7d, 'quotes_7d', quotes_7d, 'approved_suppliers', approved_suppliers,
       'inquiries_90d', inq_total, 'completed_90d', inq_done,
       'blocked_msgs_30d', blocked_30d, 'uptime_ok', up_ok, 'uptime_checks', up_tot),
    'computed_at', now());
end $$;

create or replace view public.marketplace_health as select public.fn_health_index() as health;
revoke all on public.marketplace_health from anon, authenticated;

select public.fn_health_index() as health_now;
