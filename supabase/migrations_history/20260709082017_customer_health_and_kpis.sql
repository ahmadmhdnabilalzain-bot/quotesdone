-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709082017   name: customer_health_and_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.customer_health as
with inq as (
  select i.id, i.customer_id, i.status, i.pipeline_stage, i.created_at, i.completed_at, i.outcome, i.stage_changed_at,
    (select min(q.created_at) from quotes q where q.inquiry_id=i.id) as first_quote_at,
    (select count(*) from quotes q where q.inquiry_id=i.id) as n_quotes
  from inquiries i
),
inq2 as (
  select *,
    extract(epoch from (first_quote_at - created_at))/3600.0 as resp_hrs,
    case
      when status='revealed' and completed_at is null and created_at < now()-interval '30 days' then true
      when status='quoted' and created_at < now()-interval '7 days' then true
      when coalesce(pipeline_stage,'')='qualifying' and n_quotes=0 and created_at < now()-interval '2 days' then true
      else false end as stalled,
    (completed_at is not null or outcome='won') as completed,
    (status='revealed' or completed_at is not null or outcome='won') as progressed
  from inq
),
cust as (
  select c.id as customer_id, c.full_name, c.email, coalesce(c.banned,false) as banned, coalesce(c.chat_strikes,0) as strikes,
    (select count(*) from inq2 x where x.customer_id=c.id) as total_inq,
    (select count(*) from inq2 x where x.customer_id=c.id and x.status not in ('cancelled') and coalesce(x.pipeline_stage,'')<>'lost') as active_inq,
    (select count(*) from inq2 x where x.customer_id=c.id and x.progressed) as progressed_inq,
    (select count(*) from inq2 x where x.customer_id=c.id and x.completed) as completed_inq,
    (select count(*) from inq2 x where x.customer_id=c.id and x.stalled) as stalled_inq,
    (select max(greatest(x.created_at, coalesce(x.stage_changed_at,x.created_at))) from inq2 x where x.customer_id=c.id) as last_activity,
    (select round(avg(x.resp_hrs)::numeric,1) from inq2 x where x.customer_id=c.id and x.resp_hrs is not null) as avg_resp_hrs,
    (select round(avg(r.rating)::numeric,2) from reviews r where r.customer_id=c.id) as avg_review,
    (select count(*) from reviews r where r.customer_id=c.id and r.rating<=2) as bad_reviews,
    (select count(*) from transactions t where t.customer_id=c.id and (t.refund_status is not null or t.refund_requested_at is not null)) as disputes
  from customers c
),
scored as (
  select cust.*,
    (last_activity is not null and last_activity < now()-interval '45 days') as dormant,
    round(least(100,
      (case when last_activity >= now()-interval '30 days' then 60 when last_activity >= now()-interval '60 days' then 40 when last_activity >= now()-interval '120 days' then 20 else 5 end)
      + least(total_inq,5)/5.0*40 ),1) as engagement,
    round(greatest(0, least(100,
      (case when avg_review is not null then avg_review/5.0*100 else 70 end)
      - (case when disputes>0 then 30 else 0 end) - bad_reviews*15 - least(strikes,3)*10 )),1) as satisfaction,
    round((case when active_inq>0 then progressed_inq::numeric/active_inq*100 when total_inq=0 then 50 else 20 end),1) as progress,
    round(greatest(0,
      (case when avg_resp_hrs is null then 60 when avg_resp_hrs<24 then 100 when avg_resp_hrs<72 then 70 when avg_resp_hrs<168 then 40 else 20 end)
      - (case when disputes>0 then 40 else 0 end) ),1) as service
  from cust
)
select customer_id, full_name, email, total_inq, active_inq, progressed_inq, completed_inq, stalled_inq,
  avg_resp_hrs, avg_review, bad_reviews, disputes, dormant, strikes, banned, last_activity,
  engagement, satisfaction, progress, service,
  round(engagement*0.25 + satisfaction*0.30 + progress*0.25 + service*0.20,1) as health,
  case
    when banned or disputes>0 or bad_reviews>0 or (total_inq>0 and active_inq=0)
      or round(engagement*0.25+satisfaction*0.30+progress*0.25+service*0.20,1) < 40 then 'high'
    when stalled_inq>0 or strikes>0 or dormant
      or round(engagement*0.25+satisfaction*0.30+progress*0.25+service*0.20,1) < 65 then 'medium'
    else 'low' end as risk_tier
from scored;

create or replace view public.customer_kpis as
select count(*) as customers,
  round(avg(health),1) as avg_health,
  round(avg(satisfaction),1) as avg_satisfaction,
  round(avg(avg_resp_hrs) filter (where avg_resp_hrs is not null),1) as avg_response_hrs,
  round(100.0*count(*) filter (where progress>=60)/nullif(count(*),0),1) as pct_progressing,
  count(*) filter (where disputes>0) as open_disputes,
  count(*) filter (where stalled_inq>0) as with_stalled,
  count(*) filter (where dormant) as dormant_count,
  count(*) filter (where risk_tier='high') as risk_high,
  count(*) filter (where risk_tier='medium') as risk_medium,
  count(*) filter (where risk_tier='low') as risk_low
from public.customer_health;

create table if not exists public.customer_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  created_at timestamptz not null default now()
);
create unique index if not exists customer_kpi_snap_day on public.customer_kpi_snapshots(snapshot_date);
revoke all on public.customer_health, public.customer_kpis, public.customer_kpi_snapshots from anon, authenticated;
