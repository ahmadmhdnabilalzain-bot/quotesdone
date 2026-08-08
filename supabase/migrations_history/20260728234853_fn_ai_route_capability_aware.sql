-- Adding a defaulted parameter would create an overload, and every existing named-argument call
-- would then be ambiguous ("function is not unique"). Drop first, recreate once.
drop function if exists public.fn_ai_route(text, text, numeric, text, boolean);

create or replace function public.fn_ai_route(
  p_task_class   text    default null,
  p_dept_key     text    default null,
  p_confidence   numeric default null,
  p_fn           text    default null,
  p_escalate     boolean default false,
  p_require_caps text[]  default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_class   text;
  v_src     text;
  v_pol     model_policy%rowtype;
  v_reg     model_registry%rowtype;
  v_fb      model_registry%rowtype;
  v_bud     department_budget%rowtype;
  v_pct     numeric := 0;
  v_model   text;
  v_why     text;
  v_min     numeric;
  v_tier    text;
  v_vis     boolean := 'vision' = any(coalesce(p_require_caps, '{}'::text[]));
  v_aud     boolean := 'audio'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_tls     boolean := 'tools'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_sub     model_registry%rowtype;
begin
  -- 1. Which task class? Explicit beats the map; the map beats nothing.
  if p_task_class is not null and length(btrim(p_task_class)) > 0 then
    v_class := p_task_class; v_src := 'caller-supplied task_class';
  else
    select task_class into v_class from fn_task_class where fn = p_fn and active;
    if v_class is not null then
      v_src := 'classified from calling function "' || p_fn || '"';
    else
      v_class := 'general_drafting';
      v_src := 'UNMAPPED function "' || coalesce(p_fn,'?') || '" - defaulted to general_drafting (medium). Add a fn_task_class row to route this properly.';
    end if;
  end if;

  select * into v_pol from model_policy where task_class = v_class and active;
  if not found then
    select * into v_pol from model_policy where task_class = 'general_drafting' and active;
    v_src := v_src || ' | no policy for "' || v_class || '", fell back to general_drafting';
  end if;

  -- 2. Rule 5: never use a model where deterministic code is correct.
  -- A capability requirement does not buy an exemption: if the class is deterministic, an image
  -- attached to it means the CALLER is wrong, not the policy.
  if v_pol.tier = 'none' then
    return jsonb_build_object(
      'use_llm', false, 'task_class', v_class, 'tier', 'none',
      'why', 'REFUSED. ' || coalesce(v_pol.deterministic_alternative, 'This is deterministic - use code.')
             || ' [' || v_src || ']',
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_tier  := v_pol.tier;
  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for ' || v_class) || ' [' || v_src || ']';

  -- 3. Cascade: a failed or low-quality cheap attempt escalates one tier, once.
  if p_escalate then
    v_model := coalesce(v_pol.model_fallback, v_model);
    v_why   := v_why || ' | ESCALATED one tier after an unsatisfactory cheaper attempt';
  end if;

  -- 4. Rule 12: confidence adjusts the tier in both directions.
  select (value #>> '{}')::numeric into v_min from decision_policy where key = 'confidence_min';
  if p_confidence is not null then
    if p_confidence >= 0.95 and v_tier in ('large','xlarge') then
      select model_id into v_model from model_registry
       where active and approved and tier = 'medium' order by in_per_mtok_usd limit 1;
      v_why := v_why || ' | confidence ' || p_confidence || ' >= 0.95, downgraded to medium - no second opinion needed';
    elsif v_min is not null and p_confidence < v_min and v_tier = 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence ' || p_confidence || ' below floor ' || v_min || ', escalated a tier';
    end if;
  end if;

  -- 5. Rule 10: budget-aware degradation, and a halt that actually stops the call.
  if p_dept_key is not null then
    select * into v_bud from department_budget where dept_key = p_dept_key;
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * coalesce(
        (select sum(cost_aed) from ai_cost_log
          where dept_key = p_dept_key and occurred_at >= date_trunc('month', now())), 0)
        / v_bud.monthly_aed, 2);
      if v_pct >= v_bud.halt_at_pct then
        return jsonb_build_object(
          'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'halted', true, 'budget_pct', v_pct,
          'why', 'HALTED. ' || p_dept_key || ' is at ' || v_pct || '% of its monthly AI budget (halt at '
                 || v_bud.halt_at_pct || '%). Non-gated work stops until the budget resets or is raised.');
      elsif v_pct >= v_bud.degrade_at_pct then
        select model_id into v_model from model_registry
         where active and approved
           and tier = case v_tier when 'xlarge' then 'large' when 'large' then 'medium' else 'small' end
         order by in_per_mtok_usd limit 1;
        v_why := v_why || ' | department at ' || v_pct || '% of budget, degraded one tier';
      end if;
    end if;
  end if;

  select * into v_reg from model_registry where model_id = v_model and active;
  if not found then
    select * into v_reg from model_registry
     where active and approved and tier = (case v_tier when 'xlarge' then 'xlarge' else v_tier end)
     order by in_per_mtok_usd limit 1;
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  -- 6. CAPABILITY. Everything above chose on price and tier. If the payload needs eyes, ears or
  -- tools and the chosen model has none, the call would fail at the provider - so substitute the
  -- CHEAPEST capable model, preferring the intended tier, and say plainly that policy was overridden.
  if (v_vis or v_aud or v_tls)
     and not ( (not v_vis or coalesce(v_reg.supports_vision,false))
           and (not v_aud or coalesce(v_reg.supports_audio, false))
           and (not v_tls or coalesce(v_reg.supports_tools, false)) ) then

    select * into v_sub from model_registry
     where active and approved and tier = v_tier
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by in_per_mtok_usd limit 1;

    if not found then
      select * into v_sub from model_registry
       where active and approved
         and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
       order by in_per_mtok_usd limit 1;
    end if;

    if found then
      v_why := v_why || ' | CAPABILITY OVERRIDE: ' || v_model || ' cannot do ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+') || '); substituted ' || v_sub.model_id;
      v_reg := v_sub; v_model := v_sub.model_id;
    else
      -- Better an explicit refusal than a provider error the caller has to guess at.
      return jsonb_build_object(
        'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'caps', to_jsonb(p_require_caps),
        'why', 'REFUSED. No active approved model in model_registry supports ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+')
               || '). Add one, or mark the capability on an existing model.');
    end if;
  end if;

  -- The fallback has to clear the same bar, or the ladder's second rung is a guaranteed failure.
  select * into v_fb from model_registry
   where model_id = v_pol.model_fallback and active
     and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools);
  if not found and (v_vis or v_aud or v_tls) then
    select * into v_fb from model_registry
     where active and approved and model_id <> v_model
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by in_per_mtok_usd limit 1;
  end if;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'caps', to_jsonb(coalesce(p_require_caps, '{}'::text[])),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'why', v_why);
end $function$;

revoke all on function public.fn_ai_route(text, text, numeric, text, boolean, text[]) from public, anon, authenticated;
grant execute on function public.fn_ai_route(text, text, numeric, text, boolean, text[]) to service_role;