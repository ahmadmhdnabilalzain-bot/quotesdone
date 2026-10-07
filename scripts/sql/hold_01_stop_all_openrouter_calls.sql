-- HOLD EVERY OPENROUTER CALL — founder instruction, 15 Aug 2026: "no more calls on open router.
-- hold them all."
--
-- WHY THIS LEVER. ai_gateway already fails CLOSED when every model route for a task class is
-- open-circuit: it returns 503 with `used_llm: false`, `cost_usd: 0` and makes no HTTP call at all.
-- That is a data-only switch, reversible with one UPDATE, and it holds every caller at once —
-- 186 cron jobs, every edge function, every agent — without unscheduling anything or editing code.
-- Unscheduling 186 crons would also stop the free deterministic work they do; this stops only the
-- part that spends.
--
-- THE HOLE THIS CLOSES. fn_llm_preflight answers allowed=true for a route it does not know, and
-- the gateway's own comment says so: "an unresolved id is NOT silently blocked here". Measured on
-- production before this file: model_policy names 8 routes and llm_route_health held only 3, so
-- blocking the rows that exist would have left 5 routes wide open and the hold would have leaked.
-- Every route named by model_policy is inserted first, then every row is opened.
--
-- WHAT STILL RUNS: everything deterministic. SQL routines, matching, eligibility, workflows,
-- checks, cron jobs — none of them touch OpenRouter. Only the model calls stop.
--
-- TO RELEASE THE HOLD:
--   update public.llm_route_health set open_until = null, opened_reason = null, opened_class = null;
--
-- Note fn_record_llm_attempt clears open_until on a SUCCESSFUL call, so the hold cannot be undone
-- by accident: no call succeeds while it is in place, because none is made.

begin;

-- 1. every route model_policy can select must exist here, or preflight waves it through.
insert into public.llm_route_health (model_id)
select m from (
  select model_primary  as m from public.model_policy where model_primary  is not null
  union
  select model_fallback as m from public.model_policy where model_fallback is not null
) r
on conflict (model_id) do nothing;

-- 2. open every circuit, far enough out that it cannot lapse on its own.
update public.llm_route_health
   set open_until    = now() + interval '100 years',
       opened_reason = 'HELD BY THE FOUNDER 15 Aug 2026: no OpenRouter calls until he releases it. '
                       || 'Release with: update llm_route_health set open_until = null;',
       -- opened_class stays NULL on purpose. It carries a foreign key to llm_failure_class, whose
       -- rows drive fn_classify_llm_failure and fn_llm_retry_allowed. Inventing a 'founder_hold'
       -- class to sit in this column would put a hold into the retry/breaker vocabulary and change
       -- how real failures are classified. This is not a failure; it is a deliberate stop.
       opened_class  = null,
       updated_at    = now();

commit;
