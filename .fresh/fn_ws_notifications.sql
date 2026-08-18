CREATE OR REPLACE FUNCTION public.fn_ws_notifications()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    -- CRITICAL — a founder alert raised at critical/high, or a critical action still waiting.
    'critical', jsonb_build_object(
      'tier', 'critical',
      'count', (select count(*) from public.founder_alerts
                 where lower(coalesce(level,'')) in ('critical','high')
                   and created_at > now() - interval '7 days')
             + (select count(*) from public.agent_actions
                 where status in ('pending','needs_review') and lower(coalesce(risk,'')) = 'critical'),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.event, 'detail', left(a.detail::text, 200),
                          'level', a.level, 'at', a.created_at) order by a.created_at desc)
                from (select * from public.founder_alerts
                       where lower(coalesce(level,'')) in ('critical','high')
                       order by created_at desc limit 8) a), '[]'::jsonb)),

    -- IMPORTANT — waiting on the founder, but not critical.
    'important', jsonb_build_object(
      'tier', 'important',
      'count', (select count(*) from public.agent_actions
                 where status in ('pending','needs_review')
                   and lower(coalesce(risk,'')) in ('high','medium')),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'detail', left(coalesce(a.recommendation,''), 200),
                          'risk', a.risk, 'agent', a.agent, 'at', a.created_at) order by a.created_at desc)
                from (select * from public.agent_actions
                       where status in ('pending','needs_review') and lower(coalesce(risk,'')) in ('high','medium')
                       order by created_at desc limit 8) a), '[]'::jsonb)),

    -- SUGGESTED — nothing is blocked, but the company thinks the founder should look.
    'suggested', jsonb_build_object(
      'tier', 'suggested',
      'count', (select count(*) from public.opportunity where status = 'open')
             + (select count(*) from public.evolution_proposal where status = 'proposed'),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', o.title, 'detail', left(coalesce(o.detail,''), 200),
                          'kind', o.kind, 'at', o.created_at) order by o.value_score desc nulls last)
                from (select * from public.opportunity where status = 'open'
                       order by value_score desc nulls last limit 6) o), '[]'::jsonb)),

    -- COMPLETED TODAY — closed since midnight, whoever closed it.
    'completed_today', jsonb_build_object(
      'tier', 'completed_today',
      'count', (select count(*) from public.agent_actions where decided_at::date = current_date),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'status', a.status,
                          'decided_by', a.decided_by, 'at', a.decided_at) order by a.decided_at desc)
                from (select * from public.agent_actions where decided_at::date = current_date
                       order by decided_at desc limit 8) a), '[]'::jsonb)),

    -- THE SHARE THE AI HANDLED WITHOUT THE FOUNDER. Not a boast: an action that was never escalated
    -- is one the founder never had to see, and that ratio is the whole promise of the OS.
    'auto_cleared_24h', (select round(100.0 * count(*) filter (where coalesce(escalated, false) = false)
                                 / greatest(count(*), 1))
                           from public.agent_actions where created_at > now() - interval '24 hours'),
    'auto_handled_30d', (select round(100.0 * count(*) filter (where coalesce(escalated, false) = false)
                                 / greatest(count(*), 1))
                           from public.agent_actions where created_at > now() - interval '30 days'),
    'actions_24h', (select count(*) from public.agent_actions where created_at > now() - interval '24 hours'),
    'actions_30d', (select count(*) from public.agent_actions where created_at > now() - interval '30 days'),
    -- The outbound queue, which is what public.notifications actually is.
    'outbound_queue', (select count(*) from public.notifications where coalesce(status,'') not in ('sent','delivered')),
    'generated_at', now()
  );
$function$
