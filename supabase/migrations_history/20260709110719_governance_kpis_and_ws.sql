-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709110719   name: governance_kpis_and_ws
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Governance / compliance posture across the whole agent fleet (one row)
create or replace view public.governance_kpis as
with agents as (select slug, persona from public.category_agents where active),
kn as (select distinct agent_key from public.agent_knowledge),
act30 as (select * from public.agent_actions where created_at > now()-interval '30 days')
select
  (select count(*) from agents) as active_agents,
  (select count(*) from agents where persona is not null and length(persona) > 40) as agents_with_persona,
  (select count(*) from public.agent_knowledge where agent_key='_global') as global_rules,
  (select count(*) from public.agent_knowledge) as knowledge_items,
  (select version from public.agent_governance where active order by version desc limit 1) as governance_version,
  (select count(*) from act30) as decisions_30d,
  (select count(*) from act30 where confidence is not null) as decisions_with_confidence,
  (select round(avg(confidence)::numeric,2) from act30 where confidence is not null) as avg_confidence,
  (select count(*) from act30 where escalated) as escalated_30d,
  (select count(*) from public.agent_actions where status in ('pending','needs_review')) as open_for_review,
  (select count(*) from public.agent_actions) as audit_trail_total,
  (select count(distinct agent) from public.agent_actions) as agents_with_audit_trail;

-- Workspace payload for the Governance module
create or replace function public.fn_ws_governance()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.governance_kpis k),
    'universal_rules', (select universal_rules from public.agent_governance where active order by version desc limit 1),
    'response_structure', (select response_structure from public.agent_governance where active order by version desc limit 1),
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select agent, title, coalesce(escalation_reason,'—') as reason, confidence, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where escalated order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c)
  );
$$;
revoke all on function public.fn_ws_governance() from anon, authenticated, public;
