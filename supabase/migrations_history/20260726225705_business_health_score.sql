-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726225705   name: business_health_score
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Item 13: one company score, with drill-down into why it moved.
-- Each department scores on measurable facts already in the database, not opinion.
create or replace view public.v_department_health as
with dept_scores as (
  -- Technology: uptime and agent error rate
  select 'it'::text as dept_key, 'Technology'::text as department,
    round(( (select coalesce(100.0*count(*) filter (where ok)/nullif(count(*),0),0) from health_checks where created_at>now()-interval '24 hours')
          + (select coalesce(100.0*count(*) filter (where status='ok')/nullif(count(*),0),0) from agent_runs where started_at>now()-interval '24 hours')
          )/2) as score,
    'uptime + agent success rate, last 24h'::text as basis
  union all
  -- Operations / Knowledge: test suite pass rate
  select 'knowledge','Operations',
    (select coalesce(round(avg(pass_pct)),0) from v_test_matrix),
    'average pass rate across all test suites, 14d'
  union all
  -- Marketplace & Procurement: category coverage against the 84 target
  select 'procurement','Marketplace & Procurement',
    (select round(100.0*count(*) filter (where status='mapped')/nullif(count(*),0)) from category_agent_map),
    'supplier categories covered of 84'
  union all
  -- Marketing: brand compliance at first review
  select 'marketing','Marketing',
    (select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0)),100)
       from review_chain where stage='dept_review'),
    'share of drafts approved at first department review'
  union all
  -- Legal: compliance violations and breaches (target zero)
  select 'legal','Legal & Compliance',
    (select case when count(*)=0 then 100 else greatest(0, 100 - count(*)*20) end
       from risk_register where dept_key='legal' and status='open' and impact='high'),
    'open high-impact legal risks (target zero)'
  union all
  -- Finance: money test pass rate
  select 'finance','Finance',
    (select coalesce(round(100.0*count(*) filter (where status='ok')/nullif(count(*),0)),0)
       from agent_runs where agent='money_tests' and started_at>now()-interval '14 days'),
    'money invariant test pass rate, 14d'
  union all
  -- Executive: employees fully equipped with KPI and authority
  select 'exec','Executive Office',
    (select round(100.0*count(*) filter (where kpis>0 and authorities>0)/nullif(count(*),0))
       from v_employee_knowledge_compliance),
    'employees with both a KPI and defined authority'
  union all
  -- HR: knowledge layer binding completeness
  select 'hr','Human Resources',
    (select round(100.0*avg(layers_bound)/12) from v_employee_knowledge_compliance),
    'average employee knowledge layers bound of 12'
  union all
  -- Customer Success: no data yet, so honest zero rather than a flattering default
  select 'customer_success','Customer Success', 0,
    'no customers, inquiries or quotes exist yet - unmeasurable'
  union all
  select 'sales','Sales & Growth', 0,
    'no transactions exist yet - unmeasurable'
)
select dept_key, department, greatest(0, least(100, coalesce(score,0))) as score, basis,
       case when coalesce(score,0) >= 90 then 'healthy'
            when coalesce(score,0) >= 70 then 'watch'
            when coalesce(score,0) > 0    then 'at risk'
            else 'no data' end as status
from dept_scores;

create or replace view public.v_business_health as
select round(avg(score) filter (where status <> 'no data')) as overall_score_measurable,
       round(avg(score)) as overall_score_all_departments,
       count(*) filter (where status='healthy')  as healthy,
       count(*) filter (where status='watch')    as watch,
       count(*) filter (where status='at risk')  as at_risk,
       count(*) filter (where status='no data')  as unmeasurable,
       (select count(*) from risk_register where status='open') as open_risks,
       (select count(*) from spec_backlog where status<>'done' and priority=1) as open_p1
from v_department_health;

comment on view public.v_business_health is 'Item 13: one company health score. Departments with no data score 0 and are counted separately rather than flattering the average.';
