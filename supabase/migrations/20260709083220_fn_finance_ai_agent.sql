-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709083220   name: fn_finance_ai_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- de-dupe helper: one open finance alert per signal
create or replace function public.fin_alert(p_sig text, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if not exists (select 1 from agent_actions where kind='finance_alert' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('finance_ai','finance_alert','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'finance',p_sig);
  end if;
end $$;
revoke all on function public.fin_alert(text,text,text,text) from anon, authenticated, public;

create or replace function public.fn_finance_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare k record; fc jsonb; v_health numeric; n_esc int;
  s_run numeric; s_prof numeric; s_coll numeric; s_bud numeric;
begin
  select * into k from finance_kpis;
  fc := fn_finance_forecast();

  s_run := case when k.runway_months is null then (case when k.cash>0 then 80 else 10 end)
                when k.runway_months>=6 then 100 when k.runway_months>=3 then 70 when k.runway_months>=1 then 40 else 10 end;
  s_prof := case when k.net_income>0 then 100 when k.margin_pct is null then 50 else greatest(10, least(100, 60 + k.margin_pct/5)) end;
  s_coll := coalesce(k.collection_rate, 70);
  s_bud := greatest(0, 100 - coalesce(k.budget_overruns,0)*20);
  v_health := round(s_run*0.35 + s_prof*0.25 + s_coll*0.20 + s_bud*0.20, 1);

  insert into finance_kpi_snapshots(snapshot_date, kpis, forecast)
  values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health), fc)
  on conflict (snapshot_date) do update set kpis=excluded.kpis, forecast=excluded.forecast, created_at=now();

  -- ESCALATIONS to founder (never auto-resolved; agent never moves money)
  if k.cash <= 0 then
    perform fin_alert('cash_negative','high','Book cash is negative',
      'Book cash is '||to_char(k.cash,'FM999999990.00')||' AED and owner capital is 0. Record a capital injection or fund operations to restore a positive position.');
  elsif k.runway_months is not null and k.runway_months < 3 then
    perform fin_alert('low_runway','high','Low cash runway',
      'Runway is ~'||k.runway_months||' months at the current burn. Increase revenue, cut spend, or add capital.');
  end if;
  if k.ar_overdue > 0 then
    perform fin_alert('ar_overdue', case when k.ar_overdue>=500 then 'high' else 'medium' end, 'Overdue collections',
      'AED '||to_char(k.ar_overdue,'FM999999990.00')||' in supplier commission is overdue. Reminders are automated; review whether to escalate or apply fines.');
  end if;
  if k.ap_overdue > 0 then
    perform fin_alert('ap_overdue','high','Overdue bills to pay',
      'AED '||to_char(k.ap_overdue,'FM999999990.00')||' in supplier bills is overdue. Review and pay — money movement is yours to action.');
  end if;
  if coalesce(k.budget_overruns,0) > 0 then
    perform fin_alert('budget_overrun','medium','Budget overrun',
      k.budget_overruns||' expense budget line(s) are over 110% of plan. Review spend or re-budget.');
  end if;

  select count(*) into n_esc from agent_actions where agent='finance_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'forecast',fc,'open_alerts',n_esc);
end $fn$;
revoke all on function public.fn_finance_ai() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('finance_ai','Finance AI','💰',true,
  'Manages financial operations: revenue, expenses, invoices, outstanding balances, collections, profit, forecast and budgets. Tracks KPIs (cash flow, revenue, profit, collection rate, outstanding balances), scores finance health, and builds a 30/60/90 cash-flow + revenue forecast. Escalates low runway/negative cash, overdue collections, overdue bills and budget overruns to the founder. NEVER pays bills, issues refunds, or moves money on its own — money movement is always the founder''s to action.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('finance_ai_daily','20 4 * * *', $$select public.fn_finance_ai();$$);
