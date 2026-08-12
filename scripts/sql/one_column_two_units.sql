-- ai_spend_probe.pct carried two different units in one column.
--
-- Department rows wrote round(100 * spent / monthly_aed, 2) - a PERCENTAGE. The company_daily row
-- wrote round(today / trailing_baseline, 2) - a MULTIPLE, so 1.09 meant 109%. Same table, same
-- column, same reader. No decision was wrong today because nothing reads this table yet (checked:
-- no pg_proc body and no file under supabase/functions or src references it), which is exactly
-- when to fix it - before the first reader averages a percentage with a ratio.
--
-- company_daily now writes the percentage too, so pct is always 100 * spent_aed / budget_aed.
-- The multiple is still stated in words in note ('1.4x the baseline'), which is where a human
-- reads it. budget_aed on that row remains the trailing daily average: it is the comparison base,
-- not a budget, and that is what the scope name says.
-- Definition otherwise byte-identical to production on 13 Aug 2026.

CREATE OR REPLACE FUNCTION public.fn_ai_spend_guard()
 RETURNS TABLE(scope text, verdict text, pct numeric, note text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r             record;
  v_month_start date := date_trunc('month', now())::date;
  v_day_of      numeric := greatest(extract(day from now())::numeric, 1);
  v_days_in     numeric := extract(day from (date_trunc('month', now()) + interval '1 month - 1 day'))::numeric;
  v_today       numeric;
  v_baseline    numeric;
  v_spike       numeric := coalesce((select nullif(value,'')::numeric from app_secrets where key='ai_spend_spike_multiple'), 5.0);
  v_verdict     text;
  v_note        text;
  v_proj        numeric;
  v_blind_pct   numeric;
begin
  -- HOW MUCH OF THIS MONTH'S SPEND THE AUTOMATIC HALT CANNOT SEE. fn_ai_route enforces the ceiling
  -- by looking up department_budget for the call's dept_key; a call logged without one has no
  -- budget to be measured against and cannot be halted. Measured here rather than asserted, because
  -- the sentence this feeds used to be a hardcoded claim that went stale.
  select round(100.0 * count(*) filter (where dept_key is null) / nullif(count(*), 0), 1)
    into v_blind_pct
    from ai_cost_log where occurred_at >= v_month_start;
  v_blind_pct := coalesce(v_blind_pct, 0);

  -- ---- 1 & 3: per-department consumption and month-end projection ----
  for r in
    select b.dept_key, b.monthly_aed, b.degrade_at_pct, b.halt_at_pct,
           coalesce((select sum(l.cost_aed) from ai_cost_log l
                      where l.dept_key = b.dept_key and l.occurred_at >= v_month_start), 0) as spent
    from department_budget b
    where b.monthly_aed > 0
  loop
    pct  := round(100 * r.spent / r.monthly_aed, 2);
    v_proj := round(r.spent / v_day_of * v_days_in, 2);

    if pct >= r.halt_at_pct then
      v_verdict := 'HALT';
      v_note := r.dept_key || ' has spent ' || round(r.spent,2) || ' of ' || r.monthly_aed
             || ' AED (' || pct || '%), at or past its halt threshold of ' || r.halt_at_pct || '%.';
    elsif pct >= r.degrade_at_pct then
      v_verdict := 'DEGRADE';
      v_note := r.dept_key || ' has spent ' || round(r.spent,2) || ' of ' || r.monthly_aed
             || ' AED (' || pct || '%), past its degrade threshold of ' || r.degrade_at_pct || '%.';
    elsif v_proj > r.monthly_aed then
      v_verdict := 'PROJECTED OVER';
      v_note := r.dept_key || ' is at ' || pct || '% on day ' || v_day_of || ', but the current run-rate projects '
             || v_proj || ' AED by month end against a ' || r.monthly_aed || ' AED budget.';
    else
      v_verdict := 'OK';
      v_note := r.dept_key || ': ' || round(r.spent,2) || '/' || r.monthly_aed || ' AED (' || pct
             || '%), projecting ' || v_proj || ' AED.';
    end if;

    insert into ai_spend_probe (scope, spent_aed, budget_aed, pct, projected_aed, verdict, note)
    values (r.dept_key, r.spent, r.monthly_aed, pct, v_proj, v_verdict, v_note);

    if v_verdict <> 'OK' then
      if not exists (select 1 from os_incidents
                      where status='open' and kind='ai_spend' and detail->>'scope' = r.dept_key) then
        insert into os_incidents (title, kind, severity, status, detail, opened_by)
        values (left('AI spend ' || v_verdict || ': ' || r.dept_key, 300), 'ai_spend',
                case when v_verdict='HALT' then 'high' else 'medium' end, 'open',
                jsonb_build_object('scope', r.dept_key, 'spent_aed', round(r.spent,2),
                  'budget_aed', r.monthly_aed, 'pct', pct, 'projected_aed', v_proj,
                  'verdict', v_verdict,
                  'halt_enforcement', 'The automatic halt IS enforced, by fn_ai_route inside ai_gateway: it compares month-to-date dept spend against department_budget.halt_at_pct and returns use_llm=false, which the gateway refuses as budget_halted. It can only act on calls that carry a dept_key; ' || v_blind_pct || '% of this month''s logged calls do not, and that share is outside the ceiling.'),
                'ai_spend_guard');
        insert into founder_alerts (level, event, detail, channel)
        values (case when v_verdict='HALT' then 'crit' else 'warn' end, 'ai_spend_' || lower(replace(v_verdict,' ','_')),
                v_note || ' The automatic halt is enforced by fn_ai_route in ai_gateway and stops non-gated work for a department at its halt_at_pct. It cannot see calls logged without a dept_key: ' || v_blind_pct || '% of this month''s calls, which remain outside the ceiling.', 'system');
      end if;
    else
      update os_incidents set status='resolved', resolved_at=now(), resolved_by='ai_spend_guard',
             resolution = 'Back within budget: ' || v_note
       where status='open' and kind='ai_spend' and detail->>'scope' = r.dept_key;
    end if;

    scope := r.dept_key; verdict := v_verdict; note := v_note;
    return next;
  end loop;

  -- ---- 2: company-wide daily run-rate spike ----
  select coalesce(sum(cost_aed),0) into v_today
    from ai_cost_log where occurred_at >= current_date;
  select coalesce(avg(d),0) into v_baseline from (
    select sum(cost_aed) d from ai_cost_log
    where occurred_at >= current_date - interval '7 days' and occurred_at < current_date
    group by date_trunc('day', occurred_at)
  ) x;

  if v_baseline > 0 and v_today > v_baseline * v_spike then
    v_verdict := 'SPIKE';
    v_note := 'Company AI spend today is ' || round(v_today,2) || ' AED against a trailing daily average of '
           || round(v_baseline,2) || ' AED - ' || round(v_today / v_baseline, 1)
           || 'x the baseline. Autonomy multiplies call volume; check what started.';
    if not exists (select 1 from os_incidents where status='open' and kind='ai_spend' and detail->>'scope'='company_daily') then
      insert into os_incidents (title, kind, severity, status, detail, opened_by)
      values (left('AI spend SPIKE: ' || round(v_today/v_baseline,1) || 'x the daily baseline', 300),
              'ai_spend', 'high', 'open',
              jsonb_build_object('scope','company_daily','today_aed',round(v_today,2),
                'baseline_aed',round(v_baseline,2),'multiple',round(v_today/v_baseline,1),
                'threshold_multiple', v_spike), 'ai_spend_guard');
      insert into founder_alerts (level, event, detail, channel)
      values ('crit','ai_spend_spike', v_note, 'system');
    end if;
  else
    v_verdict := 'OK';
    v_note := 'Company AI spend today ' || round(v_today,2) || ' AED against a ' || round(v_baseline,2) || ' AED trailing daily average.';
    update os_incidents set status='resolved', resolved_at=now(), resolved_by='ai_spend_guard',
           resolution = v_note
     where status='open' and kind='ai_spend' and detail->>'scope'='company_daily';
  end if;

  insert into ai_spend_probe (scope, spent_aed, budget_aed, pct, verdict, note)
  values ('company_daily', v_today, v_baseline, case when v_baseline>0 then round(100*v_today/v_baseline,2) else null end, v_verdict, v_note);

  scope := 'company_daily'; verdict := v_verdict;
  pct := case when v_baseline>0 then round(100*v_today/v_baseline,2) else null end;
  note := v_note;
  return next;
end $function$
;
