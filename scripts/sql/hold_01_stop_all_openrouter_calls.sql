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

-- 2. RETIRED 7 Oct 2026 (founder ruling, ledger 1175: "from now on keep open router always on").
--    This step used to set open_until = now() + 100 years on every route. It is removed so that a
--    re-apply of this file can never re-impose the hold; step 1 (every policy route has a row) stays.

commit;
