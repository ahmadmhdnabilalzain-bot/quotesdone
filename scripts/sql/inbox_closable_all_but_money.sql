-- The founder's rule, applied literally: "there's not a single thing that requires my approval
-- except refunds. Nothing else, literally nothing else."
--
-- The first version of this list kept legal_flag, security_incident, customer_escalation,
-- compliance_update and the finance items as FOUNDER-only. That was my judgement, not his, and it
-- is what keeps a queue pointed at him. A legal flag is decided by the legal executive, a security
-- incident by security, a customer escalation by customer success -- that is what the 24
-- departments and 96 roles in the Company Operations pack are FOR.
--
-- What still cannot be closed by an employee is money. That protection does not live in this list
-- and never did: trg_action_gate maps any refund/payout/charge/payment/transfer kind to
-- issue_refund, which the 'agent' role does not hold, and run_agent_action carries
-- max_amount_aed 0 so anything with an amount attached is refused. Probed: ordinary action
-- permitted, refund needs_review, 25,000 AED payment needs_review.
create or replace function public.fn_agent_inbox_closable_kinds()
 returns text[]
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select array(
    select distinct kind from public.agent_actions
     where kind is not null
       and lower(kind) !~ '(refund|payout|charge|payment|transfer|chargeback)'
    union
    select unnest(array['handoff','improvement_question','knowledge_task','ai_improvement',
      'report_recommendation','ops_recommendation','doc_task','report_task','objective_step',
      'supply_health','autonomy_stall','legal_flag','security_incident','customer_escalation',
      'compliance_update','strategy_rec','marketing_recommendation','incident','prompt_approval',
      'decision.route_category','finance_alert','finance_marketing_budget'])
  );
$function$;
revoke execute on function public.fn_agent_inbox_closable_kinds() from public, anon, authenticated;
