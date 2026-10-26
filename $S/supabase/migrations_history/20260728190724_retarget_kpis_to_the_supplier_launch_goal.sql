-- The company was measuring the wrong supplier goal. Re-target to what the founder actually
-- needs for the next 2-3 months: 10 approved suppliers in each of 86 categories.

update employee_kpi
   set kpi = 'Categories at the 10-supplier target',
       metric = 'Categories with 10+ approved suppliers',
       target_value = 86, unit = 'categories',
       measure_sql = $q$select count(*)::numeric from v_supply_gap where approved >= 10$q$
 where kpi = 'Categories with live supply';

update employee_kpi
   set target_value = 10,
       measure_sql = $q$select round(avg(approved),2) from v_supply_gap$q$
 where metric = 'Coverage across active supplier categories' and active;

insert into employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active)
select v.agent_key, v.kpi, v.metric, v.target_value::numeric, v.unit, v.cadence, v.serves_goal, v.measure_sql, true
from (values
  ('onboarding','Total approved suppliers','Suppliers that completed onboarding and were approved','860','suppliers','weekly','supplier_coverage',
   $q$select count(*)::numeric from leads where approval_status='approved'$q$),
  ('onboarding','Categories with a viable pool','Categories holding enough sendable leads to reach 10 approved at 5% conversion','86','categories','weekly','supplier_coverage',
   $q$select count(*)::numeric from v_supply_gap where sendable >= sendable_needed_at_5pct$q$),
  ('onboarding','Invite to approval conversion','Share of invited suppliers that reach approved','5','percent','weekly','supplier_coverage',
   $q$select round(100.0*count(*) filter (where approval_status='approved')/nullif(count(*) filter (where invite_status is not null),0),2) from leads$q$),
  ('onboarding','Lead pool growth','New sendable leads added in the last 30 days','2000','leads','monthly','supplier_coverage',
   $q$select count(*)::numeric from leads where created_at > now()-interval '30 days' and email is not null and email <> ''$q$),
  ('knowledge','Leads carrying a category','Share of sendable leads mapped to a supplier category','95','percent','weekly','supplier_coverage',
   $q$select round(100.0*count(*) filter (where exists(select 1 from lead_category lc where lc.lead_id=l.id))/nullif(count(*),0),2) from leads l where l.email is not null and l.email<>'' and coalesce(l.banned,false)=false$q$)
) v(agent_key,kpi,metric,target_value,unit,cadence,serves_goal,measure_sql)
where not exists (select 1 from employee_kpi e where e.kpi = v.kpi);

-- make the company goal match the founder's stated target
insert into company_goals (key, goal, metric, target_value, unit, period, owner_dept, measure_sql, active, category, horizon, direction)
select 'supplier_coverage_10x86','10 approved suppliers in every one of the 86 categories',
       'Categories at the 10-supplier target', 86, 'categories','quarter','procurement',
       $q$select count(*)::numeric from v_supply_gap where approved >= 10$q$, true,'growth','quarter','up'
where not exists (select 1 from company_goals where key='supplier_coverage_10x86');