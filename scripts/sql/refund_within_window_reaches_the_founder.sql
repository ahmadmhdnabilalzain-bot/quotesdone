-- APV-01 (money safety). fn_autonomy_class carved 'refund_within_window' out to 'ack' (auto-clear)
-- BEFORE the money hard-rail, on a 2026-07-24 "a refund inside the policy window is routine" doctrine.
-- The founder's 2026-08-17 ruling supersedes it and is absolute: EVERY refund at any amount reaches
-- him. This removes the carve-out so refund_within_window falls straight into the money rail ->
-- 'founder'. No refund class can auto-clear anymore.
--
--   node scripts/apply_sql.mjs scripts/sql/refund_within_window_reaches_the_founder.sql --apply --ddl

create or replace function public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
 returns text
 language plpgsql
 stable
 set search_path to 'public', 'pg_catalog'
as $function$
declare pol jsonb; d text;
begin
  -- SUPERSEDED 2026-09-02: the 2026-07-24 "refund within the policy window is routine work" carve-out
  -- ('refund_within_window' -> 'ack') is removed. The founder's 2026-08-17 ruling is absolute — every
  -- refund at any amount reaches him — so refund_within_window now falls straight into the money rail.
  -- HARD RAILS: money, destructive, and supplier approval can never be auto-cleared by policy.
  if p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then return 'founder'; end if;
  if p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then return 'founder'; end if;
  if p_kind='approve_supplier' and coalesce(p_recommendation,'')='approve' then return 'clean_supplier'; end if;
  if p_kind='approve_supplier' then return 'founder'; end if;
  -- POLICY: founder-editable per-kind disposition.
  select value into pol from public.decision_policy where key='action_autonomy';
  d := pol->>p_kind;
  if d in ('ack','founder','keep') then return d; end if;
  -- LEGACY FALLBACK
  if p_kind in ('security_alert','compliance_update','incident','supply_health','sla_no_supply') then return 'ack'; end if;
  return 'keep';
end $function$;
