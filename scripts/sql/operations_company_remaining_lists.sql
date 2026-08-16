-- ---------------------------------------------------------------------------------------------
-- THE READING SITES THE FIRST PASS MISSED ON OPERATIONS AND COMPANY.
--
-- Fixing the task predicates cleared the tiles the founder pointed at and left four lists beside
-- them still showing the old company:
--
--   Operations · decisions_24h        44, of which 1 is after the reset - a wall-clock 24h window
--                                     straddling the watermark
--   Operations · decisions list       20 rows, no filter of any kind
--   Operations · security events      10 rows, none of them after the reset
--   Company    · departments bar      2,839 LIFETIME actions across 20 departments
--   Company    · recent agent runs    12 rows
--   Company    · missing legal docs   5
--
-- Every one is a count over history with no bound. They take the same fresh-start watermark as the
-- rest; none of the rows is deleted or altered.
--
-- TWO THINGS ARE DELIBERATELY LEFT ALONE, because clearing them would be hiding rather than
-- resetting:
--
--   Company · missing legal documents (5). These are not events that happened, they are documents
--   that DO NOT EXIST - legal_checklist rows where present = false. A watermark cannot make a
--   missing document present, and dating it out of view would tell him the company is compliant
--   when it is not. It stays.
--
--   Company · recent agent runs. Nine of the twelve are AFTER the reset: they are the watcher crons
--   the stand-down deliberately left running - backup, uptime, health. Showing them is correct.
--   The list is watermarked anyway so the three older rows drop, and what remains is true.
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
      'events', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'severity',severity,'source',source,'at',created_at) order by created_at desc) from (select * from security_events where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 10) e),'[]'::jsonb)
    ),
    'kpis', jsonb_build_object(
      'approvals_pending',(select count(*) from agent_actions where status='pending'),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      'tasks_open',(select count(*) from crm_tasks where coalesce(status,'open') not in ('done','cancelled')),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours' and created_at >= public.fn_os_fresh_start_at()),
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
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 20) d),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'source',source,'entity',entity)) from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by created_at desc limit 20) t),'[]'::jsonb)
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
        from agent_actions where created_at >= public.fn_os_fresh_start_at() group by 1 order by 2 desc limit 20) d),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'status',status,'started_at',started_at,'note',note)) from (select * from agent_runs where started_at >= public.fn_os_fresh_start_at() order by started_at desc limit 12) r),'[]'::jsonb),
    'evals', coalesce((select jsonb_agg(jsonb_build_object('snapshot_at',snapshot_at,'window_days',window_days,'kpis',kpis)) from (select * from agent_evals where snapshot_at >= public.fn_os_fresh_start_at() order by snapshot_at desc limit 4) e),'[]'::jsonb)
  );
$function$;
