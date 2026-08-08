-- ---------------------------------------------------------------------------
-- AI spend guard.
--
-- WHY THIS IS URGENT FOR 30 JULY. model_policy holds a complete 26-class routing policy,
-- including budget-aware degradation and a hard halt at 95% of a department's monthly
-- budget. fn_select_model implements all of it correctly. None of it has ever run:
-- ai_cost_log shows task_class IS NULL on 100% of calls over 7 days, because no call site
-- passes taskClass to makeLlm(). Without task_class, _shared/llm.ts skips fn_select_model
-- entirely - so the model choice, the max_tokens cap, the degrade AND THE HALT are all
-- bypassed. Spend is metered but not governed.
--
-- Wiring task_class into every call site means redeploying ~20 functions, which is not a
-- sane thing to do two days before launch. This guard is the zero-deploy protection in the
-- meantime: it cannot stop a call, but it makes runaway spend impossible to miss, which is
-- what actually matters while the founder is doing supplier acquisition off-platform.
--
-- It watches three things, because they fail differently:
--   1. Monthly budget consumption per department (the slow burn)
--   2. Company-wide daily run-rate against the trailing baseline (the autonomy-day spike)
--   3. Projected month-end spend (the trajectory nobody looks at until it lands)
-- ---------------------------------------------------------------------------

create table if not exists ai_spend_probe (
  id             bigint generated always as identity primary key,
  checked_at     timestamptz not null default now(),
  scope          text not null,
  spent_aed      numeric,
  budget_aed     numeric,
  pct            numeric,
  projected_aed  numeric,
  verdict        text not null,
  note           text
);
alter table ai_spend_probe enable row level security;
revoke all on ai_spend_probe from public, anon, authenticated;

create or replace function fn_ai_spend_guard()
returns table (scope text, verdict text, pct numeric, note text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
begin
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
                  'governance_gap', 'model_policy degrade/halt is NOT enforced: task_class is null on every call, so fn_select_model never runs. This alert is currently the only ceiling.'),
                'ai_spend_guard');
        insert into founder_alerts (level, event, detail, channel)
        values (case when v_verdict='HALT' then 'crit' else 'warn' end, 'ai_spend_' || lower(replace(v_verdict,' ','_')),
                v_note || ' NOTE: the automatic budget halt in fn_select_model does not currently fire, because no call site passes task_class. Treat this alert as the ceiling.', 'system');
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
  values ('company_daily', v_today, v_baseline, case when v_baseline>0 then round(v_today/v_baseline,2) else null end, v_verdict, v_note);

  scope := 'company_daily'; verdict := v_verdict;
  pct := case when v_baseline>0 then round(v_today/v_baseline,2) else null end;
  note := v_note;
  return next;
end $$;

revoke execute on function fn_ai_spend_guard() from public, anon, authenticated;

insert into app_secrets (key, value)
select 'ai_spend_spike_multiple', '5.0'
where not exists (select 1 from app_secrets where key='ai_spend_spike_multiple');

comment on function fn_ai_spend_guard() is
  'Zero-deploy ceiling on AI spend while model_policy degrade/halt remains unenforced (task_class is null on every call, so fn_select_model never runs). Watches per-department consumption, month-end projection, and company-wide daily run-rate spikes. Added 28 Jul 2026 ahead of the autonomy switch.';