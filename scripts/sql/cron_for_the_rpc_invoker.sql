-- THE rpc INVOKER NEEDS A CLOCK, OR IT ONLY EVER RUNS WHEN SOMEONE CALLS IT BY HAND.
--
-- fn_action_invoke_rpc is the runner the rpc half of org_action_executor never had. Without a cron
-- entry it would be one more finished capability with no entry point - the exact shape it was
-- written to fix.
--
-- Scheduled on the odd minutes between the edge dispatcher (2,7,12,...) and its collector
-- (4,9,14,...) so the three never contend for the same action_execution rows. rpc is synchronous
-- and needs no collector of its own.
--
-- p_limit 5 matches the edge dispatcher. These call SQL functions that do real work -
-- fn_org_exec_knowledge_fill triggers background generation - so the ceiling is deliberate.

select cron.schedule(
  'action_invoke_rpc_5min',
  '0,5,10,15,20,25,30,35,40,45,50,55 * * * *',
  $$select public.fn_action_invoke_rpc(5)$$
)
where not exists (select 1 from cron.job where jobname = 'action_invoke_rpc_5min');
