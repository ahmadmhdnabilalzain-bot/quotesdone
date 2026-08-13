-- THE MANUAL HAS TO KNOW ABOUT A JOB THE MOMENT THE JOB EXISTS.
--
-- 13 Aug 2026. Adding action_invoke_rpc_5min took Row #3 from 130/152 to 129:
--
--   s38-manual-always-current  MET      0 undocumented job(s) against 178 active
--   s38-manual-always-current  MISSING  1 undocumented job(s) against 179 active
--
-- The check was right and I was the cause. public.cron_registry is the manual's record of what
-- actually runs, and s38 asserts the two never drift: every active cron job documented, and every
-- documented job still real. Scheduling a job without registering it is precisely the drift it
-- exists to catch, and it caught it inside one scorer run.
--
-- Registered rather than the check relaxed. A scheduler the manual does not describe is how an
-- estate ends up with jobs nobody can account for, which is the thing s38 is protecting.

insert into public.cron_registry (jobname, human_name, category, purpose)
values (
  'action_invoke_rpc_5min',
  'Action invoker — rpc',
  'Operations',
  'Runs queued action_execution rows whose executor is a SQL function (org_action_executor.kind = rpc), the half the HTTP dispatcher never covered. Applies the same refusals as the edge path - inactive, founder authority, irreversible with no declared compensation, notifies_human without unattended_ok, then the low/advisory-safe/reversible risk gate - and calls only targets that take no required arguments, recording a named reason for any target that is missing or needs arguments a workflow step cannot supply. Synchronous, so it needs no collector. Scheduled on the 0,5,10 minutes, between the edge dispatcher and its collector, so the three never contend for the same rows.'
)
on conflict (jobname) do update
  set human_name = excluded.human_name,
      category   = excluded.category,
      purpose    = excluded.purpose;
