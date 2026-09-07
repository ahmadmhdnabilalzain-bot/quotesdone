-- THE COMPANY SPENDS 85% OF ITS THINKING ON ITSELF AND 0.04% ON EARNING, AND NOTHING NOTICED.
--
-- Measured on production 2026-08-11 via fn_cost_per_os(30) - the first time this number has
-- existed. 143.75 AED floor over 30 days:
--
--   leadership      122.69 AED   85.4%   1,121 calls    the OS that reasons about the company
--   (unattributed)   16.41 AED   11.4%     658 calls
--   operations        4.59 AED    3.2%     464 calls
--   marketplace       0.06 AED    0.0%      40 calls    the OS that is supposed to earn AED 1,000,000
--   technology        0.003 AED   0.0%       2 calls
--
-- Revenue over the same window: 0.
--
-- THE POINT IS NOT THE RATIO. A company with no customers legitimately spends its time on internal
-- work, and I am not asserting the split is wrong - that is a judgement about strategy. The point is
-- that NOTHING IN THE COMPANY COULD SEE IT. The founder's standard requires that the company
-- "IDENTIFY PROBLEMS" itself, and a concentration this extreme, against a revenue target of
-- AED 1,000,000 by August 2027 with revenue at zero, is the single largest thing its own books had
-- to say and there was no reader.
--
-- So this is a routine and not a note from me. A one-off observation written by whoever happened to
-- look is exactly the failure mode the standard exists to end.
--
-- WHY THE THRESHOLDS ARE WHAT THEY ARE, STATED so they can be argued with rather than trusted:
--   - It only fires when trailing revenue is BELOW target. A company that is earning has bought the
--     right to spend its thinking wherever it likes.
--   - 5% is the earning-side floor. Not a target - a floor low enough that crossing it below it is
--     not a matter of taste. At 0.04% today it is off by two orders of magnitude.
--   - It files ONE open task at a time. A weekly routine that files a duplicate every Monday is
--     noise, and noise is how a real finding gets ignored.

create or replace function public.fn_spend_concentration_check()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_report jsonb; v_total numeric; v_earning numeric := 0; v_pct numeric;
  v_revenue numeric; v_target numeric; v_task bigint; v_title text; v_owner text;
begin
  v_report := public.fn_cost_per_os(30);
  v_total  := (v_report->>'total_cost_aed')::numeric;

  -- The OSes that face a paying customer. marketplace runs the RFQ chain, commercial brings demand.
  select coalesce(sum((e->>'cost_aed')::numeric), 0) into v_earning
    from jsonb_array_elements(v_report->'by_os') e
   where e->>'os_key' in ('marketplace','commercial');

  v_pct := case when coalesce(v_total,0) > 0 then round(100.0 * v_earning / v_total, 2) else null end;

  select p.actual_value, g.target_value into v_revenue, v_target
    from company_goals g
    left join goal_period p on p.goal_key = g.key and p.actual_value is not null
   where g.key = 'revenue_annual'
   order by p.updated_at desc nulls last limit 1;

  -- Earning its way out of the question: no finding while revenue is at or above target.
  if coalesce(v_revenue, 0) >= coalesce(v_target, 1000000) then
    return jsonb_build_object('ok', true, 'fired', false, 'reason', 'revenue at or above target',
                              'earning_os_pct', v_pct, 'revenue', v_revenue);
  end if;

  if v_pct is null or v_pct >= 5.0 then
    return jsonb_build_object('ok', true, 'fired', false, 'reason', 'earning-side share at or above the 5% floor',
                              'earning_os_pct', v_pct, 'total_cost_aed', v_total);
  end if;

  v_title := 'AI spend is concentrated away from the OS that earns revenue';
  if exists (select 1 from org_tasks where title = v_title and status <> 'done') then
    return jsonb_build_object('ok', true, 'fired', false, 'reason', 'an open task already carries this finding',
                              'earning_os_pct', v_pct);
  end if;

  select agent_key into v_owner from org_agents
   where active and agent_key = 'ai_director' limit 1;

  insert into org_tasks (dept_key, assigned_agent, title, detail, status, tier, needs_founder, action_class)
  values ('ai_dept', v_owner, v_title,
    'Measured by fn_cost_per_os over 30 days. Of ' || round(coalesce(v_total,0),2) ||
    ' AED spent on model calls, the revenue-earning operating systems (marketplace, commercial) '
    || 'received ' || round(v_earning,4) || ' AED = ' || v_pct || '%, against a floor of 5%. '
    || 'Trailing revenue is ' || coalesce(v_revenue,0) || ' against a target of '
    || coalesce(v_target,1000000) || ' AED. '
    || 'This is not an assertion that the split is wrong - a company with no customers may rightly '
    || 'think about itself. It is the observation that the company had no way to see it. '
    || 'Decide deliberately: either shift capacity toward demand and quoting, or record why the '
    || 'internal work is the faster route to revenue. Do not close this without one or the other. '
    || 'Full breakdown: ' || (v_report->'by_os')::text,
    'proposed', 'advisory', false, 'recommend')
  returning id into v_task;

  return jsonb_build_object('ok', true, 'fired', true, 'task_id', v_task,
                            'earning_os_pct', v_pct, 'total_cost_aed', v_total,
                            'assigned_agent', v_owner);
end $function$;

revoke all on function public.fn_spend_concentration_check() from public;
revoke all on function public.fn_spend_concentration_check() from anon;

-- Mondays 03:40, after the KPI measures at 03:25/03:30 and before the KPI review at 04:00, so the
-- finding is on the table in the same cycle that reviews everything else.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
