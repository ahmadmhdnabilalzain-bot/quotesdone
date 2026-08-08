-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726224936   name: model_router_and_cost_views
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The routing layer, as a deterministic function every caller consults before spending.
-- Returns the model to use, or a refusal telling the caller to use code instead.
create or replace function public.fn_select_model(
  p_task_class text,
  p_dept_key   text default null,
  p_confidence numeric default null
) returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare
  v_pol   model_policy%rowtype;
  v_bud   department_budget%rowtype;
  v_pct   numeric := 0;
  v_model text;
  v_why   text;
  v_min   numeric;
begin
  select * into v_pol from model_policy where task_class = p_task_class and active;
  if not found then
    return jsonb_build_object('use_llm', true, 'model', 'anthropic/claude-sonnet-5', 'tier','medium',
      'why','No policy for task_class "'||p_task_class||'" - defaulting to medium. Add a policy row.',
      'unpoliced', true);
  end if;

  -- Rule 5: do not use an LLM where deterministic code is correct.
  if v_pol.tier = 'none' then
    return jsonb_build_object('use_llm', false, 'model', null, 'tier','none',
      'why','Deterministic: '||coalesce(v_pol.deterministic_alternative,'use code'),
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for '||p_task_class);

  -- Rule 12: high confidence means no second opinion; low confidence escalates a tier.
  select (value #>> '{}')::numeric into v_min from decision_policy where key='confidence_min';
  if p_confidence is not null and v_min is not null then
    if p_confidence >= 0.95 and v_pol.tier <> 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence '||p_confidence||' >= 0.95, downgraded - no second opinion needed';
    elsif p_confidence < v_min and v_pol.tier = 'small' then
      v_model := 'anthropic/claude-sonnet-5';
      v_why := v_why || ' | confidence '||p_confidence||' below floor '||v_min||', escalated a tier';
    end if;
  end if;

  -- Rule 10: budget-aware degradation.
  if p_dept_key is not null then
    select * into v_bud from department_budget where dept_key = p_dept_key;
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * v_bud.spent_aed / v_bud.monthly_aed);
      if v_pct >= v_bud.halt_at_pct then
        return jsonb_build_object('use_llm', false, 'model', null, 'tier', v_pol.tier,
          'why','Department at '||v_pct||'% of monthly budget - halted for non-gated work',
          'budget_pct', v_pct, 'halted', true);
      elsif v_pct >= v_bud.degrade_at_pct and v_pol.tier = 'large' then
        v_model := coalesce(v_pol.model_fallback, v_model);
        v_why := v_why || ' | department at '||v_pct||'% of budget, degraded from large tier';
      end if;
    end if;
  end if;

  return jsonb_build_object('use_llm', true, 'model', v_model, 'tier', v_pol.tier,
    'max_tokens', v_pol.max_tokens, 'why', v_why, 'budget_pct', v_pct);
end;
$fn$;

-- Cost by department against budget.
create or replace view public.v_ai_spend as
select b.dept_key, d.name as department, b.monthly_aed, b.period_label,
       coalesce(sum(l.cost_aed),0) as spent_aed,
       case when b.monthly_aed > 0 then round(100*coalesce(sum(l.cost_aed),0)/b.monthly_aed) else 0 end as pct_used,
       count(l.id) as calls,
       count(l.id) filter (where l.cached) as cache_hits,
       count(l.id) filter (where l.could_be_cheaper) as downgradable_calls,
       coalesce(sum(l.prompt_tokens+l.output_tokens),0) as tokens
from department_budget b
left join org_departments d on d.dept_key = b.dept_key
left join ai_cost_log l on l.dept_key = b.dept_key
  and to_char(l.occurred_at,'YYYY-MM') = b.period_label
group by b.dept_key, d.name, b.monthly_aed, b.period_label;

-- Where the governor thinks money is being wasted.
create or replace view public.v_cost_optimisation as
select task_class, model_used, tier,
       count(*) as calls,
       round(sum(cost_aed),2) as cost_aed,
       count(*) filter (where could_be_cheaper) as could_downgrade,
       count(*) filter (where cached) as served_from_cache,
       round(avg(prompt_tokens)) as avg_prompt_tokens,
       string_agg(distinct cheaper_reason, ' | ') as reasons
from ai_cost_log group by task_class, model_used, tier order by 5 desc nulls last;

comment on function public.fn_select_model is 'Routing layer: returns the model for a task class, refuses when deterministic code should be used, degrades on budget, adjusts on confidence.';
