select agent, status, started_at from agent_runs where agent ilike '%outbox%' order by started_at desc limit 3; 
