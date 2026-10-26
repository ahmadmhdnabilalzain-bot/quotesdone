create or replace function public.fn_what_if(p_question text, p_change jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_sup int; v_rev numeric; v_cost numeric; v_conv numeric; v_pool int;
  v_impact jsonb; v_conf numeric; v_id bigint;
begin
  select count(*) into v_sup from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';
  select coalesce(sum(cost_aed),0) into v_cost from ai_cost_log where occurred_at>now()-interval '30 days';
  select coalesce(sum(sendable),0) into v_pool from v_supply_gap;
  v_conv := 0.05;

  if p_question ~* 'reveal fee|reduce.*fee|lower.*fee' then
    v_impact := jsonb_build_object('revenue_per_reveal','down by the discount percentage',
      'reveal_volume','unknown - no reveals have occurred, so elasticity is unmeasured',
      'net_revenue','indeterminate',
      'honest_answer','This cannot be simulated. Zero reveals have happened, so there is no price-response curve to extrapolate from. Any number would be invented.');
    v_conf := 0.15;
  elsif p_question ~* 'model price|openrouter|ai cost.*double|llm cost' then
    v_impact := jsonb_build_object('current_monthly_ai_cost_aed',round(v_cost,2),'if_doubled_aed',round(v_cost*2,2),
      'share_of_total_budget', round(100.0*v_cost*2/nullif((select sum(monthly_aed) from department_budget),0),1)||'%',
      'mitigation','Model policy already routes by task class; cache adoption is 0%, so caching is the first lever.');
    v_conf := 0.8;
  elsif p_question ~* 'invite|supplier.*onboard|scale.*supplier' then
    v_impact := jsonb_build_object('sendable_pool',v_pool,'expected_approved_at_5pct',round(v_pool*v_conv),
      'target',860,'shortfall',greatest(0,860-round(v_pool*v_conv)),
      'note','Assumes a 5% invite-to-approved conversion, which is an assumption not an observation - no invite has converted yet.');
    v_conf := 0.45;
  elsif p_question ~* 'saudi|expand|new market' then
    v_impact := jsonb_build_object('home_market_readiness',(select count(*) from v_supply_gap where approved>=10)||' of 86 categories at target',
      'assessment','Expanding before the home market has any onboarded supply spreads a thin pool thinner and the category knowledge is UAE-specific.');
    v_conf := 0.7;
  else
    v_impact := jsonb_build_object('assessment','No model exists for this question yet. Add a scenario to scenario_library so it can be simulated rather than guessed.');
    v_conf := 0.2;
  end if;

  insert into simulations (scenario, result)
  values (jsonb_build_object('question',p_question,'change',p_change,'confidence',v_conf), v_impact)
  returning id into v_id;

  return jsonb_build_object('id',v_id,'question',p_question,'projection',v_impact,'confidence',v_conf,
    'basis', jsonb_build_object('approved_suppliers',v_sup,'revenue_30d',v_rev,'ai_cost_30d',round(v_cost,2),'sendable_pool',v_pool));
end $fn$;
revoke execute on function public.fn_what_if(text,jsonb) from public, anon, authenticated;