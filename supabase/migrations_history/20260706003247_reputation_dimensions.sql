-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706003247   name: reputation_dimensions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #14 Multi-dimensional reputation: per-review dimension scores (1-5, nullable)
alter table reviews add column if not exists r_communication smallint check (r_communication between 1 and 5);
alter table reviews add column if not exists r_quality       smallint check (r_quality between 1 and 5);
alter table reviews add column if not exists r_punctuality   smallint check (r_punctuality between 1 and 5);
alter table reviews add column if not exists r_documentation smallint check (r_documentation between 1 and 5);
alter table reviews add column if not exists r_after_sales   smallint check (r_after_sales between 1 and 5);
alter table reviews add column if not exists r_compliance    smallint check (r_compliance between 1 and 5);

-- Aggregate reputation per supplier: per-dimension averages + disputes + responsiveness + composite index
create or replace view supplier_reputation as
with disp as (
  select supplier_id,
         count(*) filter (where refund_status is not null and refund_status <> 'none') as disputes,
         count(*) as reveals
  from transactions group by supplier_id
)
select l.id as supplier_id, l.company_name,
  count(r.id)                                   as review_count,
  round(avg(r.rating)::numeric,2)               as overall,
  round(avg(r.r_communication)::numeric,2)      as communication,
  round(avg(r.r_quality)::numeric,2)            as quality,
  round(avg(r.r_punctuality)::numeric,2)        as punctuality,
  round(avg(r.r_documentation)::numeric,2)      as documentation,
  round(avg(r.r_after_sales)::numeric,2)        as after_sales,
  round(avg(r.r_compliance)::numeric,2)         as compliance,
  coalesce(sp.quote_rate,0)                     as responsiveness,   -- % of matches quoted (proxy)
  coalesce(d.disputes,0)                        as disputes,
  case when coalesce(d.reveals,0)>0 then round(100.0*d.disputes/d.reveals,1) else 0 end as dispute_rate_pct,
  -- composite 0-100 index: quality-weighted rating, responsiveness, penalized by disputes
  round(
    least(100, greatest(0,
      coalesce(avg(r.rating),0)*16                                  -- up to 80 from avg rating (5*16)
      + coalesce(sp.quote_rate,0)*0.2                               -- up to 20 from responsiveness
      - case when coalesce(d.reveals,0)>0 then 100.0*d.disputes/d.reveals*0.3 else 0 end
    ))
  ,1) as reputation_index
from leads l
left join reviews r on r.supplier_id = l.id
left join supplier_perf sp on sp.supplier_id = l.id
left join disp d on d.supplier_id = l.id
group by l.id, l.company_name, sp.quote_rate, d.disputes, d.reveals;

revoke all on supplier_reputation from anon, authenticated;
