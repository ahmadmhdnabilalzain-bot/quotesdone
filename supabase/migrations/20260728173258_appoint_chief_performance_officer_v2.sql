insert into org_agents (agent_key, department, role, kind, active, title, manager_key, seniority,
                        responsibilities, max_open_tasks, hired_at, available)
select 'cpo','exec','executive','agent',true,'Chief Performance Officer','ceo','chief',
       'Owns company, department and employee performance end to end. Reviews the KPI scoreboard weekly, '
       ||'diagnoses every missed target, opens improvement initiatives with a named metric and a baseline, '
       ||'grades them against that claim through the outcome ledger, promotes what worked and reverses what '
       ||'did not. Owns AI efficiency, automation coverage, cost per decision, process optimisation and '
       ||'benchmarking. Answers one question: is this company measurably better than last week?',
       12, now(), true
where not exists (select 1 from org_agents where agent_key='cpo');

insert into employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active)
select v.agent_key, v.kpi, v.metric, v.target_value::numeric, v.unit, v.cadence, v.serves_goal, v.measure_sql, true
from (values
  ('cpo','Company KPI attainment','Share of active KPIs meeting target','70','percent','weekly','revenue_annual',
   $q$select round(100.0*count(*) filter (where verdict in ('MET','NEAR'))/nullif(count(*) filter (where verdict<>'NO DATA'),0),2) from fn_kpi_scoreboard()$q$),
  ('cpo','KPI measurability','Share of active KPIs that can be measured at all','100','percent','weekly','revenue_annual',
   $q$select round(100.0*count(*) filter (where measure_sql is not null)/nullif(count(*),0),2) from employee_kpi where active$q$),
  ('cpo','Improvements graded','Improvement initiatives closed with a verdict, not left open','80','percent','monthly','revenue_annual',
   $q$select round(100.0*count(*) filter (where verdict<>'pending')/nullif(count(*),0),2) from outcome_record$q$),
  ('cpo','Improvements that worked','Graded improvements that moved their metric the right way','60','percent','monthly','revenue_annual',
   $q$select round(100.0*count(*) filter (where verdict='improved')/nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),2) from outcome_record$q$),
  ('cpo','Over-specified AI calls','Calls a cheaper model could have served','10','percent_max','weekly','revenue_annual',
   $q$select round(100.0*count(*) filter (where could_be_cheaper)/nullif(count(*),0),2) from ai_cost_log where occurred_at>now()-interval '30 days'$q$),
  ('cpo','Daily operating rhythm','Stages of the daily loop producing evidence','100','percent','weekly','revenue_annual',
   $q$select round(100.0*count(*) filter (where ok)/nullif(count(*),0),2) from day_cadence where business_day>current_date-7$q$)
) v(agent_key,kpi,metric,target_value,unit,cadence,serves_goal,measure_sql)
where not exists (select 1 from employee_kpi where agent_key='cpo');

insert into employee_authority (agent_key, action_class, max_tier, threshold_aed, note)
select v.agent_key, v.action_class, v.max_tier, v.threshold_aed::numeric, v.note
from (values
  ('cpo','recommend','autonomous','0','May open improvement initiatives unprompted'),
  ('cpo','coordinate','autonomous','0','May assign improvement work across departments'),
  ('cpo','exec_review','autonomous','0','Owns the weekly performance review'),
  ('cpo','qa_gate','gated','0','May hold work that fails a quality gate'),
  ('cpo','escalate_founder','advisory','0','Escalates only what exceeds executive authority')
) v(agent_key,action_class,max_tier,threshold_aed,note)
where not exists (select 1 from employee_authority where agent_key='cpo');

insert into employee_knowledge (agent_key, domain_key, depth, layer_no)
select 'cpo', domain_key, depth, layer_no
from (select distinct domain_key, depth, layer_no from employee_knowledge where agent_key='strategy_director') s
where not exists (select 1 from employee_knowledge where agent_key='cpo');

insert into skills_matrix (agent_key, skill, rating, evidence, updated_at)
select v.agent_key, v.skill, v.rating::int, v.evidence, now()
from (values
  ('cpo','KPI design and measurement','5','Owns fn_kpi_scoreboard and every measure_sql'),
  ('cpo','Root cause analysis','4','Diagnoses missed targets before proposing fixes'),
  ('cpo','Cost optimisation','4','Owns ai_cost_log, model_policy and department budgets'),
  ('cpo','Process improvement','4','Owns the outcome ledger end to end'),
  ('cpo','Benchmarking','3','Compares departments against each other and over time')
) v(agent_key,skill,rating,evidence)
where not exists (select 1 from skills_matrix where agent_key='cpo');