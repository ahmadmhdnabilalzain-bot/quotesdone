-- Phase C correction 9 — the provider guard that the hold never had.
--
-- The founder's hold lives in llm_route_health.open_until = 2126-08-15, reason "HELD BY THE FOUNDER
-- 15 Aug 2026: no OpenRouter calls until he releases it". The audit measured what actually honours
-- it: fn_llm_preflight, called by exactly one of the twelve edge functions that read
-- app_secrets.openrouter_api_key. Meanwhile cron job 102 `ai_health_15min` (7,22,37,52 * * * *,
-- active) fetched https://openrouter.ai/api/v1/key on every run — six outbound OpenRouter requests
-- inside a 37-minute audit window.
--
-- Those calls cost nothing: /api/v1/key is free metadata, not inference, and both cost ledgers
-- correctly read AED 0.00. What failed was the stated boundary "no outbound request to OpenRouter",
-- and the fact that a caller could reach the provider without consulting the hold at all.
--
-- Cost governance is NOT removed. ai_health still reports, from the state the estate already holds.

create or replace function public.fn_os_paid_ai_allowed()
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $$
  -- Deny while ANY route is held open-circuit, or while the explicit zero-cost switch is set.
  -- Deny-by-default on an empty route table: an absent hold is not a permission.
  select not exists (select 1 from public.llm_route_health where open_until > now())
     and not exists (select 1 from public.app_secrets
                      where key = 'no_paid_ai' and lower(coalesce(value,'')) in ('1','true','yes','on'))
     and exists (select 1 from public.llm_route_health);
$$;
revoke all on function public.fn_os_paid_ai_allowed() from public;
grant execute on function public.fn_os_paid_ai_allowed() to service_role, anon, authenticated;
comment on function public.fn_os_paid_ai_allowed() is
  'One answer to "may anything reach a paid inference provider right now". False while the founder '
  'holds any route open-circuit, false while app_secrets.no_paid_ai is set, and false when the '
  'route table is empty — an absent hold is not a permission.';

-- The cached provider state ai_health reports from while the hold is on. No network required, and
-- the number it prints is the one the estate already recorded.
create or replace function public.fn_os_provider_state_cached()
returns jsonb language sql stable set search_path to 'public', 'pg_temp' as $$
  select jsonb_build_object(
    'paid_ai_allowed', public.fn_os_paid_ai_allowed(),
    'routes_held', (select count(*) from public.llm_route_health where open_until > now()),
    'routes_total', (select count(*) from public.llm_route_health),
    'hold_reason', (select max(opened_reason) from public.llm_route_health where open_until > now()),
    'held_until', (select max(open_until) from public.llm_route_health),
    'key_present', (select count(*) > 0 from public.app_secrets where key = 'openrouter_api_key'),
    'last_paid_attempt_at', (select max(created_at) from public.llm_attempt),
    'last_cost_row_at', (select max(occurred_at) from public.ai_cost_log),
    'cost_aed_since_phase_c', coalesce((select sum(cost_aed) from public.ai_cost_log
                                        where occurred_at > timestamptz '2026-08-15 02:51:36+00'), 0));
$$;
revoke all on function public.fn_os_provider_state_cached() from public;
grant execute on function public.fn_os_provider_state_cached() to service_role, anon, authenticated;
