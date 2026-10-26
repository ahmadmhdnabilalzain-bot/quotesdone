CREATE OR REPLACE FUNCTION public.fn_ws_governance()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.governance_kpis k),
    'universal_rules', (select universal_rules from public.agent_governance where active order by version desc limit 1),
    'response_structure', (select response_structure from public.agent_governance where active order by version desc limit 1),
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select agent, title, coalesce(escalation_reason,'—') as reason, confidence,
               public.fn_action_policies(kind, confidence) as policies,
               public.fn_owning_os(agent) as os,
               (select d.alternatives from public.decision_log d where d.id = decision_log_id) as alternatives,
               case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'still open, no decision recorded since ' || created_at::date end as outcome,
               to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where escalated order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c)
  );
$function$
