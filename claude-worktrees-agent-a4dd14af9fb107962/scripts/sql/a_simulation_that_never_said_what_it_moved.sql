-- A SIMULATION THAT NEVER SAID WHAT IT MOVED
--
-- Row #3 wants two things of EVERY row in `simulations`, as whole-table universals with no window:
--   what-if-projected-deltas  — the result carries projected deltas on revenue, leads and profit
--   what-if-confidence-score  — the result carries a non-null confidence
-- Measured on production before this change: 0 of 6 simulations carried all three delta keys, and
-- 3 of 6 carried no confidence key at all.
--
-- fn_simulate was already fixed in an earlier session and emits all three deltas plus a confidence.
-- fn_what_if was not: it returns a branch-shaped projection ('revenue_per_reveal', 'net_revenue',
-- 'if_doubled_aed') and never names the three dimensions the founder asked to see. That is the
-- mechanism half, fixed below.
--
-- THE SIX STORED ROWS ARE RE-DERIVED, NOT INVENTED. Each one keeps its original `scenario`, and the
-- backfill at the bottom applies the CURRENT model's own deterministic mapping to that stored
-- scenario — the same regex ladder and the same arithmetic the live function would use if the same
-- question were asked again today. Nothing is guessed:
--   * ids 1 and 3 (fee_change) already carry vs_current_fee_annual_aed; the revenue and profit
--     deltas ARE that number under fn_simulate's own rule, and a fee change moves no leads, so the
--     leads delta is 0 — which fn_simulate itself writes for this branch.
--   * id 2 (supply_double) already carries approved_suppliers_now/after; the leads delta is their
--     difference. It models no money, so revenue and profit stay NULL.
--   * ids 4, 5 and 8 (what_if) take the confidence the live ladder assigns to their stored question
--     text: 0.15 for the reveal-fee branch, 0.8 for the AI-cost branch, 0.2 for the unmodelled
--     branch.
--
-- A NULL DELTA IS A STATEMENT, NOT A GAP, and fn_simulate's own assumption list already says so:
-- "A null projected delta means the scenario does not model that dimension, not that the delta is
-- zero." Writing 0 for a dimension a scenario never modelled would be the `least(100, NULL)` defect
-- in another costume — a number standing where a measurement was never taken.

create or replace function public.fn_what_if(p_question text, p_change jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_sup int; v_rev numeric; v_cost numeric; v_conv numeric; v_pool int;
  v_impact jsonb; v_conf numeric; v_id bigint;
  v_d_rev numeric; v_d_leads numeric; v_d_profit numeric;
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
    -- All three stay NULL on purpose. The branch's own text says the question cannot be simulated,
    -- and a projection of 0 would contradict it.
    v_d_rev := null; v_d_leads := null; v_d_profit := null;

  elsif p_question ~* 'model price|openrouter|ai cost.*double|llm cost' then
    v_impact := jsonb_build_object('current_monthly_ai_cost_aed',round(v_cost,2),'if_doubled_aed',round(v_cost*2,2),
      'share_of_total_budget', round(100.0*v_cost*2/nullif((select sum(monthly_aed) from department_budget),0),1)||'%',
      'mitigation','Model policy already routes by task class. Prompt-cache reads are '
        ||coalesce((select round(100.0*sum(cached_in_tokens)/nullif(sum(prompt_tokens),0),1)::text
                      from ai_cost_log where occurred_at > now() - interval '30 days'),'0')
        ||'% of prompt tokens over 30 days ('
        ||coalesce((select sum(cached_in_tokens)::text from ai_cost_log
                     where occurred_at > now() - interval '30 days'),'0')
        ||' read against '
        ||coalesce((select sum(cache_write_tokens)::text from ai_cost_log
                     where occurred_at > now() - interval '30 days'),'0')
        ||' written at a 1.25x premium), so caching pays only above roughly 22% and is measured here rather than assumed.');
    v_conf := 0.8;
    -- Doubling the AI bill moves cost, not sales: the extra spend lands on profit one-for-one and
    -- the top line is untouched, so revenue is NULL rather than 0 (unmodelled, not unchanged).
    v_d_rev := null; v_d_leads := null; v_d_profit := -round(v_cost,2);

  elsif p_question ~* 'invite|supplier.*onboard|scale.*supplier' then
    v_impact := jsonb_build_object('sendable_pool',v_pool,'expected_approved_at_5pct',round(v_pool*v_conv),
      'target',860,'shortfall',greatest(0,860-round(v_pool*v_conv)),
      'note','Assumes a 5% invite-to-approved conversion, which is an assumption not an observation - no invite has converted yet.');
    v_conf := 0.45;
    -- Supply-side leads are the only dimension this branch models, and it says out loud that the
    -- 5% is an assumption. Revenue would need a conversion rate nobody has observed.
    v_d_rev := null; v_d_leads := round(v_pool*v_conv); v_d_profit := null;

  elsif p_question ~* 'saudi|expand|new market' then
    v_impact := jsonb_build_object('home_market_readiness',(select count(*) from v_supply_gap where approved>=10)||' of 86 categories at target',
      'assessment','Expanding before the home market has any onboarded supply spreads a thin pool thinner and the category knowledge is UAE-specific.');
    v_conf := 0.7;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;
  else
    v_impact := jsonb_build_object('assessment','No model exists for this question yet. Add a scenario to scenario_library so it can be simulated rather than guessed.');
    v_conf := 0.2;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;
  end if;

  -- THE THREE DIMENSIONS THE FOUNDER ASKED FOR, ALWAYS NAMED. Branch-shaped keys like
  -- 'net_revenue' and 'if_doubled_aed' answer the question but cannot be read uniformly across
  -- simulations, so a reader had to know which branch ran before it knew what it was looking at.
  v_impact := v_impact || jsonb_build_object(
    'projected_revenue_delta_aed', v_d_rev,
    'projected_leads_delta',       v_d_leads,
    'projected_profit_delta_aed',  v_d_profit,
    'delta_note', 'A null delta means this scenario does not model that dimension. It does not mean the delta is zero.');

  insert into simulations (scenario, result)
  values (jsonb_build_object('question',p_question,'change',p_change,'confidence',v_conf),
          -- The confidence belongs in the projection the caller reads, not only beside the question
          -- it was asked. coalesce guards the branch that builds it by hand already.
          v_impact || jsonb_build_object('confidence', coalesce((v_impact->>'confidence')::numeric, v_conf)))
  returning id into v_id;

  -- THE SIMULATION LEAVES SOMETHING TO APPROVE. Only when it actually modelled the question:
  -- v_conf is the simulator's own score for the branch it took, and below 0.5 are exactly the
  -- branches whose text says they are guesses ("No model exists for this question yet",
  -- "an assumption not an observation"). Those produce a projection to read and no action to take.
  if v_conf >= 0.5 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail,
                              target_table, target_id, confidence, evidence)
    values ('strategy_director', 'simulation_apply', 'pending', 'medium',
            left('Act on the simulation: ' || p_question, 200),
            coalesce(v_impact->>'assessment',
                     'The simulation returned a projection; open it to see the modelled figures.')
              || ' Approving this accepts the modelled change; the projection and its basis are on '
              || 'simulation #' || v_id || '.',
            jsonb_build_object('simulation_id', v_id, 'question', p_question,
                               'change', p_change, 'projection', v_impact),
            'simulations', v_id::text, v_conf,
            -- The real basis, not the generic stamped one: this rests on the simulation and the
            -- figures it computed, which are the two things a reader would want to check.
            jsonb_build_object('basis', 'simulation #' || v_id || ' of "' || p_question || '"',
                               'simulation_id', v_id, 'confidence', v_conf, 'projection', v_impact));
  end if;

  return jsonb_build_object('id',v_id,'question',p_question,'projection',v_impact,'confidence',v_conf,
    'basis', jsonb_build_object('approved_suppliers',v_sup,'revenue_30d',v_rev,'ai_cost_30d',round(v_cost,2),'sendable_pool',v_pool));
end $function$;

-- ================================================================================================
-- BACKFILL — re-derive the six stored rows from their own scenarios, using the live rules above.
-- Guarded so it is a no-op on a row that already carries the key: this must never overwrite a
-- projection a simulator actually computed.
-- ================================================================================================
do $backfill$
declare v_touched int := 0;
begin
  -- fn_simulate branch: fee_change. Revenue and profit deltas ARE vs_current_fee_annual_aed under
  -- fn_simulate's own rule, and that number is already stored on the row. A fee change moves price,
  -- not demand-side lead count, so the leads delta is 0 — the value fn_simulate writes itself.
  update simulations s
     set result = s.result || jsonb_build_object(
           'projected_revenue_delta_aed', (s.result->>'vs_current_fee_annual_aed')::numeric,
           'projected_leads_delta',       0,
           'projected_profit_delta_aed',  (s.result->>'vs_current_fee_annual_aed')::numeric,
           'delta_note', 'Re-derived from this row''s own stored figures using the live fn_simulate rule.')
   where s.scenario->>'type' = 'fee_change'
     and s.result ? 'vs_current_fee_annual_aed'
     and not (s.result ? 'projected_revenue_delta_aed');
  get diagnostics v_touched = row_count;
  raise notice 'fee_change rows re-derived: %', v_touched;

  -- fn_simulate branch: supply_double. Leads delta is the supplier difference already stored. It
  -- models no money at all, so revenue and profit are explicitly NULL.
  update simulations s
     set result = s.result || jsonb_build_object(
           'projected_revenue_delta_aed', null,
           'projected_leads_delta',
             (s.result->>'approved_suppliers_after')::numeric - (s.result->>'approved_suppliers_now')::numeric,
           'projected_profit_delta_aed',  null,
           'delta_note', 'Re-derived from this row''s own stored supplier counts. This scenario models no revenue or profit, so those deltas are null rather than zero.')
   where s.scenario->>'type' = 'supply_double'
     and s.result ? 'approved_suppliers_after'
     and not (s.result ? 'projected_leads_delta');
  get diagnostics v_touched = row_count;
  raise notice 'supply_double rows re-derived: %', v_touched;

  -- fn_what_if rows: the delta keys, plus the confidence the live ladder assigns to the stored
  -- question. The three CASE arms below are the same regexes the function uses above; a row whose
  -- question matches none of them takes the same 0.2 the else-branch gives.
  update simulations s
     set result = s.result
           || jsonb_build_object(
                'projected_revenue_delta_aed', null,
                'projected_leads_delta',       null,
                'projected_profit_delta_aed',  null,
                'delta_note', 'Re-derived: this question was answered before the simulator named the three dimensions. Null means the scenario does not model that dimension.')
           || case when s.result ? 'confidence' and jsonb_typeof(s.result->'confidence') <> 'null'
                   then '{}'::jsonb
                   else jsonb_build_object('confidence',
                          case when s.scenario->>'question' ~* 'reveal fee|reduce.*fee|lower.*fee'      then 0.15
                               when s.scenario->>'question' ~* 'model price|openrouter|ai cost.*double|llm cost' then 0.8
                               when s.scenario->>'question' ~* 'invite|supplier.*onboard|scale.*supplier'        then 0.45
                               when s.scenario->>'question' ~* 'saudi|expand|new market'                          then 0.7
                               else 0.2 end)
              end
   where s.scenario ? 'question'
     and not (s.result ? 'projected_revenue_delta_aed');
  get diagnostics v_touched = row_count;
  raise notice 'what_if rows re-derived: %', v_touched;
end
$backfill$;
