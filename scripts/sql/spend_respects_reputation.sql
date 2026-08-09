-- ROW #3 s32 — reputation is computed for 66 employees and consulted by nothing that grants authority.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s32-reputation-drives-authority  MISSING  0 of 5 authority routine(s) consult agent_reputation;
--                                             7 employee(s) on probation and 59 above it, against
--                                             285 authority row(s); the gate recorded 1,229
--                                             verdict(s)/30d
-- 
-- The company already believes reputation should change authority — fn_reputation_recompute ends by
-- demoting every probation-tier employee's employee_authority.max_tier from 'autonomous' to
-- 'gated'. What it does NOT do is reach the moment authority is exercised. fn_check_spend reads
-- employee_authority.threshold_aed as the agent's personal limit and has no idea whether the agent
-- holding that limit is on probation. So a demoted employee keeps spending to their nominal ceiling
-- until something else notices.
-- 
-- ── THE RULE, AND WHY IT IS THIS RULE ───────────────────────────────────────────────────────────
-- On probation, the personal limit does not apply and the spend goes to a person. That is not a new
-- policy invented here — it is the same decision fn_reputation_recompute already takes when it
-- writes max_tier='gated', applied at the point where the money would actually move.
-- 
-- No threshold is scaled, no fraction is invented. The two states are "your limit applies" and
-- "your limit does not apply", because any number in between would be a figure this file made up.
-- 
-- The tier is returned in the payload as `reputation_tier` alongside `agent_limit_aed`, so a
-- refusal says which of the two reasons it is rather than looking like a budget problem.
-- 
-- Seven of sixty-six employees are on probation today, so this changes the answer for seven people
-- and leaves it identical for the other fifty-nine.

CREATE OR REPLACE FUNCTION public.fn_check_spend(p_dept text, p_amount numeric, p_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_avail numeric; v_month numeric; v_limit numeric; v_route text; v_afford boolean;
  v_tier text; v_gated boolean := false;
begin
  select coalesce(monthly_aed,0), fn_budget_available(p_dept) into v_month, v_avail
  from department_budget where dept_key = p_dept;

  if v_month is null then
    return jsonb_build_object('ok', false, 'reason',
      'no budget is recorded for department "' || p_dept || '", so no spend can be authorised against it',
      'route_to','finance');
  end if;

  v_afford := coalesce(p_amount,0) <= v_avail;

  select max(threshold_aed) into v_limit
  from employee_authority where agent_key = p_agent;

  -- REPUTATION REACHES THE MOMENT THE MONEY WOULD MOVE.
  -- fn_reputation_recompute already demotes a probation-tier employee's max_tier from 'autonomous'
  -- to 'gated'; until now nothing consulted that at the point of spend, so a demoted employee kept
  -- their nominal ceiling. On probation the personal limit does not apply and the spend goes to a
  -- person — the same decision, applied where it bites.
  select r.tier into v_tier from agent_reputation r where r.agent_key = p_agent;
  if v_tier = 'probation' then v_gated := true; v_limit := 0; end if;

  v_route := case
    when coalesce(p_amount,0) >  10000 then 'founder'
    when coalesce(p_amount,0) >= 1000  then 'brief'
    -- a gated employee is never the approver of their own spend
    when v_gated then 'brief'
    else coalesce(p_agent,'department head') end;

  return jsonb_build_object(
    'ok', v_afford and (v_limit is null or coalesce(p_amount,0) <= v_limit),
    'affordable', v_afford,
    'requested_aed', coalesce(p_amount,0),
    'available_aed', v_avail,
    'monthly_aed', v_month,
    'agent_limit_aed', v_limit,
    'reputation_tier', coalesce(v_tier,'ungraded'),
    'route_to', v_route,
    'reason', case
      when not v_afford then format('Requested AED %s exceeds the AED %s remaining in the %s budget this period. Reduce the scope, defer to next period, or ask Finance to reallocate.', coalesce(p_amount,0), v_avail, p_dept)
      when v_gated then format('Affordable, but %s is on probation in the reputation system, so their personal spending limit does not apply. Route to %s.', coalesce(p_agent,'this employee'), v_route)
      when v_limit is not null and coalesce(p_amount,0) > v_limit then format('Affordable, but AED %s is above %s''s personal limit of AED %s. Route to %s.', coalesce(p_amount,0), p_agent, v_limit, v_route)
      else format('Within budget: AED %s of AED %s available. Approver: %s.', coalesce(p_amount,0), v_avail, v_route) end);
end; $function$
;
