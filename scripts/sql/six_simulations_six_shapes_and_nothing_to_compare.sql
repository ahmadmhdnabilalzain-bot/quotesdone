-- Six simulations, six shapes, and nothing to compare
-- ==================================================
--
-- Row #3's what-if-projected-deltas asks that EVERY simulation return projected deltas on revenue,
-- leads and profit. It reads 0 of 6, and the reason is not that the simulator is weak - it is that
-- there is no output contract at all. The six stored results share almost no keys:
--
--   1,3 fee_change     projected_annual_revenue_aed, vs_current_fee_annual_aed, reveal_volume_change_pct
--   2   supply_double  approved_suppliers_after, quotes_per_rfq_after, expected_conversion_uplift_pct
--   4   free-text      net_revenue, reveal_volume, revenue_per_reveal
--   5   free-text      assessment
--   8   free-text      current_monthly_ai_cost_aed, if_doubled_aed, share_of_total_budget
--
-- Every branch invented its own shape, so nothing on the founder's screen can put two simulations
-- side by side, and the one question a simulation exists to answer - what does this change do to
-- the money - has a different key name each time.
--
-- This adds the three contract keys at the single point where confidence, assumptions and basis
-- are already appended, derived from what each branch computed rather than recalculated. NULL
-- where the scenario genuinely does not model that dimension: supply_double moves quotes per RFQ
-- and says nothing about revenue with zero quotes on file, so its revenue delta is null rather
-- than a number invented to fill a key. The check tests that the keys exist; the values tell the
-- truth about what was and was not modelled.
--
-- The six ALREADY-STORED rows keep their old shapes and the check stays MISSING until they age out
-- or are re-simulated - deliberately. Rewriting a stored simulation's result would change an answer
-- the company may already have acted on.

CREATE OR REPLACE FUNCTION public.fn_simulate(p_scenario jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  typ text := coalesce(p_scenario->>'type','');
  aov numeric; cur_fee numeric; suppliers int; deals_pm numeric; res jsonb; conf text; assum jsonb;
begin
  select round(avg(quote_amount),0) into aov from quotes where quote_amount is not null and quote_amount>0;
  aov := coalesce(aov, 45000);  -- fallback UAE mid-size job
  begin select coalesce((value->>'reveal_pct')::numeric, 3)/100 into cur_fee from pricing_config limit 1; exception when others then cur_fee:=0.03; end;
  cur_fee := coalesce(cur_fee,0.03);
  select count(*) into suppliers from leads where coalesce(approval_status,'')='approved';
  deals_pm := coalesce((p_scenario->>'deals_per_month')::numeric, 100);  -- modelled target if provided, else 100

  if typ='fee_change' then
    declare new_fee numeric := coalesce((p_scenario->>'new_fee_pct')::numeric,4)/100; elasticity numeric := 0.6; drop_pct numeric;
    begin
      drop_pct := greatest(0, (new_fee-cur_fee)/nullif(cur_fee,0)) * elasticity;   -- higher fee -> fewer reveals
      res := jsonb_build_object(
        'current_fee_pct', round(cur_fee*100,2), 'new_fee_pct', round(new_fee*100,2),
        'assumed_deals_per_month', deals_pm, 'avg_job_aed', aov,
        'reveal_volume_change_pct', round(-drop_pct*100,1),
        'projected_monthly_revenue_aed', round(deals_pm*(1-drop_pct)*aov*new_fee),
        'projected_annual_revenue_aed', round(12*deals_pm*(1-drop_pct)*aov*new_fee),
        'vs_current_fee_annual_aed', round(12*deals_pm*aov*(new_fee*(1-drop_pct) - cur_fee)));
      assum := jsonb_build_array('Demand elasticity 0.6 (a fee rise reduces reveals proportionally)','Deals/month is a modelled target, not current run-rate','Average job value from live quote data with fallback');
      conf := 'low'; end;

  elsif typ='supply_double' then
    declare qpr_now numeric; qpr_new numeric;
    begin
      select round(avg(qc),1) into qpr_now from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id group by q.inquiry_id) z;
      qpr_now := coalesce(qpr_now,1.5); qpr_new := least(qpr_now*1.6, 6);   -- more supply -> more quotes/RFQ, capped
      res := jsonb_build_object(
        'approved_suppliers_now', suppliers, 'approved_suppliers_after', suppliers*2,
        'quotes_per_rfq_now', qpr_now, 'quotes_per_rfq_after', qpr_new,
        'expected_conversion_uplift_pct', round((qpr_new-qpr_now)/nullif(qpr_now,0)*25,1),
        'note', 'More competitive quotes per RFQ typically lifts buyer conversion and win rates.');
      assum := jsonb_build_array('Quotes/RFQ scales ~0.6x with supply, capped at 6','Conversion uplift ~25% of the quotes/RFQ uplift');
      conf := 'low'; end;

  elsif typ='new_market' then
    declare market text := coalesce(p_scenario->>'market','KSA'); pen numeric := coalesce((p_scenario->>'penetration_pct')::numeric,0.5)/100; tam numeric := coalesce((p_scenario->>'annual_market_aed')::numeric, 5000000000);
    begin
      res := jsonb_build_object('market',market,'assumed_annual_procurement_aed',tam,'assumed_penetration_pct',round(pen*100,3),
        'gmv_captured_aed', round(tam*pen), 'platform_revenue_aed', round(tam*pen*cur_fee),
        'note','Rough top-down sizing; requires local supply activation, licensing and compliance before any revenue.');
      assum := jsonb_build_array('Top-down TAM * penetration (very rough)','Same fee applies','Ignores CAC, localisation and regulatory cost/time');
      conf := 'very low'; end;
  else
    res := jsonb_build_object('error','unknown scenario type; use fee_change | supply_double | new_market');
    assum := '[]'; conf := 'n/a';
  end if;

  res := res || jsonb_build_object(
    'projected_revenue_delta_aed', coalesce((res->>'vs_current_fee_annual_aed')::numeric, (res->>'platform_revenue_aed')::numeric),
    'projected_leads_delta', case when typ='supply_double' then (res->>'approved_suppliers_after')::numeric - (res->>'approved_suppliers_now')::numeric when typ='fee_change' then 0 else null end,
    'projected_profit_delta_aed', coalesce((res->>'vs_current_fee_annual_aed')::numeric, (res->>'platform_revenue_aed')::numeric));
  assum := coalesce(assum,'[]'::jsonb) || to_jsonb(array['Profit delta equals revenue delta: at this volume a reveal carries no marginal cost, so AI spend is fixed overhead','A null projected delta means the scenario does not model that dimension, not that the delta is zero']);
  res := res || jsonb_build_object('confidence',conf,'assumptions',assum,'basis','modelled — QuotesDone is pre-traction, so treat all figures as directional, not forecasts.','computed_at',now());
  insert into simulations(scenario,result) values(p_scenario,res);
  return res;
end $function$
;
