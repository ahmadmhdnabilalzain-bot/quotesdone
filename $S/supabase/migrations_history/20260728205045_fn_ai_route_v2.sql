-- ---------------------------------------------------------------------------
-- fn_ai_route — the routing decision, in one call.
--
-- Replaces fn_select_model, which was correct but never reached because it needed a
-- task_class no caller supplied. This version can classify from the calling FUNCTION
-- name via fn_task_class, so routing works without touching 68 call sites.
--
-- It also returns the two directives that were previously missing and that the money
-- actually turns on:
--   * cache  - whether to send Anthropic cache_control. Cache reads are 10% of prompt
--              price and 94% of our token spend is input, so this is the single
--              largest lever available with zero quality change.
--   * stream - whether streaming is safe, so a cancelled generation stops billing.
--
-- And the budget halt now genuinely bites instead of being unreachable.
-- ---------------------------------------------------------------------------

drop function if exists fn_select_model(text, text, numeric);

create or replace function fn_ai_route(
  p_task_class text default null,
  p_dept_key   text default null,
  p_confidence numeric default null,
  p_fn         text default null,
  p_escalate   boolean default false      -- cascade: the cheap tier was not good enough
) returns jsonb
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
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
      -- Very high confidence on an expensive class: the cheaper sibling will do.
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
    -- Policy names a model the registry does not carry. Do not fail the business;
    -- take the cheapest approved model of the intended tier and say so loudly.
    select * into v_reg from model_registry
     where active and approved and tier = (case v_tier when 'xlarge' then 'xlarge' else v_tier end)
     order by in_per_mtok_usd limit 1;
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  select * into v_fb from model_registry where model_id = v_pol.model_fallback and active;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'why', v_why);
end $$;

revoke execute on function fn_ai_route(text,text,numeric,text,boolean) from public, anon, authenticated;

-- Backward-compatible shim: any already-deployed function still calling
-- fn_select_model(p_task_class, p_dept_key, p_confidence) keeps working and now gets
-- the new routing, including the cheap tier and the real halt.
create or replace function fn_select_model(
  p_task_class text, p_dept_key text default null, p_confidence numeric default null)
returns jsonb
language sql stable
security definer
set search_path = public, pg_temp
as $$ select fn_ai_route(p_task_class, p_dept_key, p_confidence, null, false); $$;

revoke execute on function fn_select_model(text,text,numeric) from public, anon, authenticated;

comment on function fn_ai_route(text,text,numeric,text,boolean) is
  'Single routing decision: task class (explicit or derived from the calling function), model, tier, token cap, prompt-cache and streaming directives, and a budget halt that actually stops the call. Added 28 Jul 2026 to replace fn_select_model, which was unreachable.';