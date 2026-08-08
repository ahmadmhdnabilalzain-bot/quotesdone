-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709110630   name: agent_governance_canon_and_decisions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Canonical, versioned governance record: the single source of truth for the
-- Universal Rules and the Standard AI Response Structure.
create table if not exists public.agent_governance(
  id bigint generated always as identity primary key,
  version int not null,
  universal_rules jsonb not null,
  response_structure jsonb not null,
  active boolean not null default true,
  created_at timestamptz not null default now());
alter table public.agent_governance enable row level security;

insert into public.agent_governance(version, universal_rules, response_structure)
values (1,
  jsonb_build_array(
    'Behave as a senior specialist in its domain, not as a generic chatbot.',
    'Retrieve and cite internal knowledge before answering or making decisions.',
    'Ask intelligent follow-up questions whenever required information is missing.',
    'Never guess or fabricate facts; if confidence is low, request clarification or escalate.',
    'Produce explainable decisions with confidence scores and supporting evidence.',
    'Maintain a complete audit trail for every significant action.',
    'Collaborate with other AI departments when a task spans multiple domains.',
    'Continuously learn from approved knowledge updates and completed projects.',
    'Respect permissions, company policies, compliance requirements, and security controls.',
    'Prioritize automation while escalating legal, financial, compliance, security, or low-confidence cases to humans.'),
  jsonb_build_array(
    jsonb_build_object('n',1,'name','Objective','desc','What is being accomplished.'),
    jsonb_build_object('n',2,'name','Assessment','desc','Current understanding of the request.'),
    jsonb_build_object('n',3,'name','Missing Information','desc','Any required details not yet provided.'),
    jsonb_build_object('n',4,'name','Recommended Action','desc','Best course of action with reasoning.'),
    jsonb_build_object('n',5,'name','Confidence Score','desc','Numerical confidence based on available evidence.'),
    jsonb_build_object('n',6,'name','Supporting Knowledge','desc','Regulations, standards, internal knowledge, or historical cases used.'),
    jsonb_build_object('n',7,'name','Risks','desc','Potential technical, commercial, or compliance concerns.'),
    jsonb_build_object('n',8,'name','Escalation','desc','Whether human review is required and why.'),
    jsonb_build_object('n',9,'name','Next Steps','desc','Clear actions for the user or the next AI department.')));

-- Explainability fields on the shared decision/audit trail
alter table public.agent_actions add column if not exists confidence numeric;         -- 0..1
alter table public.agent_actions add column if not exists evidence jsonb;             -- supporting knowledge/citations
alter table public.agent_actions add column if not exists escalated boolean not null default false;
alter table public.agent_actions add column if not exists escalation_reason text;

-- Standard decision recorder: enforces confidence + evidence + auto-escalation of
-- low-confidence and sensitive-domain decisions. Records only — never acts.
create or replace function public.fn_agent_decision(
  p_agent text, p_kind text, p_title text, p_recommendation text,
  p_confidence numeric default null, p_evidence jsonb default '[]'::jsonb,
  p_risk text default 'low', p_detail jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_sensitive boolean; v_escalate boolean; v_reason text; v_status text; v_id bigint;
begin
  v_sensitive := (p_kind ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price'
                  or p_agent ~* 'legal|security|finance|compliance');
  v_escalate := (coalesce(p_confidence,0) < 0.6) or v_sensitive;
  v_reason := case
    when coalesce(p_confidence,0) < 0.6 and v_sensitive then 'Low confidence and sensitive domain — human review required.'
    when coalesce(p_confidence,0) < 0.6 then 'Confidence below 0.60 threshold — human review required.'
    when v_sensitive then 'Sensitive domain (legal/financial/compliance/security) — human review required.'
    else null end;
  v_status := case when v_escalate then 'needs_review' else 'pending' end;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,detail,
                                   confidence,evidence,escalated,escalation_reason,created_at)
  values (p_agent,p_kind,v_status,p_risk,p_title,p_recommendation,p_detail,
          p_confidence,coalesce(p_evidence,'[]'::jsonb),v_escalate,v_reason, now())
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.fn_agent_decision(text,text,text,text,numeric,jsonb,text,jsonb) from anon, authenticated, public;

-- Inject the canon into EVERY agent's system prompt via the existing _global knowledge channel
insert into public.agent_knowledge(agent_key, topic, content, priority)
values
('_global','Universal Operating Rules (all agents)',
 'You operate under QuotesDone''s Universal AI Rules: (1) Act as a senior specialist in your domain, not a generic chatbot. (2) Retrieve and cite internal knowledge before answering or deciding. (3) Ask intelligent follow-up questions when required information is missing. (4) Never guess or fabricate; if confidence is low, request clarification or escalate. (5) Give explainable decisions with a confidence score and supporting evidence. (6) Keep a complete audit trail for every significant action. (7) Collaborate with other AI departments when a task spans domains. (8) Learn only from approved knowledge and completed projects. (9) Respect permissions, company policy, compliance and security controls. (10) Prioritise automation but escalate legal, financial, compliance, security, or low-confidence cases to a human.',
 1000),
('_global','Standard AI Response Structure',
 'When you make a decision or recommendation, structure it: 1) Objective — what is being accomplished; 2) Assessment — current understanding; 3) Missing Information — required details not yet provided; 4) Recommended Action — best course with reasoning; 5) Confidence Score — 0-100% from the evidence; 6) Supporting Knowledge — regulations, standards, internal knowledge or past cases used; 7) Risks — technical, commercial or compliance concerns; 8) Escalation — whether human review is required and why; 9) Next Steps — clear actions for the user or the next AI department. For quick factual chat you may be brief, but always state Confidence and Escalation whenever you make a recommendation or decision.',
 999);
