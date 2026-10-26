-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706101940   name: decision_policy_escalation
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ HUMAN ESCALATION FRAMEWORK ============
create table if not exists public.decision_policy(
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz default now());
alter table public.decision_policy enable row level security;
revoke all on public.decision_policy from anon, authenticated;

insert into public.decision_policy(key,value,description) values
 ('confidence_min', '0.6',
   'Below this model/router confidence (0-1), ask a clarifying question or escalate instead of acting.'),
 ('financial_review_aed', '10000',
   'Any single money-affecting action at/above this AED value requires human review.'),
 ('auto_action_max_aed', '0',
   'Maximum AED an agent may move/commit autonomously. 0 = agents never move money without a human.'),
 ('fraud_score_max', '0.7',
   'Fraud score (0-1) at/above which the item is held for human review.'),
 ('legal_triggers',
   '["contract change","liability","indemnity","termination","dispute","refund dispute","regulatory complaint","data subject request","subpoena","chargeback"]',
   'Phrases/topics that must route to Legal, never auto-answered.'),
 ('sensitive_categories',
   '["fire","security","electrical","structural","gas","lifts","medical"]',
   'Categories where safety/liability is high; low-confidence outputs must be reviewed.'),
 ('review_owner', '"Secretary"',
   'Default human/orchestrator that receives escalations.')
on conflict (key) do update set value=excluded.value, description=excluded.description, updated_at=now();

-- Reusable escalation gate. ctx keys (all optional):
--   confidence numeric, amount_aed numeric, category text, fraud_score numeric, text text, moves_money boolean
create or replace function public.fn_should_escalate(ctx jsonb)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
begin
  select value::numeric into conf_min   from decision_policy where key='confidence_min';
  select value::numeric into fin_review  from decision_policy where key='financial_review_aed';
  select value::numeric into auto_max    from decision_policy where key='auto_action_max_aed';
  select value::numeric into fraud_max   from decision_policy where key='fraud_score_max';
  select value into legal                from decision_policy where key='legal_triggers';
  select value into sens                 from decision_policy where key='sensitive_categories';
  select value #>> '{}' into owner       from decision_policy where key='review_owner';

  if c_conf is not null and c_conf < conf_min then
     reasons := reasons || format('confidence %.2f < min %.2f', c_conf, conf_min); end if;
  if c_amt is not null and c_amt >= fin_review then
     reasons := reasons || format('amount AED %s >= financial review threshold %s', c_amt, fin_review); end if;
  if c_money and (c_amt is null or c_amt > auto_max) then
     reasons := reasons || 'action moves money beyond autonomous limit'; end if;
  if c_fraud is not null and c_fraud >= fraud_max then
     reasons := reasons || format('fraud score %.2f >= max %.2f', c_fraud, fraud_max); end if;
  if c_cat <> '' and sens ? c_cat and (c_conf is null or c_conf < conf_min) then
     reasons := reasons || format('sensitive category "%s" with low/absent confidence', c_cat); end if;
  for trg in select jsonb_array_elements_text(legal) loop
     if c_txt <> '' and position(trg in c_txt) > 0 then
        reasons := reasons || format('legal trigger: "%s"', trg); end if;
  end loop;

  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', owner);
end $$;

-- Prose summary for agents (so they know the rules even without calling the fn)
delete from public.agent_knowledge where agent_key='_global' and topic='Escalation policy';
insert into public.agent_knowledge(agent_key, topic, content, priority) values
 ('_global','Escalation policy',
  'Escalation rules (call fn_should_escalate for the exact decision): (1) If your confidence is below 0.6, ask a clarifying question or escalate — never guess. (2) Any money-affecting action at or above AED 10,000 needs human review; agents never move money autonomously (auto limit = AED 0). (3) Fraud score >= 0.7 holds the item for review. (4) Legal topics (contract change, liability, indemnity, termination, disputes, refund disputes, regulatory complaints, data-subject requests, subpoenas, chargebacks) route to Legal and are never auto-answered. (5) Sensitive categories (fire, security, electrical, structural, gas, lifts, medical) with low confidence must be reviewed. Default escalation owner: Secretary.',
  950);
