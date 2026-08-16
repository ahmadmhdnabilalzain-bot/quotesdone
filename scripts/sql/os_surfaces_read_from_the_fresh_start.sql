-- ---------------------------------------------------------------------------------------------
-- EVERY FOUNDER-FACING ESCALATION SURFACE READS FROM THE FRESH-START WATERMARK.
--
-- The audit found EIGHT surfaces showing him escalations, not the three that were known. Patching
-- three would have produced a "clean" console and a Governance board still listing July. All five
-- founder-facing readers are patched here; each one gains the same single predicate,
-- created_at >= public.fn_os_fresh_start_at(), and nothing else changes.
--
-- Because fn_os_fresh_start_at() returns '-infinity' when no reset exists, every one of these
-- functions is byte-for-byte equivalent to its old behaviour on a database that has never been
-- reset. The watermark can only ever hide, never invent, and moving it back restores everything.
--
-- fn_ws_governance gets a second fix at the same time: its escalation list filtered on `escalated`
-- with NO status filter at all, so a decided, closed, months-old action still counted as a live
-- escalation. That was true before this session and is the reason a bulk close would have left
-- that board reading 15. It now requires the action to be open as well.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_founder_queue(p_limit integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'waiting_on_you_total',
      (select count(*) from public.agent_actions a
         join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
        where a.status in ('pending','needs_review')
          and a.created_at >= public.fn_os_fresh_start_at()),
    'oldest_days',
      (select round(extract(epoch from now() - min(a.created_at)) / 86400)::int
         from public.agent_actions a
         join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
        where a.status in ('pending','needs_review')
          and a.created_at >= public.fn_os_fresh_start_at()),
    'waiting_on_you', coalesce((
      select jsonb_agg(x order by x->>'raised')
        from (select jsonb_build_object(
                       'id', a.id, 'kind', a.kind,
                       'kind_label', public.fn_ui_label('action_kind', a.kind),
                       'from', a.agent,
                       'title', left(coalesce(a.title, a.recommendation, ''), 160),
                       'raised', a.created_at,
                       'age_days', round(extract(epoch from now() - a.created_at) / 86400)::int) as x
                from public.agent_actions a
                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
               where a.status in ('pending','needs_review')
                 and a.created_at >= public.fn_os_fresh_start_at()
               order by a.created_at
               limit greatest(coalesce(p_limit, 12), 1)) z), '[]'::jsonb),
    -- The machine's own work in flight, kept separate so the two are never added together again.
    'machine_is_working_on', (select count(*) from public.agent_actions a
                                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                               where a.status = 'pending'
                                 and a.created_at >= public.fn_os_fresh_start_at()),
    -- A kind nobody has classified. Fail-closed and NAMED: the sweep will not queue it and the
    -- worker will not settle it, so if this list is not empty, work is sitting still and this is
    -- the only place that says so.
    'unrouted_kinds', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k,
                                          'kind_label', public.fn_ui_label('action_kind', k),
                                          'pending', n, 'oldest_days', d))
        from (select a.kind k, count(*) n,
                     round(extract(epoch from now() - min(a.created_at)) / 86400)::int d
                from public.agent_actions a
               where a.status = 'pending'
                 and a.created_at >= public.fn_os_fresh_start_at()
                 and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)
               group by a.kind order by 2 desc) y), '[]'::jsonb),
    'fresh_start_at', public.fn_os_fresh_start_at());
$function$;

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
                   and created_at > now() - interval '7 days'
                   and created_at >= public.fn_os_fresh_start_at())
             + (select count(*) from public.agent_actions
                 where status in ('pending','needs_review') and lower(coalesce(risk,'')) = 'critical'
                   and created_at >= public.fn_os_fresh_start_at()),
      -- THE ROW LIST HAD NO TIME FILTER AT ALL while its count had a 7-day one, so the list showed
      -- alerts older than the number above it claimed to measure. Both now share one window.
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.event, 'detail', left(a.detail::text, 200),
                          'level', a.level, 'at', a.created_at) order by a.created_at desc)
                from (select * from public.founder_alerts
                       where lower(coalesce(level,'')) in ('critical','high')
                         and created_at > now() - interval '7 days'
                         and created_at >= public.fn_os_fresh_start_at()
                       order by created_at desc limit 8) a), '[]'::jsonb)),

    -- IMPORTANT — waiting on the founder, but not critical.
    'important', jsonb_build_object(
      'tier', 'important',
      'count', (select count(*) from public.agent_actions
                 where status in ('pending','needs_review')
                   and lower(coalesce(risk,'')) in ('high','medium')
                   and created_at >= public.fn_os_fresh_start_at()),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'detail', left(coalesce(a.recommendation,''), 200),
                          'risk', a.risk, 'agent', a.agent, 'at', a.created_at) order by a.created_at desc)
                from (select * from public.agent_actions
                       where status in ('pending','needs_review') and lower(coalesce(risk,'')) in ('high','medium')
                         and created_at >= public.fn_os_fresh_start_at()
                       order by created_at desc limit 8) a), '[]'::jsonb)),

    -- SUGGESTED — nothing is blocked, but the company thinks the founder should look.
    'suggested', jsonb_build_object(
      'tier', 'suggested',
      'count', (select count(*) from public.opportunity where status = 'open'
                 and created_at >= public.fn_os_fresh_start_at())
             + (select count(*) from public.evolution_proposal where status = 'proposed'
                 and created_at >= public.fn_os_fresh_start_at()),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', o.title, 'detail', left(coalesce(o.detail,''), 200),
                          'kind', o.kind, 'at', o.created_at) order by o.value_score desc nulls last)
                from (select * from public.opportunity where status = 'open'
                       and created_at >= public.fn_os_fresh_start_at()
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
    -- Deliberately NOT watermarked: it is a measure of the machine's behaviour over a real time
    -- window, not a list of his outstanding work, and truncating its denominator at the reset would
    -- make it read 100% of 0 on the first day.
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
    'fresh_start_at', public.fn_os_fresh_start_at(),
    'generated_at', now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_inbox_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'needs_review', (select count(*) from public.inbound_messages where needs_review=true and replied_at is null
                        and created_at >= public.fn_os_fresh_start_at()),
      'untriaged', (select count(*) from public.inbound_messages where needs_review=true and triaged_at is null and replied_at is null
                     and created_at >= public.fn_os_fresh_start_at()),
      'replied_7d', (select count(*) from public.inbound_messages where replied_at > now()-interval '7 days')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'from_email',from_email,'subject',subject,'body',left(coalesce(body,''),1200),
        'category',ai_category,'summary',ai_summary,'draft',ai_draft_reply,
        'triaged_at',triaged_at,'created_at',created_at) order by created_at desc)
      from (select * from public.inbound_messages
             where needs_review=true and replied_at is null
               and created_at >= public.fn_os_fresh_start_at()
             order by created_at desc limit 50) m),'[]'::jsonb)
  );
$function$;

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
    -- TWO FIXES. The watermark, and a status filter that was never here: this list selected on
    -- `escalated` alone, so an action decided and closed in July still counted as a live
    -- escalation on the governance board. An escalation that has been answered is not an
    -- escalation.
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select agent, title, coalesce(escalation_reason,'—') as reason, confidence,
               public.fn_action_policies(kind, confidence) as policies,
               public.fn_owning_os(agent) as os,
               (select d.alternatives from public.decision_log d where d.id = decision_log_id) as alternatives,
               case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'still open, no decision recorded since ' || created_at::date end as outcome,
               to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where escalated
          and status in ('pending','needs_review')
          and created_at >= public.fn_os_fresh_start_at()
        order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c),
    'fresh_start_at', public.fn_os_fresh_start_at()
  );
$function$;
