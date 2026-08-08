-- Phase B (autonomy): make the disposition engine policy-driven and broaden safe auto-clear.
-- EXTENDS the existing fn_autonomy_class / fn_autonomy_dispose (hourly) — no replacement.

-- 1. Policy rows in the existing decision_policy rules engine (founder-editable, reversible).
insert into public.decision_policy(key, value, description) values
('action_autonomy',
 jsonb_build_object(
   -- informational / handled by another automation -> auto-clear from the queue, counted in the daily brief
   'licence_expiring','ack','hot_lead','ack','sla_review','ack','sla_no_supply','ack',
   'coverage_gap','ack','supply_gap','ack','supply_health','ack','incident','ack',
   'security_alert','ack','compliance_update','ack','exec_briefing','ack',
   'marketing_recommendation','ack','ops_recommendation','ack','strategy_rec','ack',
   'ai_improvement','ack','ai_quality_alert','ack',
   -- real decisions / money / legal / safety -> always stay in the founder queue
   'approve_supplier','founder','customer_escalation','founder','legal_flag','founder',
   'finance_alert','founder','supplier_risk','founder','prompt_approval','founder',
   'security_incident','founder','content_review','founder','invite_campaign_week','founder'),
 'Per-kind autonomy for the Chief-of-Staff sweep: ack=auto-clear into the daily brief, founder=keep in the queue for a decision. Money/refund/delete/supplier-approval are hard-railed in fn_autonomy_class and cannot be ack-ed here.')
on conflict (key) do update set value=excluded.value, description=excluded.description, updated_at=now();

insert into public.decision_policy(key, value, description) values
('alert_digest_types',
 jsonb_build_array('health_alert','smoke_alert','exception_alert','ops_alert','supply_health',
   'agent_silence','uptime_alert','rfq_sla_breach','ai_quality_alert','doc_expiry',
   'expense_logged','agent_created','policy_inconsistency'),
 'Routine ops-alert notification types folded into the daily brief instead of emailed individually (parked status=digest by trg_notifications_digest). Money/security/legal/critical/founder_alert are hard-excluded regardless.')
on conflict (key) do update set value=excluded.value, description=excluded.description, updated_at=now();

-- 2. Policy-driven classifier. Hard safety rails first (unchanged intent), then policy, then legacy fallback.
create or replace function public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
returns text
language plpgsql
stable
set search_path to 'public','pg_catalog'
as $function$
declare pol jsonb; d text;
begin
  -- HARD RAILS: money, destructive, and supplier approval can never be auto-cleared by policy.
  if p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then return 'founder'; end if;
  if p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then return 'founder'; end if;
  if p_kind='approve_supplier' and coalesce(p_recommendation,'')='approve' then return 'clean_supplier'; end if;
  if p_kind='approve_supplier' then return 'founder'; end if;
  -- POLICY: founder-editable per-kind disposition.
  select value into pol from public.decision_policy where key='action_autonomy';
  d := pol->>p_kind;
  if d in ('ack','founder','keep') then return d; end if;
  -- LEGACY FALLBACK (kinds not in policy): the original auto-clear set.
  if p_kind in ('security_alert','compliance_update','incident','supply_health','sla_no_supply') then return 'ack'; end if;
  return 'keep';
end $function$;
