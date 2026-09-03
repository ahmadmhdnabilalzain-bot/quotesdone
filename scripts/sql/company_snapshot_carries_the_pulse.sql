-- THE COMPANY SNAPSHOT CARRIES THE PULSE (3 Sep 2026).
--
-- docs/UPGRADE_PLAN.md §2.1 asked for one screen that tells the founder the truth: department scores,
-- agent health, cron liveness, open dead-letters, throughput, revenue-to-target, the refund queue.
-- fn_company_snapshot() already composes most of it and is written daily into company_snapshot, so
-- the plan's v_company_pulse is not a new object — it is this function carrying the six signals it
-- lacked: crons that never fire (v_cron_stale), open dead letters, failed and skipped runs in the last
-- day, actions parked behind the paid-model hold, alerts that actually reached him, and the ad money
-- (active campaigns, active daily budget against the ceiling, pending decisions, whether the Meta
-- token exists). Every figure comes from an instrument that already exists; nothing here is estimated.
--
-- The definition below is the live routine with those keys added; snapshot_carries_customers.sql
-- stays in the manifest above this one and this file is canonical.

CREATE OR REPLACE FUNCTION public.fn_company_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb;
begin
  s := jsonb_build_object(
    'employees',        (select count(*) from org_agents where active),
    -- THE CUSTOMER BASE, which the snapshot has never recorded. Zero is the measurement today —
    -- 0 customers and 0 inquiries carrying one — and writing it down daily is what makes the day
    -- it stops being zero visible in the replay.
    'customers',              (select count(*) from customers),
    'customers_with_inquiry', (select count(distinct customer_id) from inquiries where customer_id is not null),
    'departments',      (select count(*) from org_departments where active),
    'operating_systems',(select count(*) from operating_system where active),
    'kpis',             (select count(*) from employee_kpi where active),
    'kpis_measurable',  (select count(*) from employee_kpi where active and measure_sql is not null),
    'kpi_gaps_open',    (select count(*) from org_tasks where title like 'KPI missed:%' and status<>'done'),
    'open_tasks',       (select count(*) from org_tasks where status<>'done'),
    'needs_founder',    (select count(*) from org_tasks where status<>'done' and needs_founder),
    'approved_suppliers',(select count(*) from leads where approval_status='approved'),
    'sendable_pool',    (select coalesce(sum(sendable),0) from v_supply_gap),
    'categories_at_target',(select count(*) from v_supply_gap where approved>=10),
    'revenue_30d_aed',  (select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) from transactions where revealed_at>now()-interval '30 days'),
    'ai_cost_30d_aed',  (select round(coalesce(sum(cost_aed),0),2) from ai_cost_log where occurred_at>now()-interval '30 days'),
    'knowledge_items',  (select count(*) from agent_knowledge),
    'knowledge_quarantined',(select count(*) from agent_knowledge where validation_status='quarantined'),
    'outcomes_pending', (select count(*) from outcome_record where verdict='pending'),
    'outcomes_improved',(select count(*) from outcome_record where verdict='improved'),
    'decisions_7d',     (select count(*) from decision_log where created_at>now()-interval '7 days'),
    'agent_runs_7d',    (select count(*) from agent_runs where started_at>now()-interval '7 days'),
    'error_rate_7d',    (select round(100.0*count(*) filter (where status='error')/nullif(count(*),0),2) from agent_runs where started_at>now()-interval '7 days'),
    'os_health',        (select jsonb_object_agg(os_key,health) from os_review where period=to_char(now(),'IYYY-"W"IW')),
    'indices',          (select jsonb_object_agg(index_name,score) from company_index where measured_on=current_date),
    'autonomy_enabled', (select value from app_secrets where key='agent_autonomy_enabled'),
    'invite_enabled', (select value from app_secrets where key='invite_enabled'),
      -- THE PULSE (3 Sep 2026): the signals the founder's one screen lacked, from the instruments that
      -- already measure them. Liveness (a cron that never fires), what is dead-lettered, what failed in
      -- the last day, what is parked behind the paid-model hold, what paged him, and the ad money.
      'crons_stale',        (select coalesce(jsonb_agg(jobname order by jobname), '[]'::jsonb) from public.v_cron_stale),
      'dead_letters_open',  (select count(*) from public.dead_letter where resolved_at is null),
      'failed_runs_24h',    (select count(*) from public.agent_runs where status = 'error' and started_at > now() - interval '24 hours'),
      'runs_skipped_24h',   (select count(*) from public.agent_runs where status = 'skipped' and started_at > now() - interval '24 hours'),
      'actions_held',       (select count(*) from public.action_execution where status = 'held'),
      'founder_alerts_24h', (select count(*) from public.founder_alerts where channel in ('email','whatsapp') and created_at > now() - interval '24 hours'),
      'ad_spend', jsonb_build_object(
        'active_campaigns', (select count(*) from public.ad_campaign_state where not is_demo and status = 'ACTIVE'),
        'active_daily_aed', (select coalesce(sum(daily_budget_aed), 0) from public.ad_campaign_state where not is_demo and status = 'ACTIVE'),
        'daily_ceiling_aed', public.fn_ad_spend_daily_ceiling(),
        'decisions_pending', (select count(*) from public.ad_decision where executed_at is null),
        'meta_token_present', exists (select 1 from app_secrets where key = 'meta_access_token' and coalesce(value, '') <> '')));

  insert into company_snapshot (snapshot_on, state) values (current_date, s)
  on conflict (snapshot_on) do update set state=excluded.state, created_at=now();

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_snapshot',now(),now(),'ok',jsonb_build_object('keys',(select count(*) from jsonb_object_keys(s))),
    'Company state snapshotted for '||current_date||'. Any past day can now be reconstructed.');
  return s;
end $function$
;
