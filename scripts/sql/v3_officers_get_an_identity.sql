-- Six executive officers run every day under names the org chart does not know.
--
-- exec_agents runs `strategy`, `operations`, `procurement_quality`, `data_science`,
-- `product_ux` and `competitive`. None of the six exists in org_agents, and none had a row in
-- org_agent_alias — so they file reports and decisions under identities no role covers, and
-- the V3 crosswalk (which reads org_agents) could not see them at all. This is the same shape
-- as every other alias defect here: work addressed to an identity nobody models.
--
-- Each is mapped to the runtime agent that actually holds that role, by charter:
insert into org_agent_alias (alias, agent_key, reason) values
  ('strategy',            'strategy_director', 'exec_agents officer: continuous improvement of the business'),   -- exec: continuous improvement of the business
  ('operations',          'ops_director',      'exec_agents officer: process, coordination, throughput'),        -- knowledge: process, coordination, throughput
  ('procurement_quality', 'quote_evaluation',  'exec_agents officer: quote quality and comparability'),    -- procurement: quote quality and comparability
  ('data_science',        'forecast_analyst',  'exec_agents officer: trends, demand, seasonality'),    -- intelligence: trends, demand, seasonality
  ('product_ux',          'cpo',               'exec_agents officer: voice of the customer, product friction'),                 -- exec: voice of the customer, product friction
  ('competitive',         'market_analyst',    'exec_agents officer: competitive position')       -- intelligence: competitive position
on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;
