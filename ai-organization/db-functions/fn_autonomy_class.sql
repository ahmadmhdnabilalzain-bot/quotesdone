CREATE OR REPLACE FUNCTION public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare pol jsonb; d text;
begin
  -- Policy-bounded carve-out (chairman doctrine 2026-07-24): a refund fully inside
  -- the published policy window is routine work, not an executive decision.
  if p_kind = 'refund_within_window' then return 'ack'; end if;
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
end $function$
