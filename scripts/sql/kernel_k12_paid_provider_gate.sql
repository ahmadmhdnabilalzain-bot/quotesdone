-- ============================================================================================
-- KERNEL K12 — ONE FAIL-CLOSED PAID-PROVIDER GATE
--
-- The audit's finding, on the deployed code:
--
--   ai_gateway/index.ts:459-464
--     for (const m of fullLadder) {
--       try {
--         const { data: pf } = await admin.rpc('fn_llm_preflight', { p_model: m });
--         if (pf && pf.allowed === false) { skipped.push(...); continue; }
--       } catch (_e) { /* preflight must never be the reason a call cannot happen */ }
--       ladder.push(m);
--     }
--
-- Three ways that reaches a paid provider without permission: the RPC throws and the catch falls
-- through to push; the RPC returns null and `pf &&` short-circuits to push; the RPC returns a shape
-- without `allowed` and the strict `=== false` misses it. The comment states the intent plainly —
-- the gate must never be the reason a call cannot happen — which is the opposite of fail-closed.
--
-- There were also two authorities. fn_os_paid_ai_allowed() knows about the no_paid_ai switch and
-- denies on an empty route table; fn_llm_preflight(model) knows about registration and the route
-- hold and knows nothing about the switch. A caller consulting either one alone gets a different
-- answer, which is how the estate ended up with four doors and three opinions.
--
-- This is ONE function. Every paid-provider client asks it and nothing else. Every branch that is
-- not an explicit, evidenced permission returns allowed=false, and the reason names which rule
-- refused, so a denial is never mistaken for an outage.
-- ============================================================================================

create or replace function public.fn_kernel_paid_provider_gate(p_model text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_switch  boolean;
  v_routes  bigint;
  v_held    bigint;
  v_model   text := nullif(btrim(coalesce(p_model, '')), '');
  v_reg     boolean;
  v_open    timestamptz;
begin
  -- An EMPTY STRING is not a deterministic path, it is a caller that did not say. Denied, with its
  -- own rule name, because "I passed you nothing" and "I am not calling a provider" are different
  -- statements and a gate that conflates them has a hole shaped like a typo.
  if p_model is not null and v_model is null then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'model_unspecified',
      'reason', 'an empty model string is not a deterministic path; pass NULL or ''none'' to declare '
             || 'that no provider call is being made', 'model', p_model);
  end if;

  -- A deterministic path is not a provider call and never was. It is named explicitly rather than
  -- reached by falling off the end of the checks.
  if v_model is null or v_model in ('none', 'none/deterministic') then
    return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
      'rule', 'deterministic_path', 'reason', 'no provider call is being made', 'model', p_model);
  end if;

  -- 1. the explicit switch
  select exists (select 1 from public.app_secrets
                  where key = 'no_paid_ai' and lower(coalesce(value,'')) in ('1','true','yes','on'))
    into v_switch;
  if v_switch then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'no_paid_ai_switch', 'reason', 'app_secrets.no_paid_ai is set; paid inference is off',
      'model', v_model);
  end if;

  -- 2. empty route state is DENIED, not permitted. An absent hold is not a permission — this is the
  --    "what does it print when its input is absent?" case, answered on purpose.
  select count(*) into v_routes from public.llm_route_health;
  if v_routes = 0 then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'empty_route_state',
      'reason', 'llm_route_health holds no rows; with no route state there is no evidence that any '
             || 'route is permitted', 'model', v_model);
  end if;

  -- 3. the founder's hold, on ANY route. He held the whole estate on 15 Aug 2026; holding one route
  --    and leaving the others open would not be what he asked for.
  select count(*) into v_held from public.llm_route_health where open_until is not null and open_until > now();
  if v_held > 0 then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'founder_hold',
      'reason', v_held || ' of ' || v_routes || ' routes are held open-circuit until '
             || (select max(open_until)::text from public.llm_route_health where open_until > now()),
      'held', v_held, 'routes', v_routes, 'model', v_model);
  end if;

  -- 4. the route must be registered and active
  select exists (select 1 from public.model_registry r where r.model_id = v_model and r.active) into v_reg;
  if not v_reg then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_not_registered',
      'reason', 'model ' || v_model || ' is not an active row in model_registry', 'model', v_model);
  end if;

  -- 5. this route's own breaker
  select open_until into v_open from public.llm_route_health where model_id = v_model;
  if v_open is not null and v_open > now() then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_open', 'reason', 'circuit open until ' || v_open::text, 'model', v_model);
  end if;

  return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
    'rule', 'registered_breaker_closed', 'reason', 'switch off, no hold, route registered, breaker closed',
    'model', v_model);
exception
  -- The gate itself failing is the most dangerous case, because it is the one a try/catch upstream
  -- used to swallow. It answers DENIED, in its own voice, rather than throwing into a caller that
  -- might interpret an exception as "carry on".
  when others then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'gate_unreadable',
      'reason', 'the paid-provider gate could not be evaluated: ' || sqlstate || ' ' || sqlerrm,
      'model', p_model);
end $fn$;

revoke all on function public.fn_kernel_paid_provider_gate(text) from public;
grant execute on function public.fn_kernel_paid_provider_gate(text) to service_role;

-- ------------------------------------------------------------------ the invariant that watches it
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_paid_provider_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_paid_provider_state() from public;
grant execute on function public.fn_kernel_paid_provider_state() to service_role;
