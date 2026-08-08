-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706120859   name: ai_governance_gate_and_twins
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ AI GOVERNANCE ENFORCEMENT GATE (Constitution, technical) ============
-- Every consequential AI answer/action can be run through this before it is emitted.
create or replace function public.fn_ai_gate(
  p_answer text, p_sources jsonb default '[]', p_confidence numeric default null,
  p_action text default 'run_agent_action', p_actor text default 'agent', p_attrs jsonb default '{}')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare g jsonb; a jsonb; esc jsonb; conf_min numeric; viol text[]:='{}'; approved boolean; route text;
begin
  g := public.fn_require_grounding(p_answer, p_sources);
  if not (g->>'grounded')::boolean then viol := array_append(viol,'ungrounded: retrieve knowledge and cite a source'); end if;
  select value::numeric into conf_min from decision_policy where key='confidence_min';
  if p_confidence is not null and p_confidence < coalesce(conf_min,0.6) then
     viol := array_append(viol,'low_confidence: below '||coalesce(conf_min,0.6)||' — ask a clarifying question or escalate'); end if;
  a := public.fn_authorize(p_actor, p_action, p_attrs);
  if not (a->>'allowed')::boolean then viol := array_append(viol,'unauthorized: '||(a->>'reason')); end if;
  esc := public.fn_should_escalate(p_attrs || jsonb_build_object('confidence',p_confidence));
  route := esc->>'route_to';
  approved := (array_length(viol,1) is null) and not (esc->>'escalate')::boolean;
  -- log the governance decision (immutable)
  insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,'ai_gate', jsonb_build_object('action',p_action,'attrs',p_attrs),
          case when approved then 'approved' else 'blocked' end, p_confidence,
          to_jsonb(viol || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]')))), p_sources, route);
  return jsonb_build_object('approved',approved,'violations',to_jsonb(viol),
    'grounding',g,'authorization',a,'escalation',esc,'route_to',route,
    'directive', case when approved then 'emit' when (esc->>'escalate')::boolean then 'escalate to '||coalesce(route,'Secretary') else 'revise before emitting' end);
end $$;

-- global rule so agents know the gate exists and what passing requires
delete from public.agent_knowledge where agent_key='_global' and topic='AI governance gate';
insert into public.agent_knowledge(agent_key,topic,content,priority) values
 ('_global','AI governance gate',
  'Before emitting a consequential answer or taking an action, it must pass the governance gate: (1) grounded in retrieved knowledge with a cited source, (2) confidence at or above 0.6, (3) authorized for your role (RBAC/ABAC), (4) not tripping an escalation trigger (financial/legal/fraud/sensitive). If any check fails: revise and re-ground, ask a clarifying question, or escalate to the Secretary — never emit an ungrounded, low-confidence, or unauthorized action.',
  990);

-- ============ DIGITAL TWINS (customer / rfq / category / company) ============
create or replace function public.fn_twin(p_kind text, p_id text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare res jsonb;
begin
  if p_kind='customer' then
    select jsonb_build_object('kind','customer','id',c.id,'name',c.full_name,'email',c.email,
      'rfqs',(select count(*) from inquiries where customer_id=c.id),
      'deals',(select count(*) from transactions where customer_id=c.id),
      'spend_aed',(select coalesce(sum(reveal_fee),0) from transactions where customer_id=c.id and coalesce(fee_status,'')='paid'),
      'categories',(select coalesce(jsonb_agg(distinct category),'[]') from inquiries where customer_id=c.id),
      'last_active',(select max(created_at) from inquiries where customer_id=c.id),
      'banned',c.banned) into res from customers c where c.id::text=p_id;

  elsif p_kind='rfq' then
    select jsonb_build_object('kind','rfq','id',i.id,'category',i.category,'emirate',i.emirate,'status',i.status,
      'completeness',i.completeness,'ready',i.rfq_ready,'budget',i.budget,
      'quotes',(select count(*) from quotes where inquiry_id=i.id),
      'avg_quote_quality',(select round(avg(nullif(quality->>'score','')::numeric),1) from quotes where inquiry_id=i.id),
      'matched_suppliers',(select count(*) from inquiry_matches where inquiry_id=i.id),
      'created',i.created_at,'completed',i.completed_at,'outcome',i.outcome) into res from inquiries i where i.id::text=p_id;

  elsif p_kind='category' then
    res := jsonb_build_object('kind','category','category',p_id,
      'demand_rfqs',(select count(*) from inquiries where category=p_id),
      'approved_suppliers',(select count(*) from leads where coalesce(approval_status,'')='approved' and (lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_id)||'%')),
      'supplier_pool_total',(select count(*) from leads where lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_id)||'%'),
      'avg_quote_quality',(select round(avg(nullif(q.quality->>'score','')::numeric),1) from quotes q join inquiries i on i.id=q.inquiry_id where i.category=p_id),
      'agent',public.fn_resolve_cat_agent(p_id));

  elsif p_kind='company' then
    res := jsonb_build_object('kind','company','name','QuotesDone',
      'health',public.fn_health_index(),
      'suppliers_total',(select count(*) from leads),'suppliers_approved',(select count(*) from leads where coalesce(approval_status,'')='approved'),
      'customers',(select count(*) from customers),'rfqs',(select count(*) from inquiries),'quotes',(select count(*) from quotes),
      'revenue_paid_aed',(select coalesce(sum(reveal_fee),0) from transactions where coalesce(fee_status,'')='paid'),
      'eval',public.fn_eval_snapshot(30));
  else
    res := jsonb_build_object('error','kind must be customer|rfq|category|company');
  end if;
  return coalesce(res, jsonb_build_object('error','not found','kind',p_kind,'id',p_id));
end $$;

select public.fn_ai_gate('It should be fine, just approve it.','[]'::jsonb,0.4,'issue_refund','agent','{"amount_aed":5000}'::jsonb) as gate_blocks,
       public.fn_twin('company') as company_twin;
