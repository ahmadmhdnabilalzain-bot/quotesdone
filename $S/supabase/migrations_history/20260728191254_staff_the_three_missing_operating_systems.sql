-- Knowledge, Intelligence and Evolution had no team. Knowledge OS had a department name but
-- an Operations team inside it. Staff all three properly.

insert into org_departments (dept_key, name, charter, north_star, lead_agent, brain_agent, active, sort)
select * from (values
 ('knowledge_eng','Knowledge Engineering',
  'Owns everything the company knows: the knowledge base, retrieval, embeddings, validation, decay and the auto-learning exam loop.',
  'Every employee answers from current, cited, validated knowledge','knowledge_director','knowledge_director',true,11),
 ('intelligence','Intelligence',
  'Owns analytics, KPI instrumentation, forecasting, and market, competitive, supplier and customer intelligence.',
  'Every decision is made against a number somebody trusts','intel_director','intel_director',true,12),
 ('evolution','Evolution',
  'Owns innovation intake, the improvement loop, the outcome ledger, performance and cost optimisation, and organisational design.',
  'The company is measurably better than it was last week','cpo','cpo',true,13)
) v(dept_key,name,charter,north_star,lead_agent,brain_agent,active,sort)
where not exists (select 1 from org_departments d where d.dept_key = v.dept_key);

insert into org_agents (agent_key, department, role, kind, active, title, manager_key, seniority, responsibilities, max_open_tasks, hired_at, available)
select v.agent_key, v.department, v.role, 'agent', true, v.title, v.manager_key, v.seniority, v.responsibilities, v.max_open_tasks::int, now(), true
from (values
 -- Knowledge OS
 ('knowledge_director','knowledge_eng','director','Knowledge Director','ceo','director',
  'Owns the knowledge base end to end: coverage across all 86 categories, the 14 required modules per expert, source citation, validation status, confidence decay and quarantine. Answerable for every employee answering from current, cited knowledge.','10'),
 ('kb_engineer','knowledge_eng','specialist','Knowledge Engineer','knowledge_director','senior',
  'Runs ingestion, chunking, embeddings and retrieval quality. Owns kb_chunks, kb_query precision and recall, and the embedding refresh cycle.','10'),
 ('knowledge_validator','knowledge_eng','specialist','Knowledge Validator','knowledge_director','senior',
  'Runs the auto-learning exam loop, grades agent answers against independent sources, writes corrections only on model convergence, and quarantines knowledge that falls below the confidence floor.','10'),
 -- Intelligence OS
 ('intel_director','intelligence','director','Intelligence Director','ceo','director',
  'Owns what the company measures and whether those measures still explain outcomes. Answerable for KPI instrumentation, forecasting accuracy, and market, competitive, supplier and customer intelligence reaching the executives who need it.','10'),
 ('forecast_analyst','intelligence','specialist','Forecasting Analyst','intel_director','senior',
  'Forecasts revenue, cash flow, supplier growth, customer growth, AI cost and infrastructure cost. Tracks forecast error and revises the model when it drifts.','10'),
 ('market_analyst','intelligence','specialist','Market Intelligence Analyst','intel_director','senior',
  'Tracks the UAE market: new and closing suppliers, tenders, permits, construction trends, regulation and competitor pricing. Feeds market_intel and the competitive position.','10'),
 ('supplier_analyst','intelligence','specialist','Supplier & Customer Analyst','intel_director','senior',
  'Owns supplier reliability, risk, response, price and quality scores, and customer lifetime value, buying behaviour and churn risk.','10'),
 -- Evolution OS (cpo already exists and leads it)
 ('innovation_mgr','evolution','manager','Innovation Manager','cpo','lead',
  'Runs innovation intake: captures ideas from any employee, scores them on value, effort and confidence, builds the business case, and tracks approved ideas to a measured outcome.','10'),
 ('optimisation_eng','evolution','specialist','Optimisation Engineer','cpo','senior',
  'Owns cost per decision, cost per RFQ, model tier routing, response caching and automation coverage. Finds the cheapest path that still satisfies the priority hierarchy.','10'),
 ('org_designer','evolution','specialist','Organisational Designer','cpo','senior',
  'Asks monthly whether the org shape still fits the work: which teams need people, which should split or merge, which workflows are dead, and which capabilities are missing.','10')
) v(agent_key,department,role,title,manager_key,seniority,responsibilities,max_open_tasks)
where not exists (select 1 from org_agents a where a.agent_key = v.agent_key);

insert into os_department (os_key, dept_key) values
('knowledge','knowledge_eng'), ('intelligence','intelligence'), ('evolution','evolution')
on conflict do nothing;

insert into department_budget (dept_key, monthly_aed, spent_aed, period_label, degrade_at_pct, halt_at_pct)
select v.dept_key, v.monthly_aed::numeric, 0, to_char(current_date,'YYYY-MM'), 70, 95
from (values ('knowledge_eng','800'),('intelligence','600'),('evolution','400')) v(dept_key,monthly_aed)
where not exists (select 1 from department_budget b where b.dept_key = v.dept_key);