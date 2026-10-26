-- ROW #3 — the daily company snapshot records everything about the company except its customers.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   time-machine-restores-six-dimensions  MISSING  5 of 6 dimensions are non-null on ALL 12
--                                                  snapshot(s) of the last 14 days
-- 
-- The one missing dimension is CUSTOMERS. company_snapshot.state carries 24 keys — employees,
-- revenue, knowledge, decisions, KPIs, indices, os_health, departments — and not one of them
-- matches customer or buyer. A time machine that restores the company as it was, minus its
-- customer base, is not restoring the company.
-- 
-- ── ZERO IS A MEASUREMENT ───────────────────────────────────────────────────────────────────────
-- public.customers holds 0 rows today and all 7 inquiries carry a null customer_id. Recording that
-- is not fabrication — it is the fact, and it is the single most important fact about this
-- marketplace's current state. The value of writing it down daily is precisely that the day it
-- stops being zero, the snapshot shows exactly when.
-- 
-- Two keys rather than one, because they answer different questions: how many customers exist, and
-- how many inquiries actually reached one. Today they are 0 and 0 and they will diverge the moment
-- inquiry_intake creates its first record.
-- 
-- ── IT DOES NOT FLIP ON DEPLOY, AND THAT IS CORRECT ─────────────────────────────────────────────
-- The check is a per-dimension universal over EVERY snapshot in the last 14 days, so it turns green
-- 14 days after the writer changes, not tonight. Back-filling the key into the 12 existing rows
-- would be editing history to turn a gate green, and those snapshots genuinely did not record it.

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
    'invite_enabled',   (select value from app_secrets where key='invite_enabled'));

  insert into company_snapshot (snapshot_on, state) values (current_date, s)
  on conflict (snapshot_on) do update set state=excluded.state, created_at=now();

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_snapshot',now(),now(),'ok',jsonb_build_object('keys',(select count(*) from jsonb_object_keys(s))),
    'Company state snapshotted for '||current_date||'. Any past day can now be reconstructed.');
  return s;
end $function$
;
