-- A TRIPPED BREAKER ON ONE ROUTE NEVER HOLDS THE WHOLE ESTATE -- it_engineer, 7 Oct 2026.
--
-- Founder ruling 7 Oct 2026 (ledger 1175): "from now on keep open router always on". The hold was
-- lifted on production the same morning: 0 of 19 llm_route_health rows carry an open_until in the
-- future and the gate answers 'registered_breaker_closed'.
--
-- THE DEFECT THE LIFT EXPOSES. Rule 3 of fn_kernel_paid_provider_gate counted EVERY route with
-- open_until > now() as "the founder's hold". While every route sat at 2126 that was the same set.
-- With the hold off, the only rows that get an open_until are real failure breakers, which open for
-- cooldown_seconds (300-900 s) on ONE model. Under the old rule one tripped breaker on one model
-- would deny every paid call on every route, estate-wide, with rule 'founder_hold' -- a hold the
-- founder never imposed. Failure breakers must stay per-route (rule 5, unchanged).
--
-- THE CHANGE, ONE LINE: rule 3 counts only founder-held rows, read from the date exactly as rule 5
-- and fn_llm_route_founder_held already read it (more than a year out). A real breaker is a
-- cooldown in minutes and falls through to rule 5, which refuses that one route only.
-- Body otherwise byte-copied from production (pg_get_functiondef, 7 Oct 2026 03:35 UTC).
-- CREATE OR REPLACE keeps the existing ACL, so no revoke here.
-- Prevented by: scripts/checks/a_tripped_breaker_on_one_route_never_holds_the_whole_estate.test.mjs

CREATE OR REPLACE FUNCTION public.fn_kernel_paid_provider_gate(p_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_switch  boolean;
  v_routes  bigint;
  v_held    bigint;
  v_model   text := nullif(btrim(coalesce(p_model, '')), '');
  v_reg     boolean;
  v_open    timestamptz;
  v_tag     text;
  v_cap     numeric;
  v_spent   numeric;
  v_rehearsal boolean := false;
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

  -- 0. A SANDBOX RUN'S CALL (ledger 1119). Untagged traffic skips this block entirely.
  v_tag := public.fn_e2e_run_tag_current();
  if v_tag is not null then
    if not coalesce(public.fn_e2e_run_tag_open(v_tag), false) then
      return jsonb_build_object('allowed', false, 'gate', 'kernel_k12', 'rule', 'rehearsal_window_closed',
        'reason', 'the call carries sandbox run tag ' || left(v_tag, 16) || ' but no open, unexpired, model-enabled rehearsal window names it',
        'model', v_model);
    end if;
    select w.cap_usd into v_cap from public.rehearsal_window w
     where w.run_tag = 'qd_run:' || v_tag and w.ended_at is null order by w.started_at desc limit 1;
    select coalesce(sum(cost_aed), 0) / 3.6725 into v_spent from public.ai_cost_log where e2e_run_tag = v_tag;
    if v_spent >= v_cap then
      return jsonb_build_object('allowed', false, 'gate', 'kernel_k12', 'rule', 'rehearsal_cap',
        'reason', 'sandbox run ' || v_tag || ' has spent USD ' || round(v_spent, 4) || ' of its USD ' || v_cap || ' cap',
        'model', v_model);
    end if;
    v_rehearsal := true;
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
  --    and leaving the others open would not be what he asked for. A sandbox run inside its open
  --    window passes the hold; it does not lift it.
  select count(*) into v_held from public.llm_route_health where open_until is not null and open_until > now() + interval '1 year';
  if v_held > 0 and not v_rehearsal then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'founder_hold',
      'reason', v_held || ' of ' || v_routes || ' routes are held open-circuit until '
             || (select max(open_until)::text from public.llm_route_health where open_until > now() + interval '1 year'),
      'held', v_held, 'routes', v_routes, 'model', v_model);
  end if;

  -- 4. the route must be registered and active
  select exists (select 1 from public.model_registry r where r.model_id = v_model and r.active) into v_reg;
  if not v_reg then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_not_registered',
      'reason', 'model ' || v_model || ' is not an active row in model_registry', 'model', v_model);
  end if;

  -- 5. this route's own breaker. For a sandbox run, a route held by the hold is not a breaker. Measured
  --    6 Oct 2026: every route is held to 2126-08-15, with opened_reason either 'HELD BY THE FOUNDER' or
  --    'held with the rest of the fleet'. A real breaker opens for cooldown_seconds (900). So 'held' is
  --    read from the date (more than a year out), never from the reason text, which has two spellings.
  select open_until into v_open from public.llm_route_health where model_id = v_model;
  if v_open is not null and v_open > now()
     and not (v_rehearsal and v_open > now() + interval '365 days') then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_open', 'reason', 'circuit open until ' || v_open::text, 'model', v_model);
  end if;

  if v_rehearsal then
    return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
      'rule', 'rehearsal_window', 'reason', 'sandbox run ' || v_tag || ' inside its open window, USD '
             || round(v_spent, 4) || ' of ' || v_cap || ' spent; the founder''s hold stays on for all other traffic',
      'model', v_model);
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
end $function$
;
