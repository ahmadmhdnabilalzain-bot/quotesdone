-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709080626   name: supplier_health_and_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Per-supplier health: quality / compliance / response / retention -> overall + risk tier.
create or replace view public.supplier_health as
with s as (
  select l.id as supplier_id, l.company_name,
         l.banned, l.matching_blocked, coalesce(l.chat_strikes,0) as strikes,
         l.approval_status, l.claimed,
         l.license_expiry, l.license_doc_path, l.insurance_expiry, l.insurance_doc_path,
         l.egr_doc_path, l.trn, l.iso_expiry, l.manufacturer_auth_expiry,
         l.registration_expires_at, l.portal_updated_at,
         coalesce(l.rv_response_rate, 0)::numeric as rv_rate,
         (l.rv_responded is not null or l.rv_reveals is not null) as has_rv,
         p.perf_score, p.rating, p.quoted, p.quote_rate,
         (select max(q.created_at) from quotes q where q.supplier_id = l.id) as last_quote_at,
         (select round(avg( (coalesce(r.r_quality,r.rating)+coalesce(r.r_documentation,r.rating)+coalesce(r.r_compliance,r.rating))/3.0 ),2)
            from reviews r where r.supplier_id = l.id) as review_quality
  from leads l
  left join supplier_perf p on p.supplier_id = l.id
  where l.claimed = true and coalesce(l.approval_status,'') = 'approved'
),
scored as (
  select s.*,
    -- QUALITY 0-100: prefer perf_score, blend review quality, floor on rating
    round(greatest(
      coalesce(s.perf_score,0)*100,
      coalesce(s.review_quality,0)/5.0*100,
      coalesce(s.rating,0)/5.0*100
    ),1) as quality,
    -- COMPLIANCE 0-100: 25 pts each for licence, insurance, est-card, TRN present & not expired; minus strikes
    round(greatest(0,(
       (case when s.license_doc_path is not null and (s.license_expiry is null or s.license_expiry >= current_date) then 25 else 0 end)
     + (case when s.insurance_doc_path is not null and (s.insurance_expiry is null or s.insurance_expiry >= current_date) then 25 else 0 end)
     + (case when s.egr_doc_path is not null then 25 else 0 end)
     + (case when s.trn is not null then 25 else 0 end)
     - least(s.strikes,3)*8
     - (case when s.iso_expiry is not null and s.iso_expiry < current_date then 10 else 0 end)
     - (case when s.manufacturer_auth_expiry is not null and s.manufacturer_auth_expiry < current_date then 10 else 0 end)
    )),1) as compliance,
    -- RESPONSE 0-100: reveal response rate if present else quote_rate
    round((case when s.has_rv then s.rv_rate else coalesce(s.quote_rate,0) end)*100,1) as response,
    -- RETENTION 0-100: activity recency + registration validity
    round((
      (case
         when greatest(coalesce(s.last_quote_at, s.portal_updated_at), s.portal_updated_at) >= now()-interval '30 days' then 60
         when greatest(coalesce(s.last_quote_at, s.portal_updated_at), s.portal_updated_at) >= now()-interval '60 days' then 40
         when greatest(coalesce(s.last_quote_at, s.portal_updated_at), s.portal_updated_at) >= now()-interval '120 days' then 20
         else 5 end)
     + (case when s.registration_expires_at is null or s.registration_expires_at >= now() then 40 else 0 end)
    ),1) as retention
  from s
)
select supplier_id, company_name, quality, compliance, response, retention,
  round(quality*0.30 + compliance*0.30 + response*0.20 + retention*0.20, 1) as health,
  case
    when banned or matching_blocked or strikes >= 3 or compliance < 40
      or round(quality*0.30 + compliance*0.30 + response*0.20 + retention*0.20,1) < 40 then 'high'
    when compliance < 75 or strikes > 0 or retention < 30
      or round(quality*0.30 + compliance*0.30 + response*0.20 + retention*0.20,1) < 65 then 'medium'
    else 'low' end as risk_tier,
  (last_quote_at is null and portal_updated_at < now()-interval '45 days') as dormant,
  strikes, banned, matching_blocked, last_quote_at, portal_updated_at
from scored;

-- Portfolio KPI rollup
create or replace view public.supplier_kpis as
select
  count(*) as active_suppliers,
  round(avg(quality),1) as avg_quality,
  round(avg(response),1) as avg_response_score,
  round(100.0*count(*) filter (where compliance >= 80)/nullif(count(*),0),1) as pct_compliant,
  round(100.0*count(*) filter (where not dormant)/nullif(count(*),0),1) as retention_rate,
  count(*) filter (where risk_tier='high') as risk_high,
  count(*) filter (where risk_tier='medium') as risk_medium,
  count(*) filter (where risk_tier='low') as risk_low,
  count(*) filter (where dormant) as dormant_count,
  round(avg(health),1) as avg_health
from public.supplier_health;

-- KPI trend snapshots
create table if not exists public.supplier_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  created_at timestamptz not null default now()
);
create unique index if not exists supplier_kpi_snap_day on public.supplier_kpi_snapshots(snapshot_date);

revoke all on public.supplier_health, public.supplier_kpis, public.supplier_kpi_snapshots from anon, authenticated;
