-- ---------------------------------------------------------------------------------------------
-- OPERATIONS, ASSISTANCE, COMPANY AND REPORTS.
--
-- Operations and Assistance were never showing STALE rows. They were showing the SAME six
-- crm_tasks the stand-down had just cancelled, because both routines ask for
--   where coalesce(status,'') <> 'done'
-- which was correct while 'done' was the only terminal state and became wrong the moment
-- 'cancelled' existed. A cancelled task is not open work. Fixed in the predicate, not in the data,
-- because the data was already right - the same shape of defect as fn_ws_governance filtering on
-- "escalated" with no status filter at all.
--
-- Operations' task LIST had no status filter whatsoever: it ordered by "is it done" and printed
-- everything else, so a cancelled task sorted to the top and read as live work.
--
-- Company and Reports are different. They read history on purpose - 30-day escalation counts, the
-- report registry, evaluation snapshots - so they take the fresh-start watermark rather than a
-- status filter. Nothing is wrong with those rows. The founder does not want the old company on
-- the screen while the new chain of command is designed; he did not ask for its records to be
-- destroyed, and they are not.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_ws_operations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'ops', jsonb_build_object(
      'health', (select (kpis->>'ops_health')::numeric from ops_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from ops_kpis k),
      'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='operations_ai' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'security', jsonb_build_object(
      'score', (select (kpis->>'security_score')::numeric from security_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from security_kpis k),
      'incidents', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='security_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'severity',severity,'source',source,'at',created_at) order by created_at desc) from (select * from security_events order by created_at desc limit 10) e),'[]'::jsonb)
    ),
    'kpis', jsonb_build_object(
      'approvals_pending',(select count(*) from agent_actions where status='pending'),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      'tasks_open',(select count(*) from crm_tasks where coalesce(status,'open') not in ('done','cancelled')),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours'),
      'disputes',(select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending'))
    ),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,'risk',risk,'title',title,
        'policies', public.fn_action_policies(kind, confidence),
        'recommendation',recommendation,'status',status,'target_table',target_table,'created_at',created_at,
        'os', public.fn_owning_os(agent), 'confidence', confidence,
        'alternatives', (select d.alternatives from public.decision_log d where d.id = decision_log_id),
        'outcome', case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'still open, no decision recorded since ' || created_at::date end)) from (
        select * from agent_actions where status='pending' order by (coalesce(risk,'')='critical') desc, created_at desc limit 30) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'actor',actor,'kind',kind,'decision',decision,
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 20) d),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'source',source,'entity',entity)) from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by created_at desc limit 20) t),'[]'::jsonb)
  );
$function$;

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
        from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'open') not in ('done','cancelled') and due_date < now()),
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_ws_company()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'legal', jsonb_build_object(
      'health', (select (kpis->>'legal_health')::numeric from legal_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from legal_kpis k),
      'missing_docs', coalesce((select jsonb_agg(jsonb_build_object('requirement',requirement,'priority',priority,'applies_to',applies_to) order by priority) from legal_checklist where not present),'[]'::jsonb),
      'flags', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='legal_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'reviews', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',doc_kind,'risk',risk_level,'at',reviewed_at) order by reviewed_at desc) from (select * from legal_reviews order by reviewed_at desc limit 10) r),'[]'::jsonb)
    ),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'actions',c,'pending',pend,'last_active',la) order by c desc) from (
        select coalesce(agent,'—') agent, count(*) c,
               count(*) filter (where status='pending') pend, max(created_at) la
        from agent_actions group by 1 order by 2 desc limit 20) d),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'status',status,'started_at',started_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb),
    'evals', coalesce((select jsonb_agg(jsonb_build_object('snapshot_at',snapshot_at,'window_days',window_days,'kpis',kpis)) from (select * from agent_evals where snapshot_at >= public.fn_os_fresh_start_at() order by snapshot_at desc limit 4) e),'[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_ws_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    -- THE LATEST EXECUTIVE MEETING, IN SEQUENCE. exec_reports.findings is the ordered transcript of
    -- what each of the ten officers said; report_registry projects only title/period/id, so until
    -- now the body reached nothing the browser could run. `contributions` keeps the array order
    -- the meeting wrote it in — that order IS the replay.
    'meeting', (select jsonb_build_object(
        'id', r.id, 'period', r.period, 'officer', r.officer, 'summary', r.summary,
        'at', to_char(r.created_at,'YYYY-MM-DD HH24:MI'),
        'contributions', coalesce(r.findings, '[]'::jsonb),
        'priorities', coalesce(r.recommendations, '[]'::jsonb),
        'challenges', (select coalesce(jsonb_agg(jsonb_build_object(
              'proposal', c.proposal, 'by', c.challenged_by, 'of', c.proposed_by,
              'stance', c.stance, 'confidence', c.confidence, 'reasoning', c.reasoning,
              'alternatives', c.alternatives) order by c.id), '[]'::jsonb)
            from public.challenge_record c
           where c.created_at between r.created_at - interval '30 minutes'
                                  and r.created_at + interval '6 hours'))
      from public.exec_reports r where r.officer='ceo' and r.created_at >= public.fn_os_fresh_start_at() order by r.created_at desc limit 1),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select id, source, report_type, title, period,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 25) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, id, title,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, id, source, title, created_at
          from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by report_type, created_at desc
        ) x order by report_type) t),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$function$;
