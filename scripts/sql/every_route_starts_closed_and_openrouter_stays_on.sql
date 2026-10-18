-- EVERY ROUTE STARTS CLOSED AND OPENROUTER STAYS ON -- it_engineer, 7 Oct 2026.
--
-- Founder ruling 7 Oct 2026 (ledger 1175): "from now on keep open router always on". The hold was lifted on
-- production at 2026-10-07 03:25:36 UTC. Earlier files in MANIFEST.txt registered new models by COPYING the fleet's
-- open_until (the hold) and hold_01 set every route 100 years out; they are history and are not edited. This file
-- supersedes their behaviour: every model a policy or the registry can route to has a breaker row, CLOSED
-- (open_until null), so its failure breaker can trip on real errors and nothing is held by default.
-- Data only, idempotent. No file after this one in MANIFEST order may write a founder hold:
-- prevented by scripts/checks/a_tripped_breaker_on_one_route_never_holds_the_whole_estate.test.mjs.
insert into public.llm_route_health (model_id, consecutive_failures, failure_threshold, cooldown_seconds, open_until, opened_reason)
select m, 0, 3, 300, null, null from (
  select model_id m from public.model_registry where active
  union select model_primary from public.model_policy where active and model_primary is not null
  union select model_fallback from public.model_policy where active and model_fallback is not null
) z where m not in ('none', 'none/deterministic')
on conflict (model_id) do nothing;

select case
  when exists (select 1 from public.llm_route_health where open_until > now() + interval '1 year'
                  or (opened_reason like 'HELD BY THE FOUNDER%' and open_until > now()))
    then 'PROBE FAILED: a route is founder-held - ledger 1175 keeps OpenRouter on'
  when exists (select 1 from public.model_registry r where r.active
                 and not exists (select 1 from public.llm_route_health h where h.model_id = r.model_id))
    then 'PROBE FAILED: an active model has no breaker row'
  else 'PROBE OK: every route has a closed breaker row and none is founder-held' end as verdict;
