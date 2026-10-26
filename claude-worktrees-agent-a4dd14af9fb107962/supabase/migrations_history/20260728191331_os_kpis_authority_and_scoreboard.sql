-- Every new employee gets measurable KPIs and real authority limits, same standard as the
-- other 56. No decorative headcount.
insert into employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active)
select v.agent_key, v.kpi, v.metric, v.target_value::numeric, v.unit, v.cadence, v.serves_goal, v.measure_sql, true
from (values
 ('knowledge_director','Knowledge validated','Knowledge items carrying a validation status other than unvalidated','80','percent','weekly','customer_satisfaction',
  $q$select round(100.0*count(*) filter (where validation_status not in ('unvalidated','unreviewed'))/nullif(count(*),0),2) from agent_knowledge$q$),
 ('knowledge_director','Knowledge quarantined','Share of knowledge below the confidence floor','5','percent_max','weekly','customer_satisfaction',
  $q$select round(100.0*count(*) filter (where validation_status='quarantined')/nullif(count(*),0),2) from agent_knowledge$q$),
 ('kb_engineer','Retrieval corpus freshness','Knowledge chunks refreshed in the last 30 days','60','percent','weekly','customer_satisfaction',
  $q$select round(100.0*count(*) filter (where created_at > now()-interval '30 days')/nullif(count(*),0),2) from kb_chunks$q$),
 ('knowledge_validator','Exam coverage','Employees examined in the last 30 days','80','percent','monthly','customer_satisfaction',
  $q$select round(100.0*count(distinct agent)/nullif((select count(*) from org_agents where active),0),2) from canon_eval_runs where run_at > now()-interval '30 days'$q$),
 ('intel_director','KPI instrumentation','Active KPIs that can actually be measured','100','percent','weekly','revenue_annual',
  $q$select round(100.0*count(*) filter (where measure_sql is not null)/nullif(count(*),0),2) from employee_kpi where active$q$),
 ('intel_director','Goal periods tracked','Goal periods carrying a live actual value','80','percent','weekly','revenue_annual',
  $q$select round(100.0*count(*) filter (where actual_value is not null)/nullif(count(*),0),2) from goal_period$q$),
 ('forecast_analyst','Forecasts produced','Forecast scenarios refreshed in the last 30 days','4','forecasts','monthly','revenue_annual',
  $q$select count(*)::numeric from simulations where created_at > now()-interval '30 days'$q$),
 ('market_analyst','Market signals captured','Market intelligence items logged in the last 30 days','20','signals','monthly','revenue_annual',
  $q$select count(*)::numeric from market_intel where created_at > now()-interval '30 days'$q$),
 ('supplier_analyst','Supplier scoring coverage','Suppliers carrying a reliability score','95','percent','weekly','supplier_coverage',
  $q$select round(100.0*(select count(*) from supplier_score where reliability is not null)/nullif((select count(*) from leads),0),2)$q$),
 ('innovation_mgr','Ideas captured','Ideas logged in the last 30 days','10','ideas','monthly','revenue_annual',
  $q$select count(*)::numeric from idea where created_at > now()-interval '30 days'$q$),
 ('optimisation_eng','AI cost efficiency','Calls a cheaper model could have served','10','percent_max','weekly','revenue_annual',
  $q$select round(100.0*count(*) filter (where could_be_cheaper)/nullif(count(*),0),2) from ai_cost_log where occurred_at > now()-interval '30 days'$q$),
 ('optimisation_eng','Response cache adoption','LLM calls served from cache','20','percent','weekly','revenue_annual',
  $q$select round(100.0*count(*) filter (where cached)/nullif(count(*),0),2) from ai_cost_log where occurred_at > now()-interval '30 days'$q$),
 ('org_designer','Employees with an improvement plan','Employees carrying a current improvement plan','80','percent','monthly','revenue_annual',
  $q$select round(100.0*count(*) filter (where improvement_plan is not null)/nullif(count(*),0),2) from org_agents where active$q$)
) v(agent_key,kpi,metric,target_value,unit,cadence,serves_goal,measure_sql)
where not exists (select 1 from employee_kpi e where e.agent_key = v.agent_key and e.kpi = v.kpi);

insert into employee_authority (agent_key, action_class, max_tier, threshold_aed, note)
select v.agent_key, v.action_class, v.max_tier, 0::numeric, v.note
from (values
 ('knowledge_director','knowledge_fill','autonomous','May commission knowledge without approval'),
 ('knowledge_director','knowledge_acquire','autonomous','May pull from approved external sources'),
 ('kb_engineer','knowledge_fill','autonomous','Owns ingestion and embeddings'),
 ('knowledge_validator','capability_exam','autonomous','Runs the exam loop'),
 ('knowledge_validator','knowledge_fill_gap','gated','Writes corrections only on model convergence'),
 ('intel_director','recommend','autonomous','May change what the company measures'),
 ('intel_director','health_report','autonomous','Owns instrumentation reporting'),
 ('forecast_analyst','forecast','autonomous','Owns forecasting'),
 ('market_analyst','knowledge_acquire','autonomous','Owns market signal capture'),
 ('supplier_analyst','capability_review','autonomous','Owns supplier and customer scoring'),
 ('innovation_mgr','recommend','autonomous','May file ideas and business cases'),
 ('optimisation_eng','recommend','autonomous','May propose model and cost changes'),
 ('optimisation_eng','code_selfheal','gated','Cost changes touching production need review'),
 ('org_designer','role_define','gated','Structural change is proposed, never self-applied')
) v(agent_key,action_class,max_tier,note)
where not exists (select 1 from employee_authority e where e.agent_key = v.agent_key and e.action_class = v.action_class);

-- inherit the shared company knowledge layer
insert into employee_knowledge (agent_key, domain_key, depth, layer_no)
select a.agent_key, s.domain_key, s.depth, s.layer_no
from (values ('knowledge_director'),('kb_engineer'),('knowledge_validator'),('intel_director'),
             ('forecast_analyst'),('market_analyst'),('supplier_analyst'),('innovation_mgr'),
             ('optimisation_eng'),('org_designer')) a(agent_key)
cross join (select distinct domain_key, depth, layer_no from employee_knowledge where agent_key='strategy_director') s
where not exists (select 1 from employee_knowledge ek where ek.agent_key = a.agent_key);

-- OS-level scoreboard: departments roll up into their operating system
create or replace view public.v_os_scoreboard as
select o.num, o.os_key, o.name, o.owner_agent,
       count(distinct od.dept_key)                                            as departments,
       count(distinct a.agent_key)                                            as employees,
       count(distinct t.id) filter (where t.status <> 'done')                 as open_tasks,
       coalesce(sum(distinct b.monthly_aed), 0)                               as budget_aed,
       coalesce(sum(distinct b.spent_aed), 0)                                 as spent_aed,
       count(distinct k.id) filter (where k.active)                           as kpis,
       count(distinct k.id) filter (where k.active and k.measure_sql is null)  as kpis_unmeasurable
from operating_system o
left join os_department od on od.os_key = o.os_key
left join org_agents   a  on a.department = od.dept_key and a.active
left join org_tasks    t  on t.dept_key   = od.dept_key
left join department_budget b on b.dept_key = od.dept_key
left join employee_kpi k  on k.agent_key   = a.agent_key
where o.active
group by o.num, o.os_key, o.name, o.owner_agent
order by o.num;