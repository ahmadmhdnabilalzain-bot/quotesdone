-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709100608   name: operations_kpis_and_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- consolidated operations rollup: queues + SLAs + approvals + automation health + failures + performance
create or replace view public.ops_kpis as
with m as (select fn_ops_metrics() j)
select
  (j->>'open_rfqs_no_quotes_7d')::int as no_quote_backlog,
  (j->>'matched_not_quoted')::int as matched_not_quoted,
  (j->>'avg_first_quote_hours')::numeric as avg_first_quote_hours,
  (j->>'response_rate_pct')::numeric as response_rate_pct,
  (j->>'overdue_activities')::int as overdue_activities,
  (select count(*) from agent_actions where status in ('pending','needs_review')) as pending_approvals,
  (select count(*) from agent_actions where status in ('pending','needs_review') and coalesce(risk,'') in ('high','critical')) as high_risk_pending,
  (select count(*) from crm_tasks where coalesce(status,'')<>'done') as open_tasks,
  (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()) as overdue_tasks,
  (select count(*) from inquiries where status='quoted' and not exists(select 1 from transactions t where t.inquiry_id=inquiries.id and t.revealed_at is not null)) as awaiting_reveal,
  (select count(*) from cron.job) as cron_jobs,
  (select count(*) from cron.job_run_details where status<>'succeeded' and start_time>=now()-interval '24 hours') as cron_failures_24h,
  (select count(*) from agent_runs where status in ('error','failed') and started_at>=now()-interval '24 hours') as agent_errors_24h,
  (select count(*) from error_events where created_at>=now()-interval '24 hours') as app_errors_24h,
  (select count(*) from agent_actions where kind in ('incident','security_incident') and status in ('pending','needs_review')) as open_incidents
from m;
revoke all on public.ops_kpis from anon, authenticated;

create table if not exists public.ops_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date, kpis jsonb not null, created_at timestamptz not null default now()
);
create unique index if not exists ops_kpi_snap_day on public.ops_kpi_snapshots(snapshot_date);
revoke all on public.ops_kpi_snapshots from anon, authenticated;

create or replace function public.ops_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='ops_recommendation' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('operations_ai','ops_recommendation','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'operations',p_sig);
  end if;
end $$;
revoke all on function public.ops_rec(text,boolean,text,text,text) from anon, authenticated, public;

create or replace function public.fn_operations_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare k record; v_health numeric; n int;
begin
  select * into k from ops_kpis;
  v_health := round(greatest(0, 100
    - least(30, coalesce(k.no_quote_backlog,0)*3)
    - (case when coalesce(k.avg_first_quote_hours,0) > 72 then 20 when coalesce(k.avg_first_quote_hours,0) > 48 then 10 else 0 end)
    - (case when coalesce(k.response_rate_pct,100) < 40 then 15 when coalesce(k.response_rate_pct,100) < 60 then 7 else 0 end)
    - least(15, coalesce(k.overdue_tasks,0)*3)
    - coalesce(k.cron_failures_24h,0)*4
    - least(10, coalesce(k.agent_errors_24h,0)*2)
    - (case when coalesce(k.high_risk_pending,0) > 5 then 8 else 0 end)),1);

  insert into ops_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('ops_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform ops_rec('no_quote_backlog', coalesce(k.no_quote_backlog,0) > 0, 'medium', 'Inquiries stuck without quotes',
    k.no_quote_backlog||' inquir(y/ies) older than 7 days have no quotes — a supply/response bottleneck. Chase matched suppliers or onboard supply in those categories.');
  perform ops_rec('slow_first_quote', coalesce(k.avg_first_quote_hours,0) > 48, 'medium', 'First quotes are slow',
    'First quotes are averaging '||coalesce(k.avg_first_quote_hours,0)||' hours. Tighten supplier response SLAs / nudges to speed the funnel.');
  perform ops_rec('low_response_rate', coalesce(k.response_rate_pct,100) < 60, 'medium', 'Supplier response rate is low',
    'Supplier response rate is '||coalesce(k.response_rate_pct,0)||'%. Improve matching quality and supplier enablement.');
  perform ops_rec('approvals_backlog', coalesce(k.pending_approvals,0) > 15, 'low', 'Approval queue building up',
    k.pending_approvals||' items are awaiting your decision ('||coalesce(k.high_risk_pending,0)||' high-risk). Clear the queue so the agents can proceed.');
  perform ops_rec('overdue_tasks', coalesce(k.overdue_tasks,0) > 0, 'low', 'Overdue tasks',
    k.overdue_tasks||' task(s) are past due. Reschedule or action them.');
  perform ops_rec('automation_failures', coalesce(k.cron_failures_24h,0) > 0 or coalesce(k.agent_errors_24h,0) > 5, 'high', 'Automation failures detected',
    coalesce(k.cron_failures_24h,0)||' scheduled-job failure(s) and '||coalesce(k.agent_errors_24h,0)||' agent error(s) in 24h. Investigate the failing jobs.');

  select count(*) into n from agent_actions where agent='operations_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ops_health',v_health,'kpis',to_jsonb(k),'open_recommendations',n);
end $fn$;
revoke all on function public.fn_operations_ai() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('operations_ai','Operations AI','⚙️',true,
  'Runs the company''s day-to-day operations. Monitors queues (inquiries without quotes, matched-not-quoted, approvals, tasks, awaiting-reveal), SLAs (first-quote time, supplier response rate), approvals backlog, automation health (scheduled jobs + agent runs), failures (app/agent errors, open incidents) and workflow performance; scores operations health and produces a daily operations picture with recommendations to clear bottlenecks. It surfaces and recommends — it does not move money or take irreversible action on its own.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('operations_ai_daily','45 4 * * *', $$select public.fn_operations_ai();$$);
