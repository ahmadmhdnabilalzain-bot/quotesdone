CREATE OR REPLACE FUNCTION public.fn_ea_agenda(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'as_of', now(),
    'today', jsonb_build_object(
      'events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location,'attendees',attendees) order by starts_at)
          from ea_events where status='scheduled' and coalesce(starts_at, now())::date = current_date),'[]'::jsonb),
      'reminders_due', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'remind_at',remind_at) order by remind_at)
          from ea_reminders where not done and remind_at <= now()+interval '1 day'),'[]'::jsonb)
    ),
    'upcoming_events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location) order by starts_at)
        from ea_events where status='scheduled' and starts_at > current_date and starts_at <= (current_date + (p_days||' days')::interval)),'[]'::jsonb),
    'open_tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'priority',priority,'due',due_date,'source',source) order by (due_date is null), due_date)
        from (select * from crm_tasks where coalesce(status,'')<>'done' order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()),
    'approvals_to_clear', jsonb_build_object(
      'total',(select count(*) from agent_actions where status in ('pending','needs_review')),
      'high_risk',(select count(*) from agent_actions where status in ('pending','needs_review') and coalesce(risk,'') in ('high','critical')),
      'top', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'title',title,'risk',risk,
            'reason', coalesce(nullif(btrim(recommendation),''), nullif(btrim(escalation_reason),''), 'queued for founder review: ' || coalesce(kind,'action')),
            'policies', public.fn_action_policies(kind, confidence),
            'confidence', confidence,
            'os', public.fn_owning_os(agent),
            'alternatives', (select d.alternatives from public.decision_log d where d.id = decision_log_id),
            'outcome', case when decided_at is not null
                 then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
                 else 'still open, no decision recorded since ' || created_at::date end)
          order by (coalesce(risk,'')='high') desc, created_at desc)
          from (select * from agent_actions where status in ('pending','needs_review') order by (coalesce(risk,'')='high') desc, created_at desc limit 8) a),'[]'::jsonb)
    ),
    'recent_meetings', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meeting_at',meeting_at,'summary',left(summary,240)) order by meeting_at desc)
        from (select * from ea_meetings order by meeting_at desc limit 5) m),'[]'::jsonb)
  );
$function$
