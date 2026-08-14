-- The V3 runtime's own health jobs. Readiness derived once and never recomputed would be a
-- number that describes the day it was written; source freshness marked once would be the
-- same. Both are cheap and both belong on a schedule rather than in a session's memory.
select cron.schedule('v3_knowledge_freshness_daily', '25 1 * * *',
  $$select public.fn_knowledge_freshness_sweep();$$)
where not exists (select 1 from cron.job where jobname = 'v3_knowledge_freshness_daily');

select cron.schedule('v3_role_readiness_daily', '30 1 * * *',
  $$select public.fn_role_readiness_recompute();$$)
where not exists (select 1 from cron.job where jobname = 'v3_role_readiness_daily');

select cron.schedule('v3_category_readiness_daily', '35 1 * * *',
  $$select public.fn_category_readiness_recompute();$$)
where not exists (select 1 from cron.job where jobname = 'v3_category_readiness_daily');

-- A retrieval row is only useful while an action might still cite it; the trace has already
-- captured what mattered.
select cron.schedule('v3_context_retrieval_prune_daily', '40 1 * * *',
  $$select public.fn_context_retrieval_prune();$$)
where not exists (select 1 from cron.job where jobname = 'v3_context_retrieval_prune_daily');
