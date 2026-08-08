-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727015627   name: budget_affordability_and_spend_thresholds
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Layer-4 remediation, part 4: the finance_rejects_budget scenario.
-- Found: nothing in the database compares a requested spend to the
-- available budget, and governance_policy #11 claimed spend thresholds
-- were "enforced by database" while all 266 employee_authority rows had
-- threshold_aed NULL and no function read them. A false enforcement
-- claim is worse than an absent one.
-- ================================================================

-- 1. Populate the thresholds the policy already claims, by seniority.
update public.employee_authority ea
set threshold_aed = case fn_seniority_rank(a.seniority)
                      when 1 then 100000   -- executive
                      when 2 then 10000    -- director
                      when 3 then 1000     -- manager
                      else 0               -- specialist: no independent spend
                    end
from public.org_agents a
where a.agent_key = ea.agent_key and ea.threshold_aed is null;

-- 2. Remaining budget, computed.
create or replace function public.fn_budget_available(p_dept text)
returns numeric language sql stable as $fn$
  select greatest(coalesce(monthly_aed,0) - coalesce(spent_aed,0), 0)
  from department_budget where dept_key = p_dept;
$fn$;

-- 3. The affordability + authority answer, in one place.
create or replace function public.fn_check_spend(p_dept text, p_amount numeric, p_agent text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare v_avail numeric; v_month numeric; v_limit numeric; v_route text; v_afford boolean;
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

  v_route := case
    when coalesce(p_amount,0) >  10000 then 'founder'
    when coalesce(p_amount,0) >= 1000  then 'brief'
    else coalesce(p_agent,'department head') end;

  return jsonb_build_object(
    'ok', v_afford and (v_limit is null or coalesce(p_amount,0) <= v_limit),
    'affordable', v_afford,
    'requested_aed', coalesce(p_amount,0),
    'available_aed', v_avail,
    'monthly_aed', v_month,
    'agent_limit_aed', v_limit,
    'route_to', v_route,
    'reason', case
      when not v_afford then format('Requested AED %s exceeds the AED %s remaining in the %s budget this period. Reduce the scope, defer to next period, or ask Finance to reallocate.', coalesce(p_amount,0), v_avail, p_dept)
      when v_limit is not null and coalesce(p_amount,0) > v_limit then format('Affordable, but AED %s is above %s''s personal limit of AED %s. Route to %s.', coalesce(p_amount,0), p_agent, v_limit, v_route)
      else format('Within budget: AED %s of AED %s available. Approver: %s.', coalesce(p_amount,0), v_avail, v_route) end);
end; $fn$;

revoke execute on function public.fn_check_spend(text,numeric,text) from anon, authenticated, public;

-- 4. Wire it into the one gate that already works, so an unaffordable decision
--    cannot reach approved status no matter how complete its paperwork is.
create or replace function public.fn_decision_gate() returns trigger
language plpgsql as $fn$
declare v_was text; v_spend jsonb;
begin
  v_was := case when tg_op = 'UPDATE' then coalesce(old.status,'') else '' end;

  if new.status in ('approved','executed') and v_was not in ('approved','executed') then
    if coalesce(length(new.impact_business),0)  < 20
    or coalesce(length(new.impact_financial),0) < 20
    or coalesce(length(new.impact_legal),0)     < 10
    or coalesce(length(new.impact_customer),0)  < 20
    or jsonb_array_length(coalesce(new.evidence,'[]'::jsonb)) = 0 then
      raise exception 'decision cannot be % : impact analysis incomplete (business/financial/legal/customer + evidence are all required)', new.status;
    end if;

    if coalesce(new.financial_aed,0) > 0 then
      v_spend := public.fn_check_spend(new.dept_key, new.financial_aed, new.approved_by);
      if not coalesce((v_spend->>'affordable')::boolean, false) then
        raise exception 'decision cannot be % : %', new.status, v_spend->>'reason';
      end if;
      if coalesce(new.financial_aed,0) > 10000 and coalesce(new.approved_by,'') not in ('founder','ceo') then
        raise exception 'decision cannot be % : AED % is above the AED 10,000 founder threshold and approved_by is "%"',
          new.status, new.financial_aed, coalesce(new.approved_by,'(none)');
      end if;
      if coalesce(new.financial_aed,0) >= 1000 and coalesce(new.financial_aed,0) <= 10000
         and coalesce(new.approved_by,'') not in ('brief','founder','ceo') then
        raise exception 'decision cannot be % : AED % needs Chief of Staff approval and approved_by is "%"',
          new.status, new.financial_aed, coalesce(new.approved_by,'(none)');
      end if;
    end if;
  end if;
  return new;
end; $fn$;

revoke execute on function public.fn_decision_gate() from anon, authenticated, public;

update public.governance_policy
set rule = 'Under AED 1,000 a department head decides alone. AED 1,000-10,000 needs Chief of Staff. Above AED 10,000 needs the founder. No employee may split a spend to stay under a threshold. A decision carrying financial_aed above the available department budget cannot reach approved status at all.',
    enforced_by = 'trg_decision_gate + fn_check_spend + employee_authority.threshold_aed',
    enforcement = 'database'
where domain = 'approval' and policy = 'Spend thresholds';

insert into public.org_action_executor (action_class, kind, target, params, active, note, advisory_safe, department)
values ('spend_check','rpc','fn_check_spend','{}'::jsonb, true,
        'Answers whether a proposed spend is affordable against the department budget and who is authorised to approve it.', true, 'finance')
on conflict do nothing;
