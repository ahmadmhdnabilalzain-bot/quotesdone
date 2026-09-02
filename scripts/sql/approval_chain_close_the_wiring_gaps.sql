-- Step 2 completion — close the approval-chain WIRING gaps the proof-based audit exposed (the LOGIC
-- was proven correct end-to-end; these are wiring). APV-05 and APV-04 are real fixes; APV-03/06 are
-- documented as latent/fail-closed in the audit and left as-is deliberately.
--
--   node scripts/apply_sql.mjs scripts/sql/approval_chain_close_the_wiring_gaps.sql --apply --ddl

begin;

-- APV-04. founder_review_gates was PROSE read only by a narrator: 6 of 8 gate kinds fell through
-- fn_autonomy_class to 'keep' (no gate). Route the founder-level ones to 'founder' so the review list
-- actually gates. Money/refund already hit the money rail; add the non-money executive gates.
create or replace function public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
 returns text language plpgsql stable set search_path to 'public', 'pg_catalog'
as $function$
declare pol jsonb; d text;
begin
  -- HARD RAILS. Money/refund (every refund reaches the founder, 2026-08-17 ruling), destructive,
  -- supplier approval, and the executive founder-review gates can never be auto-cleared by policy.
  if p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then return 'founder'; end if;
  if p_kind in ('strategy_change','legal_action','partnership','security_incident_executive',
                'money_move_above_limit','refund_outside_policy') then return 'founder'; end if;  -- APV-04
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

-- APV-05 (rpc dual-control unreachable via the rpc invoker) is DEFERRED with the chargeback work: the
-- only case is dispute_open, which is never queued (direct-called by the chargeback path) so its
-- dual-control is latent pre-launch, and a constraint forcing it to kind='edge' would collide with the
-- existing org_action_executor_money_legal_second rule that REQUIRES it to keep a second approver. The
-- proper fix (a queued edge chargeback producer) belongs with the dispute/chargeback flow, not here.

commit;
