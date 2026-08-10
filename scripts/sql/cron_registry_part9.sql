-- Register this session's nine new cron jobs in the manual.
--
-- s38-manual-always-current went MET -> NOT MET on the closing scorer run: "9 active cron job(s)
-- are undocumented". All nine are mine, added today. The check measures drift in both directions
-- and it caught me in one of them within the hour, which is the check working exactly as
-- intended — automation that runs and is not written down.
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('kb_route_tests_hourly',         'Operational route tests',        'Knowledge',
   'Runs the 344 route tests the 86-CATEGORIES pack ships against fn_kb_route_decide and raises an incident when a case that used to pass stops passing. They had run once, on 2 Aug.'),
  ('ops_scenarios_hourly',          'Operations scenario sweep',      'Operations',
   'Runs the Company Operations pack''s 282 scenarios through fn_ops_run_scenarios and writes the verdict back to ops_kb_stage.scenarios.last_run, which had said 2 Aug for ever. Raises when a scenario that was RUNNABLE becomes BLOCKED.'),
  ('kb_corpus_integrity_daily',     'Knowledge corpus integrity',     'Knowledge',
   'Asserts kb_stage.records = sum(file_hashes.rows_seen) = kb_chunks(qd_kb_pack), and that every deployed chunk has a full-text vector. This is the standing guard against a corpus that is imported but not reachable by any customer path.'),
  ('model_catalog_drift_daily',     'Model catalogue drift',          'AI',
   'Reports which of the routing pack''s 14 recommended models production does not serve, and any ACTIVE model policy pointing at a model that is not in model_registry.'),
  ('tool_readiness_daily',          'Tool and connector readiness',   'Operations',
   'Reads ai_tool_matrix and raises when a tool marked required before launch is not connected. Conditional requirements (Apify, CloudConvert, Dropbox) are counted separately and do not raise.'),
  ('action_invoke_dispatch_5min',   'Action invoker — dispatch',      'Operations',
   'Posts queued action_execution rows to their edge-function executor over HTTP. Dispatches only low-risk, advisory-safe, reversible actions; refuses founder-authority actions and anything irreversible with no declared compensation.'),
  ('action_invoke_collect_5min',    'Action invoker — collect',       'Operations',
   'Reads the pg_net response for each dispatched action, requires a 200 AND a body that does not say ok:false, retries to max_attempts, then dead-letters. Closes the org_task the invocation was carrying out.'),
  ('org_task_execute_sweep_hourly', 'Task backlog to executor',       'Operations',
   'Queues open org_tasks whose action_class has an edge executor into the invoker, five a run. 84 of the 439 open tasks qualify and none of them could run before the invoker existed.'),
  ('kb_embed_backfill_boost',       'Knowledge embedding boost',      'Knowledge',
   'Six extra kb_embed invocations a minute at the safe batch of 5, alongside the original once-a-minute job. Embedding uses the free in-region gte-small, so this is throughput, not spend. Delete this job when kb_chunks has no unembedded rows left.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
